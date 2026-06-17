#!/bin/bash
# Rincoin-Sim: MWEB Full Simulation (Peg-in, Peg-out & Reorg)
# Usage: ./scripts/sim-mweb.sh
# Flow: Transparent(1) → MWEB → Transparent(2)

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

# ---------- Helper: report a wallet tx's confirmation state ----------
# gettransaction emits JSON as  "confirmations": N  (note the space after
# the colon), so the extraction pattern must tolerate whitespace. A naive
# '"confirmations":[0-9-]*' matches zero digits and silently returns just
# the key, which is why the reorg section previously printed a blank value.
#
# Interpretation:
#   >=1  mined (confirmed in a block)
#    0   accepted but unconfirmed (back in mempool after the reorg)
#   <0   conflicted (Bitcoin/Litecoin marks reorged-out txs negative)
#  none  not in the wallet at all (dropped)
tx_status() {
    local txid=$1 json n
    json=$($RINCOINCLI -regtest -rpcwallet=mweb_wallet gettransaction "$txid" 2>/dev/null) \
        || { echo "dropped (not in wallet)"; return; }
    n=$(printf '%s' "$json" | grep -oP '"confirmations":\s*\K-?[0-9]+' | head -1)
    if   [ -z "$n" ];    then echo "unknown (parse failed)"
    elif [ "$n" -lt 0 ]; then echo "$n confirmations (conflicted / reorged out)"
    elif [ "$n" -eq 0 ]; then echo "0 confirmations (in mempool, unconfirmed)"
    else                      echo "$n confirmation(s) (mined)"
    fi
}

# ---------- Cleanup trap ----------
# Runs on EXIT (normal finish, error, or Ctrl-C).
#
# Manual inspection mode:
#   KEEP_ALIVE=1 ./scripts/sim-mweb.sh
#   After the script ends, rincoind stays running so you can inspect:
#     ./bin/rincoin-cli -regtest gettransaction <txid>
#     ./bin/rincoin-cli -regtest getblockcount
#   When done: ./bin/rincoin-cli -regtest stop
cleanup() {
    if [ "${KEEP_ALIVE:-0}" = "1" ]; then
        echo ""
        echo "=== KEEP_ALIVE=1: rincoind is still running for manual inspection ==="
        echo "  Commands available:"
        echo "    $RINCOINCLI -regtest getblockcount"
        echo "    $RINCOINCLI -regtest -rpcwallet=mweb_wallet getbalance"
        echo "    $RINCOINCLI -regtest -rpcwallet=miner_wallet getreceivedbyaddress <addr>"
        echo "  When done: $RINCOINCLI -regtest stop"
        return
    fi
    echo ""
    echo "=== Cleanup (trap EXIT) ==="
    $RINCOINCLI -regtest stop 2>/dev/null || true
    sleep 1
    pkill -f "rincoind.*regtest" 2>/dev/null || true
}
trap cleanup EXIT

# 0. Reset environment
echo "Stopping rincoind..."
$RINCOINCLI -regtest stop 2>/dev/null || true

# Wait until the process is completely terminated (avoid port conflicts)
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

# Start from a clean state
rm -rf ~/.rincoin/regtest
$RINCOIND -regtest -daemon
sleep 4

# 1. Create isolated wallets
$RINCOINCLI -regtest createwallet "miner_wallet" > /dev/null
$RINCOINCLI -regtest createwallet "mweb_wallet" > /dev/null

MINER_ADDR=$($RINCOINCLI -regtest -rpcwallet=miner_wallet getnewaddress "miner")
MWEB_ADDR=$($RINCOINCLI -regtest -rpcwallet=mweb_wallet getnewaddress "mweb_receiver" "mweb")
PEGOUT_ADDR=$($RINCOINCLI -regtest -rpcwallet=miner_wallet getnewaddress "pegout_receiver")

echo "Miner  (Transparent 1): $MINER_ADDR"
echo "MWEB   (Private)      : $MWEB_ADDR"
echo "Target (Transparent 2): $PEGOUT_ADDR"
echo ""

# 2. Mine 450 blocks
echo "[1/6] Mining 450 blocks (MWEB activates at ~block 432)..."
$RINCOINCLI -regtest -rpcwallet=miner_wallet generatetoaddress 450 $MINER_ADDR > /dev/null

# 3. Peg-in: Transparent → MWEB
echo "[2/6] Peg-in: Sending 10 RIN → MWEB..."
$RINCOINCLI -regtest -rpcwallet=miner_wallet sendtoaddress $MWEB_ADDR 10 > /dev/null

echo "[3/6] Mining 1 block to confirm Peg-in..."
$RINCOINCLI -regtest -rpcwallet=miner_wallet generatetoaddress 1 $MINER_ADDR > /dev/null

MWEB_BAL=$($RINCOINCLI -regtest -rpcwallet=mweb_wallet getbalance)
echo "  MWEB Wallet Balance: $MWEB_BAL RIN"
echo ""

# 4. Peg-out: MWEB → Transparent
echo "[4/6] Peg-out: Sending 5 RIN MWEB → Transparent..."
PEGOUT_TXID=$($RINCOINCLI -regtest -rpcwallet=mweb_wallet sendtoaddress $PEGOUT_ADDR 5)

echo "[5/6] Mining 1 block to confirm Peg-out..."
$RINCOINCLI -regtest -rpcwallet=miner_wallet generatetoaddress 1 $MINER_ADDR > /dev/null

# Securely obtain current height and block hash
# (avoids timing issues with getbestblockhash)
CURRENT_HEIGHT=$($RINCOINCLI -regtest -rpcwallet=miner_wallet getblockcount)
PEGOUT_BLOCKHASH=$($RINCOINCLI -regtest -rpcwallet=miner_wallet getblockhash $CURRENT_HEIGHT)

echo ""
echo "===== Peg-out Results ====="
RECEIVED=$($RINCOINCLI -regtest -rpcwallet=miner_wallet getreceivedbyaddress $PEGOUT_ADDR)
MWEB_REMAIN=$($RINCOINCLI -regtest -rpcwallet=mweb_wallet getbalance)
echo "Transparent 2 received : $RECEIVED RIN (expect ~5.0)"
echo "MWEB remaining         : $MWEB_REMAIN RIN (expect ~4.999)"
echo ""

# 5. Reorg test
echo "[6/6] Reorg Test: Invalidating Peg-out block..."
echo "  Invalidating block at height $CURRENT_HEIGHT: $PEGOUT_BLOCKHASH"
$RINCOINCLI -regtest invalidateblock $PEGOUT_BLOCKHASH

sleep 1

NEW_HEIGHT=$($RINCOINCLI -regtest -rpcwallet=miner_wallet getblockcount)
echo "  After invalidate: height=$NEW_HEIGHT (expect $((CURRENT_HEIGHT-1)))"

echo "  Peg-out tx after invalidate : $(tx_status "$PEGOUT_TXID")"
echo "                                (expect: 0/mempool or conflicted)"

echo "  -> Generating a dummy transaction to ensure a unique block hash..."
DUMMY_ADDR=$($RINCOINCLI -regtest -rpcwallet=miner_wallet getnewaddress "dummy")
$RINCOINCLI -regtest -rpcwallet=miner_wallet sendtoaddress $DUMMY_ADDR 0.1 > /dev/null

echo "  Re-mining replacement block..."
$RINCOINCLI -regtest -rpcwallet=miner_wallet generatetoaddress 1 $MINER_ADDR > /dev/null

FINAL_HEIGHT=$($RINCOINCLI -regtest -rpcwallet=miner_wallet getblockcount)
echo "  After re-mine: height=$FINAL_HEIGHT (expect $CURRENT_HEIGHT)"

echo "  Peg-out tx after re-mine    : $(tx_status "$PEGOUT_TXID")"
echo "                                (expect: 1 confirmation)"

echo ""
echo "===== Simulation Complete ====="
echo "Validated: Transparent → MWEB (Peg-in) → Transparent (Peg-out) + Reorg"
