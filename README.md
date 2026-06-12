# Rincoin-Sim: Customized Halving & MWEB Simulation Environment

![Version](https://img.shields.io/badge/version-1.0.7--sim-red.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Status](https://img.shields.io/badge/status-REGTEST_ONLY-critical.svg)
[![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.20363269-blue)](https://doi.org/10.5281/zenodo.20363269)

> ⚠️ **CRITICAL WARNING: REGTEST ONLY / DO NOT MERGE TO MAINNET** ⚠️
> 
> This repository (`rincoin-sim`) is a dedicated simulation environment strictly designed for local `regtest` execution. It tests the **Customized Halving (Scenario II)** mechanism at a highly accelerated pace and validates the **MWEB full lifecycle (Peg-in, Peg-out, and Reorg)**.
> 
> **Built-in Killswitches:** Hardcoded exceptions in `src/chainparams.cpp` intentionally prevent both Mainnet and Testnet daemons from initializing. 
> **This is a critical safety measure to prevent accidental misuse. Since this repository uses 1/1000 scaled parameters, any attempt to connect to public networks would result in immediate consensus rejection by standard nodes.**

### 🌐 Network Availability in Simulation

| Network | Status | Command |
| :--- | :--- | :--- |
| **regtest** | ✅ **Allowed** | `./bin/rincoind -regtest -daemon` |
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

### 2. Privacy Validation (MWEB Activation & Resilience)
This environment serves as the ultimate proving ground for the MimbleWimble Extension Block (MWEB) integration. It includes critical consensus fixes for the initial HogEx (Hogwarts Express) transaction, ensuring that MWEB can activate safely without triggering `bad-txns-vin-empty` consensus failures.
Unlike standard activation tests, our automated suite fully validates the complete MWEB lifecycle:
- **Peg-in**: Secure transfer from Transparent to MWEB.
- **Peg-out**: Secure transfer from MWEB back to Transparent addresses.
- **Reorg Resilience**: Proves MWEB transaction robustness during blockchain rollbacks (`invalidateblock`) and re-mining events.

### 3. Consensus Integrity Validation (RIN3 nVersion & Reorg Determinism)
Beyond economics and privacy, this environment validates that the **RIN3 transaction-version marker** (`nVersion = 0x52494e33`) is emitted and enforced exactly at the fork height, and that subsidy issuance is **deterministic under deep chain reorganizations**. The consolidated `sim-ch-rin3.sh` suite proves that `GetBlockSubsidy` is a pure function of block height — the correct reward is always restored after a rollback, regardless of reorg depth (validated up to a 2,101-block, two-phase reorg).

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

## 🚀 Automated Simulation Scripts (Recommended)

If you have cloned this repository, the fastest way to validate is via the automated scripts in `scripts/`. They handle daemon initialization, wallet creation, block generation, and result output automatically.

> *Note: These scripts require a Linux/Unix environment (or WSL on Windows).*

### Customized Halving Simulation
Validates all BVA boundary values of the scaled emission schedule end-to-end.
```bash
./scripts/sim-ch.sh
```

### MWEB Full Lifecycle Simulation
Validates Peg-in, Peg-out (with wallet isolation), and Chain Reorganization (Reorg) resilience in a single automated run.
```bash
./scripts/sim-mweb.sh
```

### Combined CH × RIN3 & Attack Resilience Simulation
The primary regression suite (broadest coverage). In one regtest session it validates the full emission schedule (BVA), RIN3 wallet nVersion enforcement at the fork boundary, and subsidy determinism under four escalating reorg-attack scenarios (max depth: 2,101 blocks across two economic phases). For the deepest attack proof (full CH-history erasure), see `sim-ch-attack.sh` below.
```bash
./scripts/sim-ch-rin3.sh
```
> Companion negative consensus test (node-level rejection of legacy-nVersion
> blocks at height ≥ fork): `test/functional/feature_rin3_enforcement.py`

### Deep-Reorg Attack Proof (Omega Edition)
The dedicated, heavyweight, attack proof. It runs the full phase advance and BVA, then **five** escalating reorg scenarios — culminating in a 5,461-block **full CH-history erasure** (Omega: invalidate block 840 from the Terminal phase at h=6,300, then re-mine every phase boundary from scratch). This proves `GetBlockSubsidy` is a pure function of height even when the *entire* Customized Halving history is wiped.
```bash
./scripts/sim-ch-attack.sh
```
> Runtime: ~15–20 min (vs ~5 min for `sim-ch-rin3.sh`). Use this for release-grade
> attack evidence; use `sim-ch-rin3.sh` for routine regression. This script does
> **not** include the RIN3 wallet tests — those live in `sim-ch-rin3.sh` (Section 3).

---

## 🔭 How to run the Simulation

Download the latest release tarball and extract it to your preferred
directory. The binaries are self-contained and require no external
dependencies.

```bash
# 1. Extract the release tarball
tar -xzf rincoin-sim-v1.0.7-linux-x86_64.tar.gz

# 2. Navigate to the project root directory
cd rincoin-sim-v1.0.7-linux-x86_64/
```

> 💡 **Automated scripts** (`./scripts/sim-ch.sh`, `./scripts/sim-mweb.sh`) must be
> run from this root directory. **Manual commands** below require navigating into `bin/`:

```bash
# For manual verification only
cd bin/
```

> 💡 All manual commands below assume you are inside the
> `rincoin-sim-v1.0.7-linux-x86_64/bin/` directory.

Launch the simulator daemon in regtest mode:

```bash
./rincoind -regtest -daemon
```

Create a test wallet and generate a new address:

```bash
./rincoin-cli -regtest createwallet "testwallet"
./rincoin-cli -regtest getnewaddress
```
*(Copy the generated address to use in the following commands)*

### Step 1: Generate Blocks to Key Milestones

```bash
# Advance to Phase 4 (CH Activation at Block 840)
./rincoin-cli -regtest generatetoaddress 840 <your_address> > /dev/null

# Advance to Phase 5 (Block 2,100)
./rincoin-cli -regtest generatetoaddress 1260 <your_address> > /dev/null

# Advance to Phase 6 (Block 4,200)
./rincoin-cli -regtest generatetoaddress 2100 <your_address> > /dev/null

# Advance to Terminal Phase (Block 6,300)
./rincoin-cli -regtest generatetoaddress 2100 <your_address> > /dev/null
```

### Step 2: Validate the Boundary Values

```bash
clear
./rincoin-cli -regtest getblockstats 839 | grep subsidy
./rincoin-cli -regtest getblockstats 840 | grep subsidy
echo "-----------------------------------"
./rincoin-cli -regtest getblockstats 2099 | grep subsidy
./rincoin-cli -regtest getblockstats 2100 | grep subsidy
echo "-----------------------------------"
./rincoin-cli -regtest getblockstats 4199 | grep subsidy
./rincoin-cli -regtest getblockstats 4200 | grep subsidy
echo "-----------------------------------"
./rincoin-cli -regtest getblockstats 6299 | grep subsidy
./rincoin-cli -regtest getblockstats 6300 | grep subsidy
```

---

### ⚡ Quick Validation (One-Shot Script)

```bash
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

This repository includes critical consensus fixes for the initial HogEx transaction, enabling MWEB to activate safely on Rincoin. The full lifecycle — Peg-in, Peg-out, and Reorg resilience — has been validated under accelerated regtest conditions.

### Reproducible MWEB Test Script

Stop the daemon and reset the regtest environment:
```bash
./rincoin-cli -regtest stop
rm -rf ~/.rincoin/regtest
./rincoind -regtest -daemon
sleep 3
```

Copy and paste the entire block below:

```bash
# 1. Create test wallet
./rincoin-cli -regtest createwallet "mweb_test"

# 2. Generate addresses
# Note: Mining rewards must go to transparent address (rrin1...)
# MWEB address (rrmweb1...) is for receiving via sendtoaddress only
MINER_ADDR=$(./rincoin-cli -regtest getnewaddress "miner")
MWEB_ADDR=$(./rincoin-cli -regtest getnewaddress "mweb_receiver" "mweb")
echo "Miner (Transparent): $MINER_ADDR"
echo "Receiver (MWEB)    : $MWEB_ADDR"

# 3. Mine 450 blocks to transparent address
# (MWEB activates at ~block 432 in regtest)
./rincoin-cli -regtest generatetoaddress 450 $MINER_ADDR > /dev/null

# 4. Peg-in: Send 10 RIN from transparent chain to MWEB
./rincoin-cli -regtest sendtoaddress $MWEB_ADDR 10 > /dev/null

# 5. Mine 1 block to confirm
./rincoin-cli -regtest generatetoaddress 1 $MINER_ADDR > /dev/null

# 6. Verify MWEB balance
./rincoin-cli -regtest listaddressgroupings
```

---

### ⚡ MWEB Peg-In Quick Validation (One-Shot Script)
For rapid end-to-end verification, paste the entire block below into your terminal. This script validates Peg-in activation only. For full lifecycle validation (Peg-in, Peg-out, and Reorg), use `./scripts/sim-mweb.sh`.

```bash
# ===== MWEB Full Simulation (One-shot) =====

# 0. Reset environment
./rincoin-cli -regtest stop 2>/dev/null
sleep 1
rm -rf ~/.rincoin/regtest
./rincoind -regtest -daemon
sleep 3

# 1. Create wallet and addresses
./rincoin-cli -regtest createwallet "mweb_test" > /dev/null
MINER_ADDR=$(./rincoin-cli -regtest getnewaddress "miner")
MWEB_ADDR=$(./rincoin-cli -regtest getnewaddress "mweb_receiver" "mweb")
echo "Miner (Transparent): $MINER_ADDR"
echo "MWEB  (Private)    : $MWEB_ADDR"
echo ""

# 2. Mine blocks
echo "[1/3] Mining 450 blocks (MWEB activates at ~block 432)..."
./rincoin-cli -regtest generatetoaddress 450 $MINER_ADDR > /dev/null

# 3. Peg-in
echo "[2/3] Peg-in: Sending 10 RIN to MWEB address..."
./rincoin-cli -regtest sendtoaddress $MWEB_ADDR 10 > /dev/null

# 4. Confirm
echo "[3/3] Mining 1 block to confirm Peg-in..."
./rincoin-cli -regtest generatetoaddress 1 $MINER_ADDR > /dev/null

echo ""
echo "===== MWEB Validation Results ====="
./rincoin-cli -regtest listaddressgroupings
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

### ✅ MWEB Full Lifecycle Results (sim-mweb.sh)

```text
===== Peg-out Results =====
Transparent 2 received : 5.00000000 RIN (expect ~5.0)
MWEB remaining         : 4.99991600 RIN (expect ~4.999)

[6/6] Reorg Test: Invalidating Peg-out block...
  After invalidate: height=451 (expect 451)
  Transaction status : "confirmations": (expect 0 or orphaned)
  -> Generating a dummy transaction to ensure a unique block hash...
  Re-mining replacement block...
  After re-mine: height=452 (expect 452)

===== Simulation Complete =====
Validated: Transparent → MWEB (Peg-in) → Transparent (Peg-out) + Reorg
```

> *Test Date: 2026-04-25*  
> *Environment: regtest (1/1000 scale)*  
> *Network: rincoin-sim (mainnet & testnet disabled)*

---

### Understanding the Output
The presence of two MWEB addresses is the intended behavior and cryptographically proves that the privacy features are fully functional:
* `mweb_receiver`: Holds the exact `10.00000000 RIN` explicitly sent via the Peg-in transaction.
* **Unlabeled MWEB Address (`14.999... RIN`)**: This is an automatically generated **Change Address**. Following the standard UTXO model, the remaining balance from the Peg-in transaction (minus network fees) is routed to this newly generated, hidden MWEB address to maximize transaction privacy.
* `miner`: The remaining transparent balance from the initial block generation.

**Conclusion:** The MWEB integration, including Peg-in, Peg-out, automated change obfuscation, and Reorg resilience, is operating flawlessly.

> ⚠️ Note: `generatetoaddress` only accepts transparent addresses (`rrin1...`).  
> MWEB addresses (`rrmweb1...`) receive funds via `sendtoaddress` only.  
> This is expected behavior, identical to Litecoin MWEB specification.

---

## 🔐 CH × RIN3 & Attack Resilience Simulation

`./scripts/sim-ch-rin3.sh` is the consolidated validation entry point. It runs four sequential sections in a single regtest session:

| Section | Scope | Coverage |
| :--- | :--- | :--- |
| **1. Phase Advance** | Mine blocks 1 → 6,400 | All 8 phase boundaries materialized |
| **2. BVA** | Boundary Value Analysis | Subsidy correctness at 839/840, 2099/2100, 4199/4200, 6299/6300 |
| **3. RIN3 Wallet Tests** | nVersion enforcement | Wallet emits `0x52494e33` at/above fork, legacy below |
| **4. Attack Simulation** | Reorg determinism | 4 escalating rollback scenarios (max depth 2,101 blocks) |

### RIN3 nVersion Enforcement (Section 3)

`nRinHashForkHeight` (regtest) = **840**. RIN3 marker = `0x52494e33` = `1380535859`.
Wallet rule (`txassembler.cpp`): if chain tip at send time `>= 839` → emit RIN3; else legacy nVersion.

| Scenario | Chain Tip at Send | Wallet nVersion | Mined / Enforced At | Result |
| :--- | :--- | :--- | :--- | :--- |
| **[RIN3-1]** Above fork | h > 840 | `0x52494e33` (RIN3) | h > 840 (enforced) | ✅ PASS |
| **[RIN3-2]** Boundary edge | tip = 839 (839 ≥ 839) | `0x52494e33` (RIN3) | h = 840 (enforced) | ✅ PASS |
| **[RIN3-3]** Below boundary | tip = 838 (838 < 839) | `2` (legacy) | h = 839 (not yet enforced) | ✅ PASS |

### Attack Simulation (Section 4)

**Thesis:** `GetBlockSubsidy` is a pure function of block height. No matter how deep the reorg, the correct subsidy is restored on re-mine.

| # | Scenario | Reorg Path | Depth | Rolled-back → Restored | Result |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **[A]** | Minimal | 840 → 839 → 840 | 1 block | 6.25 → 4.00 RIN | ✅ PASS |
| **[B]** | Super | 2,100 → 839 → 2,100 | 1,261 blocks | 6.25 → 2.00 RIN (Phase 4 erased) | ✅ PASS |
| **[C]** | Cross-Phase | 4,200 → 2,099 → 4,200 | 2,101 blocks | 4.00 → 1.00 RIN (Phase 5 erased) | ✅ PASS |
| **[D]** | Terminal | 6,300 → 4,199 → 6,300 | 2,101 blocks | 2.00 → 0.60 RIN (Phase 6 + Terminal erased) | ✅ PASS |

> *Max reorg depth: 2,101 blocks across 2 economic phases.*  
> *Companion negative consensus test: `test/functional/feature_rin3_enforcement.py`*

> *Test Date: 2026-05-17*  
> *Environment: regtest (1/1000 scale)*  
> *Network: rincoin-sim (mainnet & testnet disabled)*

---

### 📸 Proof of Simulation (Screenshot & Log)
Full simulation artifacts (Monte Carlo, BVA, MWEB lifecycle and reorg) are archived on Zenodo and citable by DOI.

[![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.20363269-blue)](https://doi.org/10.5281/zenodo.20363269)

---

## 💬 Community

Join the official Rincoin community to stay updated, get support, and discuss development:

[![Discord Banner 2](https://discord.com/api/guilds/1354664874176680017/widget.png?style=banner2)](https://discord.gg/H4Du5YuqFa)
