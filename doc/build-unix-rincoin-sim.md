# Rincoin-Sim Build & Test Procedure

[![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.20363269-blue)](https://doi.org/10.5281/zenodo.20363269)
**Environment**: Ubuntu 24.04 LTS (VirtualBox)
**Target**: rincoin-sim v1.0.7 — 1/1000 scale functional test environment
**Verified**: 2026-05-23

---

## Table of Contents

1. [System Dependencies](#1-system-dependencies)
2. [BDB 4.8 Build](#2-bdb-48-build)
3. [Configure](#3-configure)
4. [Make (Build)](#4-make-build)
5. [Python Environment Setup](#5-python-environment-setup)
6. [Test Framework Patches](#6-test-framework-patches)
7. [Running Tests](#7-running-tests)
8. [Troubleshooting](#8-troubleshooting)
9. [Release Packaging](#9-release-packaging)
10. [Verification & GPG Signing](#10-verification--gpg-signing)

---

## 1. System Dependencies

```bash
# Build tools
sudo apt install -y \
    build-essential libtool autotools-dev automake \
    pkg-config libssl-dev libboost-all-dev \
    python3.12-venv python3-dev

# Qt5 (only if building rincoin-qt; rincoin-sim is CLI-only and can skip)
sudo apt install -y \
    qtbase5-dev qttools5-dev-tools

# Rust (required for blake3 Python package)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# Select option 1 (standard installation)
source ~/.cargo/env
```

---

## 2. BDB 4.8 Build

Rincoin inherits Litecoin's BDB 4.8 requirement for wallet portability.
The system ships BDB 5.3, so BDB 4.8 must be built from source.

```bash
cd ~/rincoin-sim

# Build BDB 4.8 into ./db4/
./contrib/install_db4.sh `pwd`

# Export the path (required for every new shell session)
export BDB_PREFIX="$HOME/rincoin-sim/db4"
```

To avoid re-exporting on every session, add to `~/.bashrc`:

```bash
echo "export BDB_PREFIX=\"$HOME/rincoin-sim/db4\"" >> ~/.bashrc
source ~/.bashrc
```

---

## 3. Configure

```bash
cd ~/rincoin-sim

./autogen.sh

./configure \
    --without-miniupnpc \
    --without-gui \
    --disable-bench \
    --with-pic \
    BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" \
    BDB_CFLAGS="-I${BDB_PREFIX}/include"
```

### Option flags explained

| Flag | Reason |
|------|--------|
| `--without-miniupnpc` | Not needed for sim |
| `--without-gui` | rincoin-sim is CLI-only; omitting this builds Qt unnecessarily. Use `--with-gui=qt5` only for full Core release |
| `--disable-bench` | Speeds up build |
| `--with-pic` | Required to link static libs (`libargon2.a`, `libbitcoin_util.a`) into shared `libbitcoinconsensus.la`; omitting causes `R_X86_64_PC32 relocation` error |
| `BDB_LIBS / BDB_CFLAGS` | Points to the locally built BDB 4.8 |

### Expected configure output (success indicators)

```
checking for Berkeley DB C++ headers... /home/<user>/rincoin-sim/db4
...
configure: creating ./config.status
```

---

## 4. Make (Build)

```bash
# Build with all CPU cores, save log
make -j$(nproc) 2>&1 | tee build_$(date +%m%d).log

# Run unit tests (test_rincoin Boost suite + libsecp256k1).
# No Qt test is built under --without-gui, so a display is not required.
make check 2>&1 | tee test_$(date +%m%d).log
```

### Expected warnings (non-blocking)

```
*** Warning: Linking the shared library libbitcoinconsensus.la against the
*** static library ../src/crypto/argon2/libargon2.a is not portable!
```

These portability warnings are harmless. The build succeeds.

### make check note

`test_rincoin` (Boost) and `exhaustive_tests` (libsecp256k1) are the only test targets built under `--without-gui`. No display is required.

### Built binaries

| File | Role |
|------|------|
| `src/rincoind` | Daemon (main binary) |
| `src/rincoin-cli` | RPC controller |
| `src/rincoin-tx` | Raw transaction tool |
| `src/rincoin-wallet` | Offline wallet maintenance tool |
| `src/qt/rincoin-qt` | GUI (only built without `--without-gui`) |

---

## 5. Python Environment Setup

### Create virtual environment

```bash
# python3.12-venv must be installed (Step 1)
python3 -m venv ~/rincoin-venv
source ~/rincoin-venv/bin/activate
# Prompt changes to (rincoin-venv)
```

Add to `~/.bashrc` to auto-activate:

```bash
echo "source ~/rincoin-venv/bin/activate" >> ~/.bashrc
source ~/.bashrc
```

### Install Python packages

```bash
pip install --upgrade pip
pip install blake3 argon2-cffi
```

### Verify

```bash
python3 -c "import blake3; import argon2; print('OK')"
# Expected: OK
```

---

## 6. Test Framework Patches

Three files required patching to replace Litecoin-specific code with Rincoin equivalents.

### 6-1. `test/functional/test_framework/messages.py`

**Problem**: `import litecoin_scrypt` — this module does not exist in rincoin-sim or Litecoin master.
**Root cause**: `litecoin_scrypt.getPoWHash()` was Litecoin's scrypt PoW helper. Rincoin uses RinHash (BLAKE3 → Argon2d → SHA3-256).

**Change summary**:

| Location | Before | After |
|----------|--------|-------|
| Line 32 | `import litecoin_scrypt` | Inline `rinhash()` function |
| `CBlockHeader.__slots__` | `"scrypt256"` | `"rinhash256"` |
| `calc_sha256()` | `litecoin_scrypt.getPoWHash(r)` | `rinhash(r)` |
| `CBlock.is_valid()` | `self.scrypt256 > target` | `self.rinhash256 > target` |
| `CBlock.solve()` | `self.scrypt256 > target` | `self.rinhash256 > target` |

**RinHash Python implementation** (replaces `import litecoin_scrypt`):

```python
# RinHash: BLAKE3 -> Argon2d -> SHA3-256 (replaces litecoin_scrypt)
# Matches rinhash.cpp: BLAKE3(header) -> Argon2d(t=2,m=64,p=1,salt="RinCoinSalt") -> SHA3-256
import hashlib as _hashlib
import blake3 as _blake3
from argon2.low_level import hash_secret_raw as _argon2_raw, Type as _Argon2Type

def rinhash(header_bytes: bytes) -> bytes:
    """Pure-Python RinHash: matches rinhash.cpp (BLAKE3 -> Argon2d -> SHA3-256)."""
    b3 = _blake3.blake3(header_bytes).digest()
    a2 = _argon2_raw(
        secret=b3,
        salt=b"RinCoinSalt",
        time_cost=2,
        memory_cost=64,
        parallelism=1,
        hash_len=32,
        type=_Argon2Type.D,
    )
    return _hashlib.sha3_256(a2).digest()
```

### 6-2. `test/functional/test_framework/blocktools.py`

**Problem**: `create_block()` defaults to `nVersion=1`, which Rincoin rejects (requires BIP9-style `0x20000000+`).

**Change** (line 66):

```python
# Before
block.nVersion = version or tmpl.get('version') or 1

# After
block.nVersion = version or tmpl.get('version') or 4  # Default to BIP34/65/66-compliant version
```

> Note: In practice, `_build_block()` in tests calls `getblocktemplate` to get the exact required version, so this default is a safety fallback only.

### 6-3. `test/functional/feature_rin3_enforcement.py`

Three issues were fixed:

**Fix A — `set_test_params`: missing comma caused implicit string concatenation**

```python
# Before (BUG: "-acceptnonstdtxn=0" and "-vbparams=..." were concatenated)
self.extra_args = [["-fallbackfee=0.001", "-acceptnonstdtxn=0"]]

# After
self.extra_args = [[
    "-fallbackfee=0.001",
    "-acceptnonstdtxn=0",
    # Disable MWEB for this test: MWEB+RIN3 interaction is covered by
    # feature_rin3_mweb_exemption.py. Use far-future timestamp (~2286)
    # as a practical equivalent of NEVER_ACTIVE.
    "-vbparams=mweb:9999999999:9999999999",
]]
```

**Fix B — `_build_block`: use `getblocktemplate` version + `add_witness_commitment`**

```python
def _build_block(self, extra_txs):
    node       = self.nodes[0]
    tip_hash   = node.getbestblockhash()
    tip_height = node.getblockcount()
    block_time = node.getblock(tip_hash)["time"] + 1

    # getblocktemplate returns the correct BIP9-style nVersion for current height
    tmpl    = node.getblocktemplate({"rules": ["mweb", "segwit"]})
    version = tmpl["version"]

    block = create_block(
        int(tip_hash, 16),
        create_coinbase(tip_height + 1),
        block_time,
        version=version,
    )
    for tx in extra_txs:
        block.vtx.append(tx)
    # Required for SegWit-active blocks; omitting causes "unexpected-witness"
    add_witness_commitment(block)
    block.hashMerkleRoot = block.calc_merkle_root()
    block.solve()
    return block
```

**Fix C — `subtest_10_coinbase_exemption`: same version + witness fixes**

```python
tmpl = node.getblocktemplate({"rules": ["mweb", "segwit"]})

block = create_block(
    int(tip_hash, 16),
    create_coinbase(tip_height + 1),
    block_time,
    version=tmpl["version"],    # <-- added
)
add_witness_commitment(block)   # <-- added
block.hashMerkleRoot = block.calc_merkle_root()
block.solve()
```

---

## 7. Running Tests

```bash
cd ~/rincoin-sim

# Activate venv if not already active
source ~/rincoin-venv/bin/activate

# Run a single functional test
python3 test/functional/feature_rin3_enforcement.py

# Run via test_runner (file must be registered in test_runner.py first)
python3 test/functional/test_runner.py feature_rin3_enforcement.py
```

### Expected output (success)

```
=======================================================
  RIN3 nVersion enforcement -- consensus & mempool
  nRinHashForkHeight (regtest) = 840
  RIN_FORK_TX_VERSION = 0x52494e33 = 1380535859
=======================================================
...
  [PASS] legacy nVersion=2 at h=839 -> ACCEPTED, chain advanced to h=839
  [PASS] nVersion=2 at h=840 -> REJECTED as expected
  [PASS] nVersion=1 at h=840 -> REJECTED as expected
  [PASS] nVersion=3 at h=840 -> REJECTED as expected
  [PASS] mixed RIN3+legacy at h=840 -> REJECTED as expected
  [PASS] pure RIN3 at h=840 -> ACCEPTED, chain advanced to h=840
  getblockstats[840] | subsidy =    400000000 sat  (4.00 RIN)  expect 4.00 RIN
  [PASS] nVersion=2 at h=841 -> REJECTED as expected
  [PASS] mempool rejected nVersion=3 with 'version' reason (IsStandardTx)
  [PASS] Mempool Zombie DoS defense confirmed
  [PASS] Coinbase exemption confirmed: nVersion=0x1 accepted at h>=840
=======================================================
  ALL 10 SUBTESTS PASSED
  RIN3 consensus & mempool defense verified end-to-end
=======================================================
Tests successful
```

---

## 8. Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `ModuleNotFoundError: No module named 'litecoin_scrypt'` | messages.py not patched | Apply patch 6-1 |
| `cannot find -ldb_cxx-4.8` | `BDB_PREFIX` not set | `export BDB_PREFIX=~/rincoin-sim/db4` |
| `R_X86_64_PC32 relocation` (make error) | Missing `--with-pic` | Re-run configure with `--with-pic` |
| `bad-version(0x00000001)` | Block nVersion=1 rejected | Use `getblocktemplate` for version |
| `bad-version(0x00000004)` | Block nVersion=4 rejected | Use `getblocktemplate` for version |
| `unexpected-witness` | SegWit commitment missing | Call `add_witness_commitment(block)` |
| `mweb-missing` | MWEB data required but not built | Add `-vbparams=mweb:9999999999:9999999999` |
| `venv` creation fails | `python3.12-venv` not installed | `sudo apt install python3.12-venv` |
| `blake3` install fails | Rust not installed | Install Rust first (Step 1) |
| `Text file busy` during `strip` | rincoind is running | `pkill -9 rincoind` first |
| `git pull` blocked with `modified:` warnings | Local edits conflict with remote | `git restore <file>` to discard local changes |

### Re-build from scratch (preserve repo)

```bash
cd ~/rincoin-sim
make distclean
export BDB_PREFIX="$HOME/rincoin-sim/db4"
./configure \
    --without-miniupnpc \
    --without-gui \
    --disable-bench \
    --with-pic \
    BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" \
    BDB_CFLAGS="-I${BDB_PREFIX}/include"
make -j$(nproc) 2>&1 | tee build_$(date +%m%d).log
```

### Nuclear clean rebuild (delete & re-clone repo)

Use when the working tree is in an irrecoverable state (untracked litecoin-era files, broken caches, etc.). **All committed work must already be pushed to GitHub.**

Choose the appropriate repository:

```bash
cd ~
rm -rf rincoin-sim

# Current source (until upstream PR is merged into the Rin-coin org repo)
git clone https://github.com/Aevust/rincoin-sim.git

# Future canonical source (after PR merge into Rin-coin org)
# git clone https://github.com/Rin-coin/rincoin-sim.git

cd rincoin-sim
./autogen.sh
./contrib/install_db4.sh `pwd`
export BDB_PREFIX="$HOME/rincoin-sim/db4"
./configure \
    --without-miniupnpc \
    --without-gui \
    --disable-bench \
    --with-pic \
    BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" \
    BDB_CFLAGS="-I${BDB_PREFIX}/include"
make -j$(nproc)
```

---

## 9. Release Packaging

For distributing `rincoin-sim` to other testers/developers via GitHub Releases.

### 9-1. Stop the daemon

`strip` cannot modify a running binary (Linux's `Text file busy` protection).

```bash
pkill -9 rincoind
```

### 9-2. Strip binaries

Removes debug symbols, dramatically reducing file size (often 50%+).

```bash
strip src/rincoind src/rincoin-cli src/rincoin-tx src/rincoin-wallet
# If GUI was built:
# strip src/qt/rincoin-qt
```

### 9-3. Assemble the release directory

Standard package layout (v1.0.7 includes additional CH attack/RIN3 simulation scripts):

```
rincoin-sim-v1.0.7-linux-x86_64/
├── bin/
│   ├── rincoind
│   ├── rincoin-cli
│   ├── rincoin-tx
│   └── rincoin-wallet
├── scripts/
│   ├── sim-ch.sh
│   ├── sim-ch-attack.sh
│   ├── sim-ch-rin3.sh
│   └── sim-mweb.sh
└── README.md
```

```bash
VER="v1.0.7"
PKG="rincoin-sim-${VER}-linux-x86_64"

mkdir -p ${PKG}/bin ${PKG}/scripts

# Binaries
cp src/rincoind src/rincoin-cli src/rincoin-tx src/rincoin-wallet ${PKG}/bin/

# Simulation scripts (v1.0.7: 4 scripts)
cp scripts/sim-ch.sh \
   scripts/sim-ch-attack.sh \
   scripts/sim-ch-rin3.sh \
   scripts/sim-mweb.sh \
   ${PKG}/scripts/

# Documentation
cp README.md ${PKG}/
```

### 9-4. Create the tarball

```bash
tar -czvf ${PKG}.tar.gz ${PKG}
```

### Why ship all four binaries

| Binary | Why needed |
|--------|-----------|
| `rincoind` | Daemon — required for everything |
| `rincoin-cli` | RPC client — required to drive the daemon |
| `rincoin-tx` | Low-level raw tx tool — needed for MWEB / RIN3 debugging |
| `rincoin-wallet` | Offline wallet.dat repair / dump |

Shipping all four signals a complete Bitcoin/Litecoin-grade node, not a partial port.

---

## 10. Verification & GPG Signing

Bitcoin Core-level release security (supply chain attack defense).

### 10-1. Generate SHA256 checksums (Ubuntu)

```bash
# Main tarball checksum
sha256sum rincoin-sim-v1.0.7-linux-x86_64.tar.gz > SHA256SUMS.txt

# Optionally include per-binary checksums for transparency
# (run while the package directory still exists, before cleanup)
sha256sum ${PKG}/bin/rincoind \
          ${PKG}/bin/rincoin-cli \
          ${PKG}/bin/rincoin-tx \
          ${PKG}/bin/rincoin-wallet >> SHA256SUMS.txt

cat SHA256SUMS.txt
```

### 10-2. Transfer to the signing machine

Move the following two files to the host OS (Windows or wherever your GPG key lives):

1. `rincoin-sim-v1.0.7-linux-x86_64.tar.gz`
2. `SHA256SUMS.txt`

Transfer via VirtualBox shared folder, SCP, or WinSCP.

### 10-3. GPG clear-sign on the signing machine

Clear-sign keeps the SHA256 values human-readable while attaching a verifiable signature.

**Windows PowerShell:**
```powershell
gpg --clear-sign SHA256SUMS.txt
```

**Linux (if signing on the same machine):**
```bash
gpg --clear-sign SHA256SUMS.txt
```

Output: `SHA256SUMS.txt.asc` — contains both the readable hashes and a `-----BEGIN PGP SIGNATURE-----` block.

### 10-4. Why clear-sign

| Format | Pros |
|--------|------|
| `--clear-sign` (`.asc`) | Hashes visible to humans + verifiable signature in one file |
| `--detach-sign` (`.sig`) | Smaller signature file, but requires separate hash file |

Clear-sign is recommended for user-friendliness.

### 10-5. GitHub Releases asset structure

Upload exactly **3 files**:

| File | Role |
|------|------|
| `rincoin-sim-v1.0.7-linux-x86_64.tar.gz` | Binary package |
| `SHA256SUMS.txt` | Plain-text checksums |
| `SHA256SUMS.txt.asc` | GPG-signed checksums (clear-sign format) |

### 10-6. User-side verification flow

```bash
# 1. Download all three files

# 2. Verify the GPG signature on the checksums
gpg --verify SHA256SUMS.txt.asc
# Expected: "Good signature from <signer email>"

# 3. Verify the tarball matches the checksum
sha256sum -c SHA256SUMS.txt
# Expected: rincoin-sim-...tar.gz: OK
```

---

## Appendix A: RinHash Algorithm

Defined in `src/rinhash.cpp`. The Python equivalent in `messages.py`:

```
80-byte block header
    ↓  BLAKE3
32 bytes
    ↓  Argon2d  (t_cost=2, m_cost=64, lanes=1, salt="RinCoinSalt")
32 bytes
    ↓  SHA3-256
32 bytes  ←  PoW hash (replaces scrypt in Litecoin)
```

## Appendix B: MWEB Activation in Regtest

| Network | MWEB activation |
|---------|----------------|
| Mainnet | `NEVER_ACTIVE`|
| Testnet | `nStartHeight = 840` (height-based) |
| Regtest | `nStartTime = 1601450001` (time-based, already past → activates ~h=432) |

For tests that do not cover MWEB behaviour, disable with:

```
-vbparams=mweb:9999999999:9999999999
```

MWEB + RIN3 interaction is covered by `feature_rin3_mweb_exemption.py` (separate test).

## Appendix C: Differences vs Rincoin Core Release Build

| Aspect | rincoin-sim (this guide) | Rincoin Core release |
|--------|--------------------------|----------------------|
| Purpose | Functional testing, 1/1000 scale | Mainnet binary distribution |
| GUI | `--without-gui` | `--with-gui=qt5` |
| BDB | `BDB_LIBS / BDB_CFLAGS` (strict) | Same |
| Optimization | `Strip` recommended | `strip` mandatory |
| Signing | Optional | Mandatory (GPG clear-sign) |
| Distribution | Tarball + scripts/ | Tarball, multi-platform |
