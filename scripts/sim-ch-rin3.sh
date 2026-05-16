#!/bin/bash
# Rincoin-Sim: Customized Halving x RIN3 Simulation (v4)
# Usage: ./scripts/sim-ch-rin3.sh
#
# Structure:
#   Section 1: Phase Advance (blocks 1 -> 6400)
#   Section 2: BVA  -- Boundary Value Analysis (8 blocks, no reorgs)
#   Section 3: RIN3 -- Wallet Version Tests (positive + boundary edge)
#   Section 4: Attack Simulation
#     [A] Minimal Attack      840  ->  839 ->  840  (  1-block cross-boundary)
#     [B] Super Attack       2100  ->  839 -> 2100  (1261-block, Phase 4 full erasure)
#     [C] Cross-Phase Attack 4200  -> 2099 -> 4200  (2101-block, Phase 5 full erasure)
#     [D] Terminal Attack    6300  -> 4199 -> 6300  (2101-block, Phase 6 + Terminal erasure)
#
# Companion: test/functional/feature_rin3_enforcement.py
#   covers consensus-level rejection of legacy-nVersion blocks at height >= fork.

set -e

PASS=0
FAIL=0

ok()   { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

# ---------- Cleanup trap ----------
# Runs on EXIT (normal, error, or Ctrl-C) so rincoind is never
# left as a zombie. pgrep loop at startup handles the previous run;
# this trap covers unexpected mid-test crashes.
cleanup() {
    echo ""
    echo "=== Cleanup (trap EXIT) ==="
    $RINCOINCLI -regtest stop 2>/dev/null || true
    sleep 1
    pkill -f "rincoind.*regtest" 2>/dev/null || true
}
trap cleanup EXIT

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

# ---------- Helpers ----------
height()    { $RINCOINCLI -regtest getblockcount; }
blockhash() { $RINCOINCLI -regtest getblockhash "$1"; }
json_val()  { python3 -c "import sys,json; print(json.load(sys.stdin)$1)"; }

RIN_FORK_TX_VERSION_DEC=1380535859   # 0x52494e33 ("RIN3")

# check_subsidy HEIGHT EXPECTED_SAT LABEL
#   Shows raw getblockstats line (sim-ch.sh style) then PASS/FAIL judgment.
check_subsidy() {
    local h=$1 expected=$2 label=$3
    local raw actual rin exp_rin
    raw=$($RINCOINCLI -regtest getblockstats "$h")
    actual=$(echo "$raw" | json_val "['subsidy']")
    rin=$(python3    -c "print(f'{$actual/1e8:.2f}')")
    exp_rin=$(python3 -c "print(f'{$expected/1e8:.2f}')")
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
#   Uses gettransaction (wallet RPC) so confirmed txs are accessible
#   without -txindex. v4 fix for getrawtransaction error code -5.
check_tx_nversion() {
    local txid=$1 expected=$2 label=$3
    local hex nver
    hex=$($RINCOINCLI -regtest gettransaction "$txid" | json_val "['hex']")
    nver=$($RINCOINCLI -regtest decoderawtransaction "$hex" | json_val "['version']")
    printf "    Tx nVersion = %-12s (expect %s)\n" "$nver" "$expected"
    if [ "$nver" = "$expected" ]; then
        ok "nVersion = $nver [$label]"
    else
        fail "nVersion = $nver (expected $expected) [$label]"
    fi
}

# advance_to TARGET [LABEL]
#   Mine blocks to TARGET height with progress every 500 blocks.
advance_to() {
    local target=$1
    local label=${2:-"Mining"}
    local cur; cur=$(height)
    [ "$cur" -ge "$target" ] && return
    local n=$((target - cur))
    local remaining=$n
    echo "  [$label] $n blocks -> h=$target..."
    while [ "$remaining" -gt 0 ]; do
        local batch=$(( remaining > 500 ? 500 : remaining ))
        $RINCOINCLI -regtest generatetoaddress "$batch" "$ADDR" > /dev/null
        remaining=$((remaining - batch))
        [ "$remaining" -gt 0 ] && echo "    -> h=$(height)  ($remaining remaining)"
    done
    echo "    -> h=$(height)"
}

# dummy_tx
#   Inject a low-value tx so the re-mined block has a unique merkle root,
#   avoiding hash collision with the just-invalidated block when mempool is
#   empty and difficulty/timestamp are identical. (Pattern from sim-mweb.sh)
dummy_tx() {
    if ! $RINCOINCLI -regtest sendtoaddress "$ADDR" 0.001 > /dev/null 2>&1; then
        echo "  [warn] dummy tx failed (low balance?) -- unique-hash guarantee weaker"
    fi
}

# attack_scenario LABEL ADVANCE_TO REORG_AT PRE_SATS TARGET POST_SATS
#
#   Flow:
#     1. advance_to ADVANCE_TO   (chain must reach this height before the attack)
#     2. invalidate REORG_AT     (chain falls to REORG_AT-1)
#     3. check_subsidy at REORG_AT-1   (verify rolled-back phase)
#     4. dummy_tx + advance_to TARGET  (remine)
#     5. check_subsidy at TARGET       (verify restored phase)
#
#   Chain height after call = TARGET (ready for next scenario).
attack_scenario() {
    local label=$1
    local advance=$2
    local reorg_at=$3
    local pre_sats=$4
    local target=$5
    local post_sats=$6

    local pre_h=$((reorg_at - 1))
    local pre_rin post_rin depth hash

    pre_rin=$(python3  -c "print(f'{$pre_sats/1e8:.2f}')")
    post_rin=$(python3 -c "print(f'{$post_sats/1e8:.2f}')")

    echo ""
    echo "====== Attack Scenario: $label ======"

    advance_to "$advance"

    depth=$(( $(height) - pre_h ))
    echo "  From h=$(height): invalidating block $reorg_at -> falls to h=$pre_h"
    echo "  Reorg depth   : $depth blocks"
    echo "  Rolled-back   : $pre_rin RIN @ h=$pre_h"
    echo "  Restored      : $post_rin RIN @ h=$target"
    echo ""

    hash=$(blockhash "$reorg_at")
    $RINCOINCLI -regtest invalidateblock "$hash"
    check_height "$pre_h" "after reorg"
    check_subsidy "$pre_h" "$pre_sats" "rolled-back subsidy"

    dummy_tx

    echo ""
    advance_to "$target" "Remining"
    check_height "$target" "after remine"
    check_subsidy "$target" "$post_sats" "restored subsidy"
}

# ---------- Setup ----------
echo ""
echo "========================================"
echo "  Rincoin-Sim: CH x RIN3 Simulation v4"
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

$RINCOINCLI -regtest createwallet "ch_rin3_v4" > /dev/null
ADDR=$($RINCOINCLI -regtest getnewaddress "sim")
echo "Test address: $ADDR"

# ---------- Section 1: Phase Advance ----------
#
#   Phase 0:  blocks     1-209  ->  50.00 RIN/block
#   Phase 1:  blocks   210-419  ->  25.00 RIN/block
#   Phase 2:  blocks   420-629  ->  12.50 RIN/block
#   Phase 3:  blocks   630-839  ->   6.25 RIN/block
#   Phase 4:  blocks  840-2099  ->   4.00 RIN/block  (CH dilation + RIN3)
#   Phase 5:  blocks 2100-4199  ->   2.00 RIN/block
#   Phase 6:  blocks 4200-6299  ->   1.00 RIN/block
#   Terminal: blocks    6300+   ->   0.60 RIN/block
#
echo ""
echo "=== Section 1: Phase Advance (1 -> 6400) ==="
echo ""

echo "[1/8] Phase 0 (50.00 RIN): Mining blocks 1-209..."
$RINCOINCLI -regtest generatetoaddress 209 "$ADDR" > /dev/null
echo "      Height: $(height)"
echo ""

echo "[2/8] Phase 1 (25.00 RIN): Mining blocks 210-419..."
$RINCOINCLI -regtest generatetoaddress 210 "$ADDR" > /dev/null
echo "      Height: $(height)"
echo ""

echo "[3/8] Phase 2 (12.50 RIN): Mining blocks 420-629..."
$RINCOINCLI -regtest generatetoaddress 210 "$ADDR" > /dev/null
echo "      Height: $(height)"
echo ""

echo "[4/8] Phase 3 ( 6.25 RIN): Mining blocks 630-839..."
$RINCOINCLI -regtest generatetoaddress 210 "$ADDR" > /dev/null
echo "      Height: $(height)"
echo ""

echo "[5/8] FORK: Block 840 (CH activation: 6.25 -> 4.00 RIN  |  RIN3 enforcement ON)..."
$RINCOINCLI -regtest generatetoaddress 1 "$ADDR" > /dev/null
echo "      Height: $(height)  <- nRinHashForkHeight reached"
echo ""

echo "[6/8] Phase 4 ( 4.00 RIN): Mining blocks 841-2099..."
advance_to 2099
echo ""

echo "[7/8] Phase 5-6 (2.00 -> 1.00 RIN): Mining blocks 2100-6299..."
advance_to 6299
echo ""

echo "[8/8] Terminal ( 0.60 RIN): Mining blocks 6300-6400 (buffer for mature UTXOs)..."
advance_to 6400
echo ""
echo "      All phase boundaries mined. Height: $(height)"

# ---------- Section 2: BVA ----------
echo ""
echo "========================================"
echo "  Section 2: BVA -- Boundary Value Analysis"
echo "========================================"
echo ""
echo "  Reading getblockstats for all 8 boundary blocks."
echo "  No reorgs -- pure subsidy correctness verification."
echo ""
echo "  Satoshi reference:"
echo "    6.25 RIN =  625000000  (Phase 3)"
echo "    4.00 RIN =  400000000  (Phase 4, CH dilation)"
echo "    2.00 RIN =  200000000  (Phase 5)"
echo "    1.00 RIN =  100000000  (Phase 6)"
echo "    0.60 RIN =   60000000  (Terminal)"
echo ""

echo "[Phase 3->4: CH dilation + RIN3 activation]"
check_subsidy  839  625000000 "Phase 3 last block"
check_subsidy  840  400000000 "Phase 4 first block (CH)"
echo ""

echo "[Phase 4->5]"
check_subsidy 2099  400000000 "Phase 4 last block"
check_subsidy 2100  200000000 "Phase 5 first block"
echo ""

echo "[Phase 5->6]"
check_subsidy 4199  200000000 "Phase 5 last block"
check_subsidy 4200  100000000 "Phase 6 first block"
echo ""

echo "[Phase 6->Terminal]"
check_subsidy 6299  100000000 "Phase 6 last block"
check_subsidy 6300   60000000 "Terminal first block"

# ---------- Section 3: RIN3 Wallet Tests ----------
#
# txassembler logic (txassembler.cpp):
#   last_height = chain tip at send time
#   if last_height >= nRinHashForkHeight - 1 (= 839) -> use RIN_FORK_TX_VERSION
#   else                                              -> use legacy nVersion
#
# Tip 839: 839 >= 839 -> RIN3   | block at h=840 enforces  -> accepted
# Tip 838: 838 <  839 -> legacy | block at h=839 no enforce -> accepted
#
echo ""
echo "========================================"
echo "  Section 3: RIN3 Wallet Version Tests"
echo "========================================"
echo ""
echo "  nRinHashForkHeight (regtest) = 840"
echo "  RIN_FORK_TX_VERSION = 0x52494e33 = $RIN_FORK_TX_VERSION_DEC"
echo "  Current height: $(height)"

# [RIN3-1] Positive: wallet uses RIN_FORK_TX_VERSION above fork
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

# [RIN3-2] Reorg to tip=839: wallet still RIN3 (839 >= 839), enforced at h=840
echo ""
echo "------ [RIN3-2] Reorg to tip=839 (boundary edge) ------"
echo "  Invalidating block 840 -> chain falls to h=839..."
$RINCOINCLI -regtest invalidateblock "$(blockhash 840)"
check_height 839 "after invalidate(840)"

echo "  Sending 1.0 RIN (tip=839 >= 839 -> wallet uses RIN3)..."
TXID2=$($RINCOINCLI -regtest sendtoaddress "$ADDR" 1.0)
echo "  Mining block (h=840, enforcement active)..."
$RINCOINCLI -regtest generatetoaddress 1 "$ADDR" > /dev/null
check_height 840 "after remine to h=840"

CONFIRMS2=$($RINCOINCLI -regtest gettransaction "$TXID2" | json_val "['confirmations']")
printf "  Confirmations = %s\n" "$CONFIRMS2"
[ "$CONFIRMS2" -ge 1 ] && ok "Tx confirmed (consensus accepted at h=840)" \
                       || fail "Tx rejected at boundary edge"
check_tx_nversion "$TXID2" "$RIN_FORK_TX_VERSION_DEC" "at fork edge (expect RIN3)"

# [RIN3-3] Reorg to tip=838: wallet reverts to legacy (838 < 839)
echo ""
echo "------ [RIN3-3] Reorg to tip=838 (below boundary) ------"
echo "  Invalidating block 839 -> chain falls to h=838..."
$RINCOINCLI -regtest invalidateblock "$(blockhash 839)"
check_height 838 "after invalidate(839)"

echo "  Sending 1.0 RIN (tip=838 < 839 -> wallet uses legacy nVersion)..."
TXID3=$($RINCOINCLI -regtest sendtoaddress "$ADDR" 1.0)
echo "  Mining block (h=839, enforcement NOT yet active)..."
$RINCOINCLI -regtest generatetoaddress 1 "$ADDR" > /dev/null
check_height 839 "after remine to h=839"

CONFIRMS3=$($RINCOINCLI -regtest gettransaction "$TXID3" | json_val "['confirmations']")
printf "  Confirmations = %s\n" "$CONFIRMS3"
[ "$CONFIRMS3" -ge 1 ] && ok "Tx confirmed (no enforcement at h=839)" \
                       || fail "Tx rejected below fork"

NVER3=$($RINCOINCLI -regtest decoderawtransaction \
    "$($RINCOINCLI -regtest gettransaction "$TXID3" | json_val "['hex']")" \
    | json_val "['version']")
printf "    Tx nVersion = %s  (expect anything except %s)\n" \
    "$NVER3" "$RIN_FORK_TX_VERSION_DEC"
if [ "$NVER3" != "$RIN_FORK_TX_VERSION_DEC" ]; then
    ok "nVersion = $NVER3 (legacy, not RIN3) [below fork]"
else
    fail "nVersion = $NVER3 (wallet incorrectly used RIN3 below fork)"
fi

# Reset chain to h=840 for Attack Simulation.
# After RIN3-3, chain is at h=839 -- just mine 1 block.
echo ""
echo "  [Reset for Attack Simulation] Mining 1 block -> h=840..."
$RINCOINCLI -regtest generatetoaddress 1 "$ADDR" > /dev/null
check_height 840 "reset to h=840"

# ---------- Section 4: Attack Simulation ----------
echo ""
echo "========================================"
echo "  Section 4: Attack Simulation"
echo "========================================"
echo ""
echo "  Thesis: GetBlockSubsidy is a pure function of block height."
echo "  No matter how deep the reorg, the correct subsidy is restored."
echo "  Each scenario leaves the chain at TARGET, ready for the next."
echo ""
echo "  Scenario depths:"
echo "    [A] Minimal Attack      840 ->  839 ->  840  (   1 block)"
echo "    [B] Super Attack       2100 ->  839 -> 2100  (1261 blocks, Phase 4 erasure)"
echo "    [C] Cross-Phase Attack 4200 -> 2099 -> 4200  (2101 blocks, Phase 5 erasure)"
echo "    [D] Terminal Attack    6300 -> 4199 -> 6300  (2101 blocks, Phase 6 erasure)"

# [A] 840 -> 839 -> 840
#   From h=840: invalidate(840) -> h=839 (6.25 RIN)
#               remine 1        -> h=840 (4.00 RIN)
attack_scenario \
    "[A] Minimal Attack: 840 -> 839 -> 840  (1-block cross-boundary)" \
    840 840 625000000 840 400000000

# [B] 2100 -> 839 -> 2100
#   From h=840: advance to h=2100
#               invalidate(840) -> h=839  (6.25 RIN, 1261-block reorg)
#               remine to h=2100          (2.00 RIN)
attack_scenario \
    "[B] Super Attack: 2100 -> 839 -> 2100  (Phase 4 full erasure)" \
    2100 840 625000000 2100 200000000

# [C] 4200 -> 2099 -> 4200
#   From h=2100: advance to h=4200
#                invalidate(2100) -> h=2099 (4.00 RIN, 2101-block reorg)
#                remine to h=4200          (1.00 RIN)
attack_scenario \
    "[C] Cross-Phase Attack: 4200 -> 2099 -> 4200  (Phase 5 full erasure)" \
    4200 2100 400000000 4200 100000000

# [D] 6300 -> 4199 -> 6300
#   From h=4200: advance to h=6300
#                invalidate(4200) -> h=4199 (2.00 RIN, 2101-block reorg)
#                remine to h=6300          (0.60 RIN)
attack_scenario \
    "[D] Terminal Attack: 6300 -> 4199 -> 6300  (Phase 6 + Terminal erasure)" \
    6300 4200 200000000 6300 60000000

# ---------- Summary ----------
echo ""
echo "========================================"
printf "  PASS: %d\n" "$PASS"
printf "  FAIL: %d\n" "$FAIL"
echo "========================================"
echo ""
echo "NOTE: Positive wallet/consensus paths verified here."
echo "      Negative consensus rejection tests (legacy tx rejected at h>=840)"
echo "      live in: test/functional/feature_rin3_enforcement.py"

if [ "$FAIL" -eq 0 ]; then
    echo ""
    echo "ALL TESTS PASSED -- CH x RIN3 attack resilience confirmed"
    exit 0
else
    echo ""
    echo "$FAIL TEST(S) FAILED"
    exit 1
fi
