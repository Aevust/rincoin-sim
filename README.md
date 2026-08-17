# Rincoin-Sim: Customized Halving & MWEB Simulation Environment

![License](https://img.shields.io/badge/license-MIT-green.svg)
![Status](https://img.shields.io/badge/status-REGTEST_ONLY-critical.svg)
[![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.20363269-blue)](https://doi.org/10.5281/zenodo.20363269)

> ⚠️ **CRITICAL WARNING: REGTEST ONLY / DO NOT MERGE TO MAINNET** ⚠️
>
> This repository (`rincoin-sim`) is a dedicated simulation environment strictly designed for local `regtest` execution. It tests the **Customized Halving (Scenario II)** mechanism at a highly accelerated pace and validates the **MWEB full lifecycle (Peg-in, Peg-out, and Reorg)**.
>
> **Built-in Killswitch:** A daemon-level guard in `src/bitcoind.cpp` refuses every chain except regtest. Mainnet, testnet and signet all fail at startup with an error naming the chain. (`src/chainparams.cpp` carries only a pointer comment to it.)
> **Startup self-check:** every start also asserts that the Customized Halving fork height equals four times the halving interval, on all three networks -- the daemon constructs them all at startup -- so a mis-scaled build aborts before it runs.
> **This is a critical safety measure to prevent accidental misuse. Since this repository uses 1/1000 scaled parameters, any attempt to connect to public networks would result in immediate consensus rejection by standard nodes.**

### Network Availability in Simulation

| Network | Status | Command |
| :--- | :--- | :--- |
| **regtest** | ✅ **Allowed** | `./bin/rincoind -regtest -daemon` |
| **testnet** | ❌ Refused | Error & exit |
| **mainnet** | ❌ Refused | Error & exit |
| **signet** | ❌ Refused | Error & exit (`-signet` / `-chain=signet`) |

*Reason: `rincoin-sim` uses 1/1000 scaled block parameters strictly incompatible with public network consensus rules. The daemon refuses every chain except regtest. The built-in `-help` text still lists all four chains under `-chain=`; that text is inherited, and the daemon's refusal is what governs.*

---

## Purpose of this Repository

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

## Scaled Emission Schedule (Simulation: 1/1000)

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

### Simulation Scale (rincoin-sim)

| Milestone | Mainnet | This Repo (1/1000) |
| :--- | :--- | :--- |
| CH Activation | 840,000 | 840 |
| Phase 5 Start | 2,100,000 | 2,100 |
| Phase 6 Start | 4,200,000 | 4,200 |
| Terminal Start | 6,300,000 | 6,300 |
| Network | mainnet | regtest only |

---

## Core Architecture (Inherited)

While the emission schedule is accelerated for testing, the underlying architecture remains identical to Rincoin Core:
- **Proof-of-Work (PoW):** RinHash algorithm (BLAKE3 -> Argon2d -> SHA3-256).
- **P2P Sovereignty:** All legacy cryptographic salts and network identifiers have been fully purged.
- **Network Magic Bytes:** `0x52` `0x49` `0x4E` `0x43` ("RINC").

---

## Automated Simulation Scripts (Recommended)

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

## How to run the Simulation

Download the latest release tarball and extract it to your preferred
directory. The binaries are self-contained and require no external
dependencies.

```bash
# 1. Extract the release tarball (the file name carries the version and platform)
tar -xzf rincoin-sim-<version>-x86_64-linux-gnu.tar.gz

# 2. Navigate to the extracted directory
cd rincoin-sim-<version>-x86_64-linux-gnu/
```

> **Automated scripts** (`./scripts/sim-ch.sh`, `./scripts/sim-mweb.sh`) must be
> run from this root directory. **Manual commands** below require navigating into `bin/`:

```bash
# For manual verification only
cd bin/
```

> All manual commands below assume you are inside the
> `rincoin-sim-<version>-x86_64-linux-gnu/bin/` directory.

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

### Quick Validation (One-Shot Script)

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

## Validation Results

Boundary Value Analysis (BVA) confirms that the Customized Halving executes correctly at 1/1000 scaled block heights.

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

Beyond the table above, the archived evidence covers, per release:

- **MWEB full lifecycle** -- activation, peg-in, peg-out, and reorg
  resilience across the MWEB activation boundary (`scripts/sim-mweb.sh`)
- **RIN3 nVersion enforcement** -- boundary behaviour at the fork height,
  mempool defense, and P2P service signaling
  (`scripts/sim-ch-rin3.sh`, `test/functional/feature_rin3_enforcement.py`,
  `test/functional/p2p_rin3_services.py`)
- **Deep-reorg attack resilience** -- reorgs of up to 2,101 blocks that
  erase entire economic phases and remine them, with deterministic
  subsidy recovery (`scripts/sim-ch-attack.sh`)
- **Taproot wallet guard** -- witness v1+ refusal at the wallet layer
  while MWEB stays functional
  (`test/functional/feature_taproot_wallet_guard.py`)

Full logs are not quoted here. They are archived on Zenodo, citable by
DOI, and reproducible from this tree: every result above comes from a
script or functional test that ships in this repository, and each
release's evidence bundle carries the logs together with a signed
digest list (`SHA256SUMS` + `SHA256SUMS.asc`). Start with `MANIFEST.md`
in the bundle; it states what the bundle establishes and what it does
not.

- All versions (concept DOI, resolves to the latest release's bundle):
  [![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.20363269-blue)](https://doi.org/10.5281/zenodo.20363269)
- v1.1.0 release evidence (functional suite, simulation logs, signed
  digest list): [10.5281/zenodo.21805345](https://doi.org/10.5281/zenodo.21805345)
- v1.0.7 simulation artifacts (Monte Carlo, BVA, MWEB lifecycle and
  reorg): [10.5281/zenodo.20745260](https://doi.org/10.5281/zenodo.20745260)

---

## Community

Join the official Rincoin community to stay updated, get support, and discuss development:

[![Discord Banner 2](https://discord.com/api/guilds/1354664874176680017/widget.png?style=banner2)](https://discord.gg/H4Du5YuqFa)
