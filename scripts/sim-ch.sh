# ===== Customized Halving Full Simulation (One-shot) =====

# 0. Setup: stop daemon, reset, restart
./rincoin-cli -regtest stop 2>/dev/null
rm -rf ~/.rincoin/regtest
./rincoind -regtest -daemon
sleep 3

# 1. Create wallet and address
./rincoin-cli -regtest createwallet "ch_test"
ADDR=$(./rincoin-cli -regtest getnewaddress "sim")
echo "Simulation Address: $ADDR"

# 2. Generate blocks through all phases
echo "[1/4] Advancing to Phase 4 (CH Activation: Block 840)..."
./rincoin-cli -regtest generatetoaddress 840 $ADDR > /dev/null

echo "[2/4] Advancing to Phase 5 (Block 2,100)..."
./rincoin-cli -regtest generatetoaddress 1260 $ADDR > /dev/null

echo "[3/4] Advancing to Phase 6 (Block 4,200)..."
./rincoin-cli -regtest generatetoaddress 2100 $ADDR > /dev/null

echo "[4/4] Advancing to Terminal Phase (Block 6,300)..."
./rincoin-cli -regtest generatetoaddress 2100 $ADDR > /dev/null

echo ""
echo "===== Boundary Value Analysis Results ====="

echo "[Phase 3 → 4: CH Activation]"
echo -n "Block 839  (expect 6.25 RIN): "
./rincoin-cli -regtest getblockstats 839 | grep subsidy
echo -n "Block 840  (expect 4.00 RIN): "
./rincoin-cli -regtest getblockstats 840 | grep subsidy

echo "[Phase 4 → 5: CH Halving 1]"
echo -n "Block 2099 (expect 4.00 RIN): "
./rincoin-cli -regtest getblockstats 2099 | grep subsidy
echo -n "Block 2100 (expect 2.00 RIN): "
./rincoin-cli -regtest getblockstats 2100 | grep subsidy

echo "[Phase 5 → 6: CH Halving 2]"
echo -n "Block 4199 (expect 2.00 RIN): "
./rincoin-cli -regtest getblockstats 4199 | grep subsidy
echo -n "Block 4200 (expect 1.00 RIN): "
./rincoin-cli -regtest getblockstats 4200 | grep subsidy

echo "[Phase 6 → Terminal]"
echo -n "Block 6299 (expect 1.00 RIN): "
./rincoin-cli -regtest getblockstats 6299 | grep subsidy
echo -n "Block 6300 (expect 0.60 RIN): "
./rincoin-cli -regtest getblockstats 6300 | grep subsidy

echo ""
echo "===== Simulation Complete ====="
