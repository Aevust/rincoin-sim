# Rincoin-Sim: Customized Halving Simulation Environment

![Version](https://img.shields.io/badge/version-1.0.6--sim-red.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Status](https://img.shields.io/badge/status-SIMULATION_ONLY-critical.svg)

> ⚠️ **CRITICAL WARNING: DO NOT MERGE TO MAINNET** ⚠️
> 
> This repository (`rincoin-sim`) is a dedicated simulation environment strictly designed to test the Customized Halving (Scenario II) mechanism on the `regtest` network at a highly accelerated pace.
> 
> The hardcoded block height thresholds in `src/validation.cpp` and `src/chainparams.cpp` have been intentionally scaled down by **1/1000**. 
> **Using this codebase to run a Mainnet or public Testnet node will result in immediate network consensus failure, severe chain forks, and catastrophic disruption of the Rincoin economy.**

---

## 🔬 Purpose of this Repository

Rincoin implements a sophisticated, multi-phase emission schedule (Scenario II) designed to prevent entropic yield collapse and secure the network's long-term thermodynamic future. To strictly validate this long-term economic model without waiting years for block generation, this repository accelerates the timeline.

In this environment, the `regtest` network is configured to scale down block heights by **1/1000**:
- The standard `nSubsidyHalvingInterval` is set to `210` blocks (simulating 210,000 blocks).
- The Customized Halving trigger (Phase 4) activates at block `840` instead of 840,000.

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


---

## ✅ Validation Results

Boundary Value Analysis (BVA) confirming Customized Halving 
(Scenario II) executes correctly at 1/1000 scaled block heights.

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

*Test Date: 2026-04-19*  
*Environment: regtest (1/1000 scale)*  
*Network: rincoin-sim (mainnet disabled)*

---

### 📸 Proof of Simulation (Screenshot)
![Validation Results at Block 6300](assets/simulation-bva-results.png)

---

## 💬 Community

Join the official Rincoin community to stay updated, get support, and discuss development:

[![Discord Banner 2](https://discord.com/api/guilds/1354664874176680017/widget.png?style=banner2)](https://discord.gg/H4Du5YuqFa)

```
```
