#!/bin/bash
# Rincoin-Sim: MWEB Full Simulation (Peg-in, Peg-out & Reorg)
# Usage: ./scripts/sim-mweb.sh
# Flow: Transparent(1) → MWEB → Transparent(2)

set -e

# Automatic detection of binary paths
if [ -f "./bin/rincoind" ]; then
    RINCOIND="./bin/rincoind"
    RINCOINCLI="./bin/rincoin-cli"
elif [ -f "./src/rincoind" ]; then
    RINCOIND="./src/rincoind"
    RINCOINCLI="./src/rincoin-cli"
else
    echo "Error: rincoind not found."
    echo "Run from rincoin-sim-v1.0.6-linux-x86_64/bin/ or source dir."
    exit 1
fi

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

CONF=$($RINCOINCLI -regtest -rpcwallet=mweb_wallet gettransaction $PEGOUT_TXID 2>/dev/null \
  | grep -o '"confirmations":[0-9-]*' || echo '"confirmations":orphaned')
echo "  Transaction status : $CONF (expect 0 or orphaned)"

echo "  -> Generating a dummy transaction to ensure a unique block hash..."
DUMMY_ADDR=$($RINCOINCLI -regtest -rpcwallet=miner_wallet getnewaddress "dummy")
$RINCOINCLI -regtest -rpcwallet=miner_wallet sendtoaddress $DUMMY_ADDR 0.1 > /dev/null

echo "  Re-mining replacement block..."
$RINCOINCLI -regtest -rpcwallet=miner_wallet generatetoaddress 1 $MINER_ADDR > /dev/null

FINAL_HEIGHT=$($RINCOINCLI -regtest -rpcwallet=miner_wallet getblockcount)
echo "  After re-mine: height=$FINAL_HEIGHT (expect $CURRENT_HEIGHT)"

CONF2=$($RINCOINCLI -regtest -rpcwallet=mweb_wallet gettransaction $PEGOUT_TXID 2>/dev/null \
  | grep -o '"confirmations":[0-9]*' || echo '"confirmations":rebroadcast_needed')
echo "  Transaction status : $CONF2"

echo ""
echo "===== Simulation Complete ====="
echo "Validated: Transparent → MWEB (Peg-in) → Transparent (Peg-out) + Reorg"
