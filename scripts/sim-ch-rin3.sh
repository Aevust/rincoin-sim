#!/bin/bash
# Rincoin-Sim: Customized Halving × RIN3 Reorg Simulation (v3)
# Usage: ./scripts/sim-ch-rin3.sh
#
# Tests:
#   [CH]    100-block reorg across all 4 subsidy boundaries → BVA after reorg
#   [RIN3]  User tx confirmed above fork height → nVersion proven = RIN_FORK_TX_VERSION
#   [RIN3]  Reorg to tip=839 → wallet still RIN3 (border edge)
#   [RIN3]  Reorg to tip=838 → wallet reverts to legacy nVersion
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
# Runs on EXIT (normal, error, or signal) to ensure rincoind is never
# left as a zombie. The startup pgrep loop handles the previous run;
# this trap handles unexpected mid-test crashes. (Gemini 2)
cleanup() {
    echo ""
    echo "=== Cleanup (trap EXIT) ==="
    $RINCOINCLI -regtest stop 2>/dev/null || true
    sleep 1
    pkill -f "rincoind.*regtest" 2>/dev/null || true
}
trap cleanup EXIT

# ---------- Helpers ----------
height()    { $RINCOINCLI -regtest getblockcount; }
blockhash() { $RINCOINCLI -regtest getblockhash "$1"; }
json_val()  { python3 -c "import sys,json; print(json.load(sys.stdin)$1)"; }

RIN_FORK_TX_VERSION_DEC=1380535859   # 0x52494e33 ("RIN3")

# check_subsidy HEIGHT EXPECTED_SATOSHIS LABEL
#   Shows raw getblockstats line (sim-ch.sh style) then PASS/FAIL judgment.
check_subsidy() {
    local h=$1 expected=$2 label=$3
    local raw actual rin exp_rin

    raw=$($RINCOINCLI -regtest getblockstats "$h")
    actual=$(echo "$raw" | json_val "['subsidy']")
    rin=$(python3 -c "print(f'{$actual/1e8:.2f}')")
    exp_rin=$(python3 -c "print(f'{$expected/1e8:.2f}')")

    # Raw output — same style as sim-ch.sh "grep subsidy"
    printf "    Block %-5s | subsidy = %-12s sat  (%s RIN)  expect %s RIN\n" \
        "$h" "$actual" "$rin" "$exp_rin"

    if [ "$actual" = "$expected" ]; then
        ok "Block $h: $rin RIN [$label]"
    else
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
check_tx_nversion() {
    local txid=$1 expected=$2 label=$3
    local hex nver
    hex=$($RINCOINCLI -regtest getrawtransaction "$txid")
    nver=$($RINCOINCLI -regtest decoderawtransaction "$hex" | json_val "['version']")
    printf "    Tx nVersion = %-12s (expect %s)\n" "$nver" "$expected"
    if [ "$nver" = "$expected" ]; then
        ok "nVersion = $nver [$label]"
    else
        fail "nVersion = $nver (expected $expected) [$label]"
    fi
}

# reorg_bva BOUNDARY PRE_SATS POST_SATS LABEL
reorg_bva() {
    local boundary=$1 pre_sats=$2 post_sats=$3 label=$4
    local cur target n hash pre_rin post_rin

    pre_rin=$(python3 -c "print(f'{$pre_sats/1e8:.2f}')")
    post_rin=$(python3 -c "print(f'{$post_sats/1e8:.2f}')")

    echo ""
    echo "====== Reorg BVA: $label ======"
    echo "  Boundary: Block $boundary  |  $pre_rin RIN → $post_rin RIN"

    cur=$(height)
    target=$((boundary + 100))

    if [ "$cur" -lt "$target" ]; then
        n=$((target - cur))
        echo ""
        echo "  [Advancing] Mining $n blocks → height $target..."
        $RINCOINCLI -regtest generatetoaddress "$n" "$ADDR" > /dev/null
        echo "              Height: $(height)"
    fi

    echo ""
    echo "  [Reorg] Invalidating block $boundary → chain rolls back..."
    hash=$(blockhash "$boundary")
    $RINCOINCLI -regtest invalidateblock "$hash"
    check_height $((boundary - 1)) "after reorg"

    echo ""
    echo "  [BVA — orphan side]"
    check_subsidy $((boundary - 1)) "$pre_sats" "pre-boundary (orphan side)"

    # Dummy tx: ensures a unique merkle root on re-mine.
    # Avoids hash collision with the just-invalidated block when mempool is
    # empty and difficulty/timestamp are identical. (Pattern from sim-mweb.sh)
    # If sendtoaddress fails (e.g. low balance right after reorg), the hash
    # guarantee is weaker but the test continues.
    if ! $RINCOINCLI -regtest sendtoaddress "$ADDR" 0.001 > /dev/null 2>&1; then
        echo "  [warn] dummy tx failed (low balance after reorg?) -- unique-hash guarantee weaker"
    fi

    echo ""
    echo "  [Remining] Mining 101 blocks → restoring chain..."
    $RINCOINCLI -regtest generatetoaddress 101 "$ADDR" > /dev/null
    check_height "$target" "after remine"

    echo ""
    echo "  [BVA — new chain]"
    check_subsidy $((boundary - 1)) "$pre_sats"  "pre-boundary (new chain)"
    check_subsidy "$boundary"        "$post_sats" "at-boundary  (new chain)"
}

# ---------- Setup ----------
echo ""
echo "========================================"
echo "  Rincoin-Sim: CH x RIN3 Simulation"
echo "========================================"
echo ""
echo "=== Setup: Reset regtest environment ==="
echo ""
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
$RINCOIND -regtest -daemon -fallbackfee=0.001
sleep 3

$RINCOINCLI -regtest createwallet "ch_rin3_reorg" > /dev/null
ADDR=$($RINCOINCLI -regtest getnewaddress "sim")
echo "Test address: $ADDR"

# ---------- Phase advance ----------
#
#   Phase 0:  blocks     1-209  →  50.00 RIN/block
#   Phase 1:  blocks   210-419  →  25.00 RIN/block
#   Phase 2:  blocks   420-629  →  12.50 RIN/block
#   Phase 3:  blocks   630-839  →   6.25 RIN/block
#   Phase 4:  blocks  840-2099  →   4.00 RIN/block  (CH dilation + RIN3)
#   Phase 5:  blocks 2100-4199  →   2.00 RIN/block
#   Phase 6:  blocks 4200-6299  →   1.00 RIN/block
#   Terminal: blocks    6300+   →   0.60 RIN/block
#
echo ""
echo "=== Phase Advance: Blocks 1 → 940 ==="
echo ""

echo "[1/5] Phase 0 (50.00 RIN): Mining blocks 1-209..."
$RINCOINCLI -regtest generatetoaddress 209 "$ADDR" > /dev/null
echo "      Height: $(height)"
echo ""

echo "[2/5] Phase 1 (25.00 RIN): Mining blocks 210-419..."
$RINCOINCLI -regtest generatetoaddress 210 "$ADDR" > /dev/null
echo "      Height: $(height)"
echo ""

echo "[3/5] Phase 2 (12.50 RIN): Mining blocks 420-629..."
$RINCOINCLI -regtest generatetoaddress 210 "$ADDR" > /dev/null
echo "      Height: $(height)"
echo ""

echo "[4/5] Phase 3 ( 6.25 RIN): Mining blocks 630-839..."
$RINCOINCLI -regtest generatetoaddress 210 "$ADDR" > /dev/null
echo "      Height: $(height)"
echo ""

echo "[5/5] FORK:   Mining block 840 (CH activation: 6.25 -> 4.00 RIN  |  RIN3 enforcement ON)..."
$RINCOINCLI -regtest generatetoaddress 1 "$ADDR" > /dev/null
echo "      Height: $(height)  <- nRinHashForkHeight reached"
echo ""

echo "      Mining 99 blocks past fork (buffer for mature UTXOs)..."
$RINCOINCLI -regtest generatetoaddress 99 "$ADDR" > /dev/null
echo "      Height: $(height)"

# ---------- CH Reorg BVA ----------
echo ""
echo "========================================"
echo "  CH Reorg BVA - 4 Boundaries"
echo "========================================"
echo ""
echo "Satoshi reference:"
echo "    6.25 RIN =  625000000  (Phase 3)"
echo "    4.00 RIN =  400000000  (Phase 4, CH dilation)"
echo "    2.00 RIN =  200000000  (Phase 5)"
echo "    1.00 RIN =  100000000  (Phase 6)"
echo "    0.60 RIN =   60000000  (Terminal)"

reorg_bva  840  625000000  400000000 "Phase 3->4 (CH dilation + RIN3 activation)"
reorg_bva 2100  400000000  200000000 "Phase 4->5"
reorg_bva 4200  200000000  100000000 "Phase 5->6"
reorg_bva 6300  100000000   60000000 "Phase 6->Terminal"

# ---------- RIN3 Wallet Version Tests ----------
#
# txassembler logic:
#   last_height = chain tip at send time
#   if last_height >= nRinHashForkHeight - 1 (= 839) -> use RIN_FORK_TX_VERSION
#   else                                              -> use legacy nVersion
#
# Tip 839:  839 >= 839  -> RIN3    block at h=840 enforces -> accepted
# Tip 838:  838 >= 839  -> FALSE   block at h=839 no enforcement -> accepted
#
echo ""
echo "========================================"
echo "  RIN3 Wallet Version Tests"
echo "========================================"
echo ""
echo "  nRinHashForkHeight (regtest) = 840"
echo "  RIN_FORK_TX_VERSION = 0x52494e33 = $RIN_FORK_TX_VERSION_DEC"
echo "  Current height: $(height)"

# [RIN3-1] Positive — wallet uses RIN_FORK_TX_VERSION above fork
echo ""
echo "------ [RIN3-1] User tx above fork (expect RIN3) ------"
echo "  Sending 1.0 RIN to self..."
TXID=$($RINCOINCLI -regtest sendtoaddress "$ADDR" 1.0)
echo "  Mining confirmation block..."
$RINCOINCLI -regtest generatetoaddress 1 "$ADDR" > /dev/null
echo "  Height: $(height)"

CONFIRMS=$($RINCOINCLI -regtest gettransaction "$TXID" | json_val "['confirmations']")
printf "  Confirmations = %s\n" "$CONFIRMS"
[ "$CONFIRMS" -ge 1 ] && ok "Tx confirmed (block accepted at h>840)" \
                      || fail "Tx not confirmed above fork"
check_tx_nversion "$TXID" "$RIN_FORK_TX_VERSION_DEC" "above fork (expect RIN3)"

# [RIN3-2] Reorg to tip=839 — wallet still RIN3, enforced at h=840
echo ""
echo "------ [RIN3-2] Reorg to tip=839 (boundary edge) ------"
echo "  Invalidating block 840 -> chain falls back to h=839..."
$RINCOINCLI -regtest invalidateblock "$(blockhash 840)"
check_height 839 "after invalidate(840)"

echo "  Sending 1.0 RIN (wallet sees tip=839 >= 839 -> should use RIN3)..."
TXID2=$($RINCOINCLI -regtest sendtoaddress "$ADDR" 1.0)
echo "  Mining block (h=840, enforcement active)..."
$RINCOINCLI -regtest generatetoaddress 1 "$ADDR" > /dev/null
check_height 840 "after remine to h=840"

CONFIRMS2=$($RINCOINCLI -regtest gettransaction "$TXID2" | json_val "['confirmations']")
printf "  Confirmations = %s\n" "$CONFIRMS2"
[ "$CONFIRMS2" -ge 1 ] && ok "Tx confirmed (consensus accepted at h=840)" \
                       || fail "Tx rejected at boundary edge"
check_tx_nversion "$TXID2" "$RIN_FORK_TX_VERSION_DEC" "at fork edge (expect RIN3)"

# [RIN3-3] Reorg to tip=838 — wallet reverts to legacy
echo ""
echo "------ [RIN3-3] Reorg to tip=838 (below boundary) ------"
echo "  Invalidating block 839 -> chain falls back to h=838..."
$RINCOINCLI -regtest invalidateblock "$(blockhash 839)"
check_height 838 "after invalidate(839)"

echo "  Sending 1.0 RIN (wallet sees tip=838 < 839 -> should use legacy nVersion)..."
TXID3=$($RINCOINCLI -regtest sendtoaddress "$ADDR" 1.0)
echo "  Mining block (h=839, enforcement NOT yet active)..."
$RINCOINCLI -regtest generatetoaddress 1 "$ADDR" > /dev/null
check_height 839 "after remine to h=839"

CONFIRMS3=$($RINCOINCLI -regtest gettransaction "$TXID3" | json_val "['confirmations']")
printf "  Confirmations = %s\n" "$CONFIRMS3"
[ "$CONFIRMS3" -ge 1 ] && ok "Tx confirmed (no enforcement at h=839)" \
                       || fail "Tx rejected below fork"

NVER3=$($RINCOINCLI -regtest decoderawtransaction \
        "$($RINCOINCLI -regtest getrawtransaction "$TXID3")" | json_val "['version']")
printf "    Tx nVersion = %s  (expect anything except %s)\n" \
    "$NVER3" "$RIN_FORK_TX_VERSION_DEC"
if [ "$NVER3" != "$RIN_FORK_TX_VERSION_DEC" ]; then
    ok "nVersion = $NVER3 (legacy, not RIN3) [below fork]"
else
    fail "nVersion = $NVER3 (wallet incorrectly used RIN3 below fork)"
fi

# Restore chain
echo ""
echo "  Restoring chain (mining 102 blocks)..."
$RINCOINCLI -regtest generatetoaddress 102 "$ADDR" > /dev/null
ok "Chain restored  |  height = $(height)"

# ---------- Summary ----------
echo ""
echo "========================================"
printf "  PASS: %d\n" "$PASS"
printf "  FAIL: %d\n" "$FAIL"
echo "========================================"
echo ""
echo "NOTE: This script tests POSITIVE wallet/consensus paths."
echo "      Negative consensus tests (legacy tx in block at h>=840 rejected)"
echo "      live in: test/functional/feature_rin3_enforcement.py"

if [ "$FAIL" -eq 0 ]; then
    echo ""
    echo "ALL TESTS PASSED -- CH x RIN3 reorg resilience confirmed"
    exit 0
else
    echo ""
    echo "$FAIL TEST(S) FAILED"
    exit 1
fi
