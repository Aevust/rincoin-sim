# Rincoin-Sim: Customized Halving & MWEB Simulation Environment

![Version](https://img.shields.io/badge/version-1.0.6--sim-red.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Status](https://img.shields.io/badge/status-REGTEST_ONLY-critical.svg)

> ⚠️ **CRITICAL WARNING: REGTEST ONLY / DO NOT MERGE TO MAINNET** ⚠️
> 
> This repository (`rincoin-sim`) is a dedicated simulation environment strictly designed for local `regtest` execution. It tests the **Customized Halving (Scenario II)** mechanism at a highly accelerated pace and validates the **MWEB initial activation**.
> 
> **Built-in Killswitches:** Hardcoded exceptions in `src/chainparams.cpp` intentionally prevent both Mainnet and Testnet daemons from initializing. 
> **This is a critical safety measure to prevent accidental misuse. Since this repository uses 1/1000 scaled parameters, any attempt to connect to public networks would result in immediate consensus rejection by standard nodes.**

### 🌐 Network Availability in Simulation

| Network | Status | Command |
| :--- | :--- | :--- |
| **regtest** | ✅ **Allowed** | `./src/rincoind -regtest` |
| **testnet** | ❌ Disabled | Error & exit |
| **mainnet** | ❌ Disabled | Error & exit |

*Reason: `rincoin-sim` uses 1/1000 scaled block parameters strictly incompatible with public Testnet/Mainnet consensus rules. Both are physically disabled at the code level.*

---

## 🔬 Purpose of this Repository

This repository serves a dual purpose for validating Rincoin's core upgrades prior to mainnet deployment:

### 1. Economic Validation (Customized Halving)
Rincoin implements a sophisticated, multi-phase emission schedule (Scenario II) designed to prevent entropic yield collapse and secure the network's long-term thermodynamic future. To strictly validate this long-term economic model without waiting years for block generation, this repository accelerates the timeline.

In this environment, the `regtest` network is configured to scale down block heights by **1/1000**:
- The standard `nSubsidyHalvingInterval` is set to `210` blocks (simulating 210,000 blocks).
- The Customized Halving trigger (Phase 4) activates at block `840` instead of 840,000.

### 2. Privacy Validation (MWEB Activation)
This environment serves as the ultimate proving ground for the MimbleWimble Extension Block (MWEB) integration. It includes critical consensus fixes for the initial HogEx (Hogwarts Express) transaction, ensuring that MWEB can activate safely without triggering `bad-txns-vin-empty` consensus failures. 
It allows developers to thoroughly validate MWEB Peg-in operations and automated change address obfuscation under accelerated regtest conditions.

---

## 📊 Scaled Emission Schedule (Simulation: 1/1000)

The following table outlines the accelerated timeline for Boundary Value Analysis (BVA) validation via `regtest` RPC commands:

| Phase | Sim Block Height | Original Mainnet Height | Reward (RIN) | Sim Duration (Blocks) |
| :--- | :--- | :--- | :--- | :--- |
| **Phase 0** | 0 - 209 | 0 - 209,999 | 50 | 210 |
| **Phase 1** | 210 - 419 | 210,000 - 419,999 | 25 | 210 |
| **Phase 2** | 420 - 629 | 420,000 - 629,999 | 12.5 | 210 |
| **Phase 3** | 630 - 839 | 630,000 - 839,999 | 6.25 | 210 |
| **Phase 4** | 840 - 2,099 | 840,000 - 2,099,999 | 4 | 1,260 |
| **Phase 5** | 2,100 - 4,199 | 2,100,000 - 4,199,999 | 2 | 2,100 |
| **Phase 6** | 4,200 - 6,299 | 4,200,000 - 6,299,999 | 1 | 2,100 |
| **Terminal**| 6,300+ | 6,300,000+ | 0.6 | Perpetual |

### 🧪 Simulation Scale (rincoin-sim)

| Milestone | Mainnet | This Repo (1/1000) |
| :--- | :--- | :--- |
| CH Activation | 840,000 | 840 |
| Phase 5 Start | 2,100,000 | 2,100 |
| Phase 6 Start | 4,200,000 | 4,200 |
| Terminal Start | 6,300,000 | 6,300 |
| Network | mainnet | regtest only |

---

## ⚙️ Core Architecture (Inherited)

While the emission schedule is accelerated for testing, the underlying architecture remains identical to Rincoin Core:
- **Proof-of-Work (PoW):** RinHash algorithm (BLAKE3 -> Argon2d -> SHA3-256).
- **P2P Sovereignty:** All legacy cryptographic salts and network identifiers have been fully purged.
- **Network Magic Bytes:** `0x52` `0x49` `0x4E` `0x43` ("RINC").

---

## 🔭 How to run the Simulation

Compile the daemon using standard Unix/Windows build procedures, then launch in `regtest` mode to allow CLI command access:

```bash
./src/rincoind -regtest -daemon
```

Create a test wallet and generate a new address:

```bash
./src/rincoin-cli -regtest createwallet "testwallet"
./src/rincoin-cli -regtest getnewaddress
```
*(Copy the generated address to use in the following commands)*

### Step 1: Generate Blocks to Key Milestones
Advance the blockchain to experience all phases of the Customized Halving (Scenario II).

```bash
# Advance to Phase 4 (CH Activation at Block 840)
./src/rincoin-cli -regtest generatetoaddress 840 <your_address>

# Advance to Phase 5 (Block 2,100)
./src/rincoin-cli -regtest generatetoaddress 1260 <your_address>

# Advance to Phase 6 (Block 4,200)
./src/rincoin-cli -regtest generatetoaddress 2100 <your_address>

# Advance to Terminal Phase (Block 6,300)
./src/rincoin-cli -regtest generatetoaddress 2100 <your_address>
```

### Step 2: Validate the Boundary Values
Clear your terminal and run the following command block to output the exact block subsidies at every phase transition. 

```bash
clear
./src/rincoin-cli -regtest getblockstats 839 | grep subsidy
./src/rincoin-cli -regtest getblockstats 840 | grep subsidy
echo "-----------------------------------"
./src/rincoin-cli -regtest getblockstats 2099 | grep subsidy
./src/rincoin-cli -regtest getblockstats 2100 | grep subsidy
echo "-----------------------------------"
./src/rincoin-cli -regtest getblockstats 4199 | grep subsidy
./src/rincoin-cli -regtest getblockstats 4200 | grep subsidy
echo "-----------------------------------"
./src/rincoin-cli -regtest getblockstats 6299 | grep subsidy
./src/rincoin-cli -regtest getblockstats 6300 | grep subsidy
```

*(Note: The `subsidy` is displayed in satoshis. E.g., `400000000` = 4.0 RIN)*


### ⚡ Quick Validation (One-Shot Script)
For rapid end-to-end verification, paste the entire block below into your terminal. This fully automated script will reset the environment, generate all necessary blocks, and output the cleanly formatted Boundary Value Analysis.

```bash
# ===== Customized Halving Full Simulation (One-shot) =====

# 0. Setup: stop daemon, reset, restart
./src/rincoin-cli -regtest stop
rm -rf ~/.rincoin/regtest
./src/rincoind -regtest -daemon
sleep 3

# 1. Create wallet and address
./src/rincoin-cli -regtest createwallet "ch_test"
ADDR=$(./src/rincoin-cli -regtest getnewaddress "sim")
echo "Simulation Address: $ADDR"

# 2. Generate blocks through all phases
echo "[1/4] Advancing to Phase 4 (CH Activation: Block 840)..."
./src/rincoin-cli -regtest generatetoaddress 840 $ADDR > /dev/null

echo "[2/4] Advancing to Phase 5 (Block 2,100)..."
./src/rincoin-cli -regtest generatetoaddress 1260 $ADDR > /dev/null

echo "[3/4] Advancing to Phase 6 (Block 4,200)..."
./src/rincoin-cli -regtest generatetoaddress 2100 $ADDR > /dev/null

echo "[4/4] Advancing to Terminal Phase (Block 6,300)..."
./src/rincoin-cli -regtest generatetoaddress 2100 $ADDR > /dev/null

echo ""
echo "===== Boundary Value Analysis Results ====="

# 3. BVA validation
echo "[Phase 3 → 4: CH Activation]"
echo -n "Block 839  (expect 6.25 RIN): "
./src/rincoin-cli -regtest getblockstats 839 | grep subsidy
echo -n "Block 840  (expect 4.00 RIN): "
./src/rincoin-cli -regtest getblockstats 840 | grep subsidy

echo "[Phase 4 → 5: CH Halving 1]"
echo -n "Block 2099 (expect 4.00 RIN): "
./src/rincoin-cli -regtest getblockstats 2099 | grep subsidy
echo -n "Block 2100 (expect 2.00 RIN): "
./src/rincoin-cli -regtest getblockstats 2100 | grep subsidy

echo "[Phase 5 → 6: CH Halving 2]"
echo -n "Block 4199 (expect 2.00 RIN): "
./src/rincoin-cli -regtest getblockstats 4199 | grep subsidy
echo -n "Block 4200 (expect 1.00 RIN): "
./src/rincoin-cli -regtest getblockstats 4200 | grep subsidy

echo "[Phase 6 → Terminal]"
echo -n "Block 6299 (expect 1.00 RIN): "
./src/rincoin-cli -regtest getblockstats 6299 | grep subsidy
echo -n "Block 6300 (expect 0.60 RIN): "
./src/rincoin-cli -regtest getblockstats 6300 | grep subsidy

echo ""
echo "===== Simulation Complete ====="
```

---

## ✅ Validation Results

Boundary Value Analysis (BVA) confirms that the Customized Halving (Scenario II) executes correctly at 1/1000 scaled block heights.

| Block (sim) | Block (mainnet) | Subsidy (satoshi) | RIN | Result |
| :--- | :--- | :--- | :--- | :--- |
| 839 | 839,000 | 625,000,000 | 6.25 | ✅ PASS |
| **840** | **840,000** | **400,000,000** | **4.00** | ✅ **CH Activated** |
| 2,099 | 2,099,000 | 400,000,000 | 4.00 | ✅ PASS |
| **2,100** | **2,100,000** | **200,000,000** | **2.00** | ✅ **CH Halving 1** |
| 4,199 | 4,199,000 | 200,000,000 | 2.00 | ✅ PASS |
| **4,200** | **4,200,000** | **100,000,000** | **1.00** | ✅ **CH Halving 2** |
| 6,299 | 6,299,000 | 100,000,000 | 1.00 | ✅ PASS |
| **6,300** | **6,300,000** | **60,000,000** | **0.60** | ✅ **Terminal** |

> *Test Date: 2026-04-20*  
> *Environment: regtest (1/1000 scale)*  
> *Network: rincoin-sim (mainnet & testnet disabled)*

---

## 🛡️ MWEB (MimbleWimble Extension Block) Simulation

This repository includes a critical consensus fix for the initial 
HogEx transaction, enabling MWEB to activate safely on Rincoin.

### Reproducible MWEB Test Script

Stop the daemon and reset the regtest environment:
```bash
./src/rincoin-cli -regtest stop
rm -rf ~/.rincoin/regtest
./src/rincoind -regtest -daemon
sleep 3
```

Copy and paste the entire block below:

```bash
# 1. Create test wallet
./src/rincoin-cli -regtest createwallet "mweb_test"

# 2. Generate addresses
# Note: Mining rewards must go to transparent address (rrin1...)
# MWEB address (rrmweb1...) is for receiving via sendtoaddress only
MINER_ADDR=$(./src/rincoin-cli -regtest getnewaddress "miner")
MWEB_ADDR=$(./src/rincoin-cli -regtest getnewaddress "mweb_receiver" "mweb")
echo "Miner (Transparent): $MINER_ADDR"
echo "Receiver (MWEB)    : $MWEB_ADDR"

# 3. Mine 450 blocks to transparent address
# (MWEB activates at ~block 432 in regtest)
./src/rincoin-cli -regtest generatetoaddress 450 $MINER_ADDR

# 4. Peg-in: Send 10 RIN from transparent chain to MWEB
./src/rincoin-cli -regtest sendtoaddress $MWEB_ADDR 10

# 5. Mine 1 block to confirm
./src/rincoin-cli -regtest generatetoaddress 1 $MINER_ADDR

# 6. Verify MWEB balance
./src/rincoin-cli -regtest listaddressgroupings
```

---

### ⚡ MWEB Quick Validation (One-Shot Script)
For rapid end-to-end verification, paste the entire block below into your terminal. This fully automated script will reset the environment, generate the required blocks, execute the Peg-in transaction, and output the final balances.

```bash
# ===== MWEB Full Simulation (One-shot) =====

# 0. Reset environment
./src/rincoin-cli -regtest stop 2>/dev/null
sleep 1
rm -rf ~/.rincoin/regtest
./src/rincoind -regtest -daemon
sleep 3

# 1. Create wallet and addresses
./src/rincoin-cli -regtest createwallet "mweb_test" > /dev/null
MINER_ADDR=$(./src/rincoin-cli -regtest getnewaddress "miner")
MWEB_ADDR=$(./src/rincoin-cli -regtest getnewaddress "mweb_receiver" "mweb")
echo "Miner (Transparent): $MINER_ADDR"
echo "MWEB  (Private)    : $MWEB_ADDR"
echo ""

# 2. Mine blocks
echo "[1/3] Mining 450 blocks (MWEB activates at ~block 432)..."
./src/rincoin-cli -regtest generatetoaddress 450 $MINER_ADDR > /dev/null

# 3. Peg-in
echo "[2/3] Peg-in: Sending 10 RIN to MWEB address..."
./src/rincoin-cli -regtest sendtoaddress $MWEB_ADDR 10 > /dev/null

# 4. Confirm
echo "[3/3] Mining 1 block to confirm Peg-in..."
./src/rincoin-cli -regtest generatetoaddress 1 $MINER_ADDR > /dev/null

echo ""
echo "===== MWEB Validation Results ====="
./src/rincoin-cli -regtest listaddressgroupings
echo ""
echo "===== Simulation Complete ====="
echo "Expected: rrmweb1... address holding 10.00000000 RIN"
```

---

## ✅ Expected Result

```bash
===== MWEB Validation Results =====
[
  [
    [
      "rrin1q8twvefee3rpvk2yj...",
      13975.00000000,
      "miner"
    ]
  ],
  [
    [
      "rrmweb1qq0mdeg9msd2hqm...",
      14.99963500
    ]
  ],
  [
    [
      "rrmweb1qqfd6u6nk4pvyu9...",
      10.00000000,
      "mweb_receiver"
    ]
  ]
]

===== Simulation Complete =====
Expected: rrmweb1... address holding 10.00000000 RIN
```

> *Test Date: 2026-04-20*  
> *Environment: regtest (1/1000 scale)*  
> *Network: rincoin-sim (mainnet & testnet disabled)*

---

### Understanding the Output
The presence of two MWEB addresses is the intended behavior and cryptographically proves that the privacy features are fully functional:
* `mweb_receiver`: Holds the exact `10.00000000 RIN` explicitly sent via the Peg-in transaction.
* **Unlabeled MWEB Address (`14.999... RIN`)**: This is an automatically generated **Change Address**. Following the standard UTXO model, the remaining balance from the Peg-in transaction (minus network fees) is routed to this newly generated, hidden MWEB address to maximize transaction privacy.
* `miner`: The remaining transparent balance from the initial block generation.

**Conclusion:** The MWEB integration, including Peg-in transactions and automated change obfuscation, is operating flawlessly.

> ⚠️ Note: `generatetoaddress` only accepts transparent addresses (`rrin1...`).  
> MWEB addresses (`rrmweb1...`) receive funds via `sendtoaddress` only.  
> This is expected behavior, identical to Litecoin MWEB specification.

---

### 📸 Proof of Simulation (Screenshot)
![Validation Results at Block 6300](doc/assets/simulation-bva-results.png)

![MWEB Validation Results](doc/assets/simulation-mimble-wimble-results.png)

---

## 💬 Community

Join the official Rincoin community to stay updated, get support, and discuss development:

[![Discord Banner 2](https://discord.com/api/guilds/1354664874176680017/widget.png?style=banner2)](https://discord.gg/H4Du5YuqFa)


