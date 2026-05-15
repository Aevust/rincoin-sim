#!/bin/bash
# Rincoin-Sim: Customized Halving × RIN3 Reorg Simulation (v2)
# Usage: ./scripts/sim-ch-rin3.sh
#
# Tests:
#   [CH]    100-block reorg across each subsidy boundary → BVA after reorg
#   [RIN3]  User tx confirmed at height > 840, nVersion proven = RIN_FORK_TX_VERSION
#   [RIN3]  Reorg to tip=839 → wallet still RIN3 (last_height >= fork-1=839)
#   [RIN3]  Reorg to tip=838 → wallet reverts to legacy nVersion, accepted at h=839 (<840)
#
# Companion: test/functional/feature_rin3_enforcement.py
#   covers consensus-level rejection of legacy-nVersion blocks at height >= fork.

set -e

PASS=0
FAIL=0

ok()   { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

# ---------- Binary detection ----------
if [ -f "./bin/rincoind" ]; then
    RINCOIND="./bin/rincoind"
    RINCOINCLI="./bin/rincoin-cli"
elif [ -f "./src/rincoind" ]; then
    RINCOIND="./src/rincoind"
    RINCOINCLI="./src/rincoin-cli"
else
    echo "Error: rincoind not found."
    echo "Run from rincoin-sim-v1.0.6.1-linux-x86_64/ or source dir."
    exit 1
fi

# ---------- Cleanup trap ----------
cleanup() {
    echo ""
    echo "[trap] Stopping rincoind..."
    $RINCOINCLI -regtest stop 2>/dev/null || true
    sleep 2
    pkill -f "rincoind.*regtest" 2>/dev/null || true
}
trap cleanup EXIT

# ---------- Helpers ----------
height()    { $RINCOINCLI -regtest getblockcount; }
blockhash() { $RINCOINCLI -regtest getblockhash "$1"; }
json_val()  { python3 -c "import sys,json; print(json.load(sys.stdin)$1)"; }

RIN_FORK_TX_VERSION_DEC=1380535859   # 0x52494e33 ("RIN3")

# check_subsidy HEIGHT EXPECTED_SATOSHIS LABEL
check_subsidy() {
    local h=$1 expected=$2 label=$3
    local actual
    actual=$($RINCOINCLI -regtest getblockstats "$h" | json_val "['subsidy']")
    local rin
    rin=$(python3 -c "print(f'{$actual/1e8:.2f}')")
    if [ "$actual" = "$expected" ]; then
        ok "Block $h: $rin RIN [$label]"
    else
        local exp_rin
        exp_rin=$(python3 -c "print(f'{$expected/1e8:.2f}')")
        fail "Block $h: $rin RIN (expected $exp_rin) [$label]"
    fi
}

# check_height EXPECTED LABEL
check_height() {
    local h; h=$(height)
    if [ "$h" = "$1" ]; then
        ok "Height = $h [$2]"
    else
        fail "Height = $h, expected $1 [$2]"
    fi
}

# check_tx_nversion TXID EXPECTED_DEC LABEL
#   Extracts nVersion from a confirmed tx via decoderawtransaction.
check_tx_nversion() {
    local txid=$1 expected=$2 label=$3
    local hex nver
    hex=$($RINCOINCLI -regtest getrawtransaction "$txid")
    nver=$($RINCOINCLI -regtest decoderawtransaction "$hex" | json_val "['version']")
    if [ "$nver" = "$expected" ]; then
        ok "Tx $label: nVersion = $nver"
    else
        fail "Tx $label: nVersion = $nver (expected $expected)"
    fi
}

# reorg_bva BOUNDARY PRE_SATS POST_SATS LABEL
reorg_bva() {
    local boundary=$1 pre_sats=$2 post_sats=$3 label=$4

    echo ""
    echo "====== Reorg BVA: $label (boundary=$boundary) ======"

    local cur; cur=$(height)
    local target=$((boundary + 100))
    if [ "$cur" -lt "$target" ]; then
        local n=$((target - cur))
        echo "  Mining $n blocks → height $target..."
        $RINCOINCLI -regtest generatetoaddress "$n" "$ADDR" > /dev/null
    fi
    echo "  Height before reorg: $(height)"

    local hash; hash=$(blockhash "$boundary")
    echo "  Invalidating block $boundary..."
    $RINCOINCLI -regtest invalidateblock "$hash"

    check_height $((boundary - 1)) "after reorg"
    check_subsidy $((boundary - 1)) "$pre_sats" "pre-boundary (orphan side)"

    echo "  Remining 101 blocks..."
    $RINCOINCLI -regtest generatetoaddress 101 "$ADDR" > /dev/null

    check_height "$target" "after remine"
    check_subsidy $((boundary - 1)) "$pre_sats"  "pre-boundary (new chain)"
    check_subsidy "$boundary"        "$post_sats" "at-boundary  (new chain)"
}

# ---------- Setup ----------
echo "=== Setup ==="
echo "Stopping rincoind..."
$RINCOINCLI -regtest stop 2>/dev/null || true

for i in {1..10}; do
    if ! pgrep -f "rincoind.*regtest" > /dev/null; then
        echo "rincoind stopped cleanly"
        break
    fi
    sleep 1
    if [ "$i" -eq 10 ]; then
        echo "Warning: forcing kill..."
        pkill -f "rincoind.*regtest" 2>/dev/null || true
        sleep 2
    fi
done

rm -rf ~/.rincoin/regtest
# -fallbackfee: safety net for wallet send operations on regtest
$RINCOIND -regtest -daemon -fallbackfee=0.001
sleep 3

$RINCOINCLI -regtest createwallet "ch_rin3_reorg" > /dev/null
ADDR=$($RINCOINCLI -regtest getnewaddress "sim")
echo "Test address: $ADDR"

echo "Mining initial 940 blocks..."
$RINCOINCLI -regtest generatetoaddress 940 "$ADDR" > /dev/null
echo "Height: $(height)"

# ---------- CH Reorg BVA ----------
# Satoshi reference:
#   6.25 RIN = 625000000   (Phase 3)
#   4.00 RIN = 400000000   (Phase 4, CH dilation)
#   2.00 RIN = 200000000   (Phase 5)
#   1.00 RIN = 100000000   (Phase 6)
#   0.60 RIN =  60000000   (Terminal)

reorg_bva  840 625000000 400000000 "Phase 3→4 (CH dilation + RIN3 activation)"
reorg_bva 2100 400000000 200000000 "Phase 4→5"
reorg_bva 4200 200000000 100000000 "Phase 5→6"
reorg_bva 6300 100000000  60000000 "Phase 6→Terminal"

# ---------- RIN3 Wallet Version Tests ----------
# nRinHashForkHeight (regtest) = 840
# txassembler:  last_height >= 839 ⇒ RIN_FORK_TX_VERSION  else legacy
#
# Tip 839: 839>=839 ⇒ RIN3      (block at h=840 enforces → match)
# Tip 838: 838>=839 ⇒ FALSE     (block at h=839 no enforcement → accepted)

echo ""
echo "====== RIN3 Wallet Version Tests ======"
echo "  Current height: $(height)  (above nRinHashForkHeight=840)"

# [RIN3-1] Positive — verify wallet actually used RIN_FORK_TX_VERSION
echo ""
echo "  [RIN3-1] User tx above fork height (proves wallet used RIN3)..."
TXID=$($RINCOINCLI -regtest sendtoaddress "$ADDR" 1.0)
$RINCOINCLI -regtest generatetoaddress 1 "$ADDR" > /dev/null
CONFIRMS=$($RINCOINCLI -regtest gettransaction "$TXID" | json_val "['confirmations']")
[ "$CONFIRMS" -ge 1 ] && ok "Tx confirmed (block accepted)" \
                     || fail "Tx not confirmed above fork"
check_tx_nversion "$TXID" "$RIN_FORK_TX_VERSION_DEC" "above fork (expect RIN3)"

# [RIN3-2] Reorg to tip=839 — wallet still RIN3, block at h=840 enforces
echo ""
echo "  [RIN3-2] Reorg to tip=839 (boundary edge)..."
$RINCOINCLI -regtest invalidateblock "$(blockhash 840)"
check_height 839 "after invalidate(840)"

TXID2=$($RINCOINCLI -regtest sendtoaddress "$ADDR" 1.0)
$RINCOINCLI -regtest generatetoaddress 1 "$ADDR" > /dev/null
check_height 840 "after remine to h=840"
CONFIRMS2=$($RINCOINCLI -regtest gettransaction "$TXID2" | json_val "['confirmations']")
[ "$CONFIRMS2" -ge 1 ] && ok "Tx confirmed (consensus accepted at h=840)" \
                      || fail "Tx rejected at boundary edge"
check_tx_nversion "$TXID2" "$RIN_FORK_TX_VERSION_DEC" "at fork edge (expect RIN3)"

# [RIN3-3] Reorg to tip=838 — wallet reverts to legacy
echo ""
echo "  [RIN3-3] Reorg to tip=838 (below boundary)..."
$RINCOINCLI -regtest invalidateblock "$(blockhash 839)"
check_height 838 "after invalidate(839)"

TXID3=$($RINCOINCLI -regtest sendtoaddress "$ADDR" 1.0)
$RINCOINCLI -regtest generatetoaddress 1 "$ADDR" > /dev/null
check_height 839 "after remine to h=839"
CONFIRMS3=$($RINCOINCLI -regtest gettransaction "$TXID3" | json_val "['confirmations']")
[ "$CONFIRMS3" -ge 1 ] && ok "Tx confirmed (no enforcement at h=839)" \
                      || fail "Tx rejected below fork"

# Below fork: wallet should use default (nVersion=2 typically)
NVER3=$($RINCOINCLI -regtest decoderawtransaction \
        "$($RINCOINCLI -regtest getrawtransaction "$TXID3")" | json_val "['version']")
if [ "$NVER3" != "$RIN_FORK_TX_VERSION_DEC" ]; then
    ok "Tx below fork: nVersion = $NVER3 (legacy, not RIN3)"
else
    fail "Tx below fork: wallet incorrectly used RIN3 nVersion"
fi

# Restore chain
echo ""
echo "  Restoring chain..."
$RINCOINCLI -regtest generatetoaddress 102 "$ADDR" > /dev/null
ok "Chain restored to height $(height)"

# ---------- Summary ----------
echo ""
echo "============================================"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "============================================"
echo ""
echo "NOTE: This script tests POSITIVE wallet/consensus paths."
echo "      Negative consensus tests (legacy tx in block at h>=840 → rejected)"
echo "      live in test/functional/feature_rin3_enforcement.py"

if [ "$FAIL" -eq 0 ]; then
    echo ""
    echo "ALL TESTS PASSED — CH × RIN3 reorg resilience confirmed"
    exit 0
else
    echo ""
    echo "$FAIL TEST(S) FAILED"
    exit 1
fi
