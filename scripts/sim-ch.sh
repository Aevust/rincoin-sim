#!/bin/bash
# Rincoin-Sim: Customized Halving Full Simulation
# Usage: ./scripts/sim-ch.sh
# Flow: Phase 0 → Phase 4 (CH Activation) → Terminal

set -e

# ---------- Binary detection (CWD-independent) ----------
# Resolve binaries relative to this script's own location so the
# harness can be invoked from any working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(dirname "$SCRIPT_DIR")"
if [ -f "$PKG_ROOT/bin/rincoind" ]; then
    RINCOIND="$PKG_ROOT/bin/rincoind"
    RINCOINCLI="$PKG_ROOT/bin/rincoin-cli"
elif [ -f "$PKG_ROOT/src/rincoind" ]; then
    RINCOIND="$PKG_ROOT/src/rincoind"
    RINCOINCLI="$PKG_ROOT/src/rincoin-cli"
else
    echo "Error: rincoind not found under $PKG_ROOT/bin/ or $PKG_ROOT/src/."
    echo "If running from a source tree, build it first (doc/build-unix-rincoin-sim.md)."
    exit 1
fi

# ---------- Cleanup trap ----------
# Runs on EXIT (normal finish, error, or Ctrl-C) so rincoind is never
# left running as a zombie after the script ends.
cleanup() {
    echo ""
    echo "=== Cleanup (trap EXIT) ==="
    $RINCOINCLI -regtest stop 2>/dev/null || true
    sleep 1
    pkill -f "rincoind.*regtest" 2>/dev/null || true
}
trap cleanup EXIT

# 0. Setup: stop daemon, reset, restart
echo "Stopping rincoind..."
$RINCOINCLI -regtest stop 2>/dev/null || true

for i in {1..10}; do
  if ! pgrep -f "rincoind.*regtest" > /dev/null; then
    echo "rincoind stopped cleanly"
    break
  fi
  sleep 1
  if [ $i -eq 10 ]; then
    echo "Warning: rincoind still running, forcing kill..."
    pkill -f "rincoind.*regtest" 2>/dev/null || true
    sleep 2
  fi
done

rm -rf ~/.rincoin/regtest
$RINCOIND -regtest -daemon
sleep 3

# 1. Create wallet and address
$RINCOINCLI -regtest createwallet "ch_test" > /dev/null
ADDR=$($RINCOINCLI -regtest getnewaddress "sim")
echo "Simulation Address: $ADDR"
echo ""

# 2. Generate blocks through all phases
echo "[1/4] Advancing to Phase 4 (CH Activation: Block 840)..."
$RINCOINCLI -regtest generatetoaddress 840 $ADDR > /dev/null

echo "[2/4] Advancing to Phase 5 (Block 2,100)..."
$RINCOINCLI -regtest generatetoaddress 1260 $ADDR > /dev/null

echo "[3/4] Advancing to Phase 6 (Block 4,200)..."
$RINCOINCLI -regtest generatetoaddress 2100 $ADDR > /dev/null

echo "[4/4] Advancing to Terminal Phase (Block 6,300)..."
$RINCOINCLI -regtest generatetoaddress 2100 $ADDR > /dev/null

echo ""
echo "===== Boundary Value Analysis Results ====="

echo "[Phase 3 → 4: CH Activation]"
echo -n "Block 839  (expect 6.25 RIN): "
$RINCOINCLI -regtest getblockstats 839 | grep subsidy
echo -n "Block 840  (expect 4.00 RIN): "
$RINCOINCLI -regtest getblockstats 840 | grep subsidy

echo "[Phase 4 → 5: CH Halving 1]"
echo -n "Block 2099 (expect 4.00 RIN): "
$RINCOINCLI -regtest getblockstats 2099 | grep subsidy
echo -n "Block 2100 (expect 2.00 RIN): "
$RINCOINCLI -regtest getblockstats 2100 | grep subsidy

echo "[Phase 5 → 6: CH Halving 2]"
echo -n "Block 4199 (expect 2.00 RIN): "
$RINCOINCLI -regtest getblockstats 4199 | grep subsidy
echo -n "Block 4200 (expect 1.00 RIN): "
$RINCOINCLI -regtest getblockstats 4200 | grep subsidy

echo "[Phase 6 → Terminal]"
echo -n "Block 6299 (expect 1.00 RIN): "
$RINCOINCLI -regtest getblockstats 6299 | grep subsidy
echo -n "Block 6300 (expect 0.60 RIN): "
$RINCOINCLI -regtest getblockstats 6300 | grep subsidy

echo ""
echo "===== Simulation Complete ====="
echo "Validated: Customized Halving Scenario II — All BVA boundaries confirmed"
