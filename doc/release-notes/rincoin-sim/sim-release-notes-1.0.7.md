# Rincoin-Sim version 1.0.7 release notes

[![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.20363269-blue)](https://doi.org/10.5281/zenodo.20363269)

---

Rincoin-Sim version 1.0.7 is now available from:

[github.com/Aevust/rincoin-sim/releases/tag/v1.0.7](https://github.com/Aevust/rincoin-sim/releases/tag/v1.0.7)

This release tracks Rincoin Core v1.0.7. The `PATCH` component is `0`, indicating no sim-internal fixes beyond what is required to remain in sync with the corresponding Core release (RIP-0001 §Version Numbering).

Please report bugs using the issue tracker at GitHub:

[github.com/Aevust/rincoin-sim/issues](https://github.com/Aevust/rincoin-sim/issues)

---

## Versioning

`rincoin-sim` uses a four-component version scheme:

```
  v[GENERATION].[MAJOR].[MINOR].[PATCH]
```

The first three components track the Core release that the tool validates against. `PATCH` increments for sim-internal fixes that do not correspond to a Core release change.

| Component | Value | Meaning |
| --------- | ----- | ------- |
| GENERATION | 1 | Current PoR epoch (~400-year cycle) |
| MAJOR      | 0 | CH hard fork pending (Block 840,000); MAJOR = 1 at v1.1.0 |
| MINOR      | 7 | Tracks Core v1.0.7 |
| PATCH      | 0 | No sim-internal divergence from Core |

`rincoin-sim v1.0.6.1` represented a sim-internal fix against Core v1.0.6. v1.0.7 is the pre-release validation target for the CH hard fork; v1.1.0 will be the definitive release, timed ~2 months before Block 840,000.

---

## How to upgrade

Shut down any running `rincoind` test instances. Wait until all simulation processes have completely terminated, then rebuild from the v1.0.7 source tree:

```
make distclean
./autogen.sh
./configure \
    --without-miniupnpc \
    --without-gui \
    --disable-bench \
    --with-pic \
    BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" \
    BDB_CFLAGS="-I${BDB_PREFIX}/include"

make -j$(nproc) 2>&1 | tee build_$(date +%m%d).log

# Run unit tests
make check 2>&1 | tee test_$(date +%m%d).log
```

| Flag | Reason |
| ---- | ------ |
| `--without-miniupnpc` | Not needed for sim |
| `--without-gui` | rincoin-sim is CLI-only |
| `--disable-bench` | Speeds up build |
| `--with-pic` | Required to link static libs (`libargon2.a`, `libbitcoin_util.a`) into shared `libbitcoinconsensus.la`; omitting causes `R_X86_64_PC32 relocation` error |

Refer to `doc/build-unix-rincoin-sim.md` for full build instructions, including dependency installation on Linux.

---

## Compatibility

Rincoin-Sim v1.0.7 is supported and tested on:

- Ubuntu 24.04 (x86_64)

The release builds against the same toolchain matrix as Rincoin Core v1.0.7.

---

## Notable changes

All Core v1.0.7 changes are inherited and verified in this sim release. See `doc/release-notes/release-notes-1.0.7.md` for the full Core changelog. The sim-relevant summary follows.

### Mainnet Taproot sealed as NEVER_ACTIVE (consensus / chainparams)

Mainnet Taproot deployment parameters inherited from Litecoin (`nStartHeight=2161152`, `nTimeoutHeight=2370816`) were not aligned to Rincoin's `nMinerConfirmationWindow=7920`, causing the `versionbits_sanity` invariant to fail in sim test runs:

```
2161152 % 7920 = 6912   (must be 0)
2370816 % 7920 = 2736   (must be 0)
```

Taproot is now sealed as `NEVER_ACTIVE` on mainnet, mirroring the MWEB deferral pattern (RIP-0004). Testnet and Regtest remain `ALWAYS_ACTIVE` and are exercised by sim BVA suites unchanged.

### BIP8 computeblockversion test re-enabled (test)

The `versionbits_computeblockversion` test was temporarily disabled in v1.0.6.x (commit `d377e97`) when the mainnet Taproot period-alignment failure prevented the test's internal sanity check from passing.

With mainnet Taproot now sealed, the BIP8 test path is exercised only by `TESTNET/DEPLOYMENT_MWEB` (`nStartHeight=840`, `nTimeoutHeight=1050`, `window=210`, all period-aligned at the 1/1000 simulation scale). The test is re-enabled and passes cleanly under `make check`.

The earlier commit message attributed the failure to a "per-block vs period-boundary semantic mismatch" in the BIP8 state machine. That diagnosis was incorrect; the actual cause was the same period-alignment invariant that also fired in `versionbits_sanity` for the same deployment. The BIP8 state machine implementation in both Rincoin and Litecoin upstream is functionally correct under period-aligned parameters.

### RIP-0001 version mapping documented (build)

Inline comments added to `configure.ac` and `src/clientversion.h` documenting the correspondence between Bitcoin-origin macro names and Rincoin's RIP-0001 versioning scheme:

```
  CLIENT_VERSION_MAJOR    = GENERATION (~400-year PoR epoch)
  CLIENT_VERSION_MINOR    = MAJOR      (protocol upgrade)
  CLIENT_VERSION_REVISION = MINOR      (maintenance / bugfix)
  CLIENT_VERSION_BUILD    = PATCH      (sim-internal; tracks
                                        4-component version
                                        for rincoin-sim)
```

For `rincoin-sim`, the `CLIENT_VERSION_BUILD` macro is the authoritative source of the `PATCH` component (currently `0`).

### RIN3 nVersion enforcement validated (test / scripts)

The Block 840,000 RIN3 transaction-version marker (`nVersion = 0x52494e33`) is validated end-to-end in this release. `sim-ch-rin3.sh` exercises wallet-side nVersion selection across the fork boundary (tip 838 → legacy, tip ≥ 839 → RIN3); `feature_rin3_enforcement.py` exercises RIN3 enforcement across 10 subtests: consensus-level block rejection of non-RIN3 nVersion (1 / 2 / 3 and mixed blocks) at height ≥ fork with reason `bad-tx-rinhash-version`, the pre-fork accept, and the positive RIN3 control, mempool-level rejection (`IsStandardTx` for nVersion=3 and the `PreChecks` Zombie-DoS defense for legacy nVersion at h ≥ fork), and the coinbase nVersion exemption (HogEx / MWEBOnly exemptions require MWEB activation and are deferred to `feature_rin3_mweb_exemption.py`); `sim-ch-attack.sh` proves subsidy determinism under reorgs up to full CH-history erasure (5,461 blocks).

---

## Verification

### Standard test suite

```
$ make check
...
PASS: tests
PASS: exhaustive_tests
=========================
# TOTAL: 2
# PASS:  2
# FAIL:  0
=========================
```

The full `versionbits_tests` suite, including `versionbits_computeblockversion`, passes without any `--run_test` exclusions.

### Boundary Value Analysis (BVA, 1/1000 scale)

Inherited from v1.0.6.1 and re-verified under v1.0.7:

| Boundary | Block heights | Result |
| -------- | ------------- | ------ |
| Pre-CH dilation         | 839 / 840     | PASS |
| CH phase 4 → 5 boundary | 2099 / 2100   | PASS |
| CH phase 5 → 6 boundary | 4199 / 4200   | PASS |
| CH phase 6 → Terminal   | 6299 / 6300   | PASS |

### MWEB lifecycle (1/1000 scale, regtest)

| Operation | Amount | Result |
| --------- | ------ | ------ |
| MWEB activation | ~Block 432 (time-based) | PASS |
| Peg-in          | 10 RIN    | PASS |
| Peg-out         | 5 RIN     | PASS |
| Reorg           | Heights 451 / 452 | PASS |

### Automation scripts

Carried over from v1.0.6.1 (unchanged):

- `sim-ch.sh`   — Customized Halving lifecycle harness
- `sim-mweb.sh` — MWEB peg-in / peg-out / reorg harness

New in v1.0.7:

- `sim-ch-rin3.sh`   — four-section suite: phase advance, BVA, RIN3 wallet nVersion enforcement, and four reorg-attack scenarios (max depth 2,101 blocks)
- `sim-ch-attack.sh` — Deep-Reorg Attack Proof (Omega Edition): five escalating reorg scenarios up to 5,461-block full CH-history erasure
- `test/functional/feature_rin3_enforcement.py` — consensus-level rejection of legacy-nVersion blocks at height ≥ fork

---

## Known issues

None at the time of release.

The MWEB BDB → SQLite migration remains pending upstream Litecoin work. MWEB remains sealed as `NEVER_ACTIVE` on mainnet (RIP-0004); testnet MWEB activation at Block 840 under the 1/1000-scale design is unaffected and is the primary BIP8 exercise path in the sim test suite.

---

## Binaries

| Platform | SHA256 |
| -------- | ------ |
| Linux (x86_64) | `cc0c708e38779333a54424fcfbf5c1900a8ea79fb3ad32288918eacf78a17eec` |

SHA256 verification:
```bash
sha256sum -c SHA256SUMS.txt
```

Signed checksum file: `SHA256SUMS.txt.asc`
```bash
gpg --verify SHA256SUMS.txt.asc
```

GPG key fingerprint: `ED20 B635 4EE4 526D 01F8 3B53 8B6E 3BF4 5C71 4ECA`

`rincoin-sim` does not currently ship a Windows binary; build from source on Windows is supported via MSYS2, but not part of the verified release matrix.

---

## Relation to Rincoin Core v1.0.7

Rincoin-Sim v1.0.7 and Rincoin Core v1.0.7 share the following source-level changes:

- `src/chainparams.cpp`           (Taproot NEVER_ACTIVE on mainnet)
- `src/test/versionbits_tests.cpp` (BIP8 test re-enabled)
- `configure.ac`                  (version bump + RIP-0001 comments)
- `src/clientversion.h`           (RIP-0001 mapping comments)

Sim-specific consensus additions in this release: none — the sim shares Core's consensus code verbatim (PATCH = 0). Sim-only test harnesses added: `scripts/sim-ch-rin3.sh`, `scripts/sim-ch-attack.sh`, and `test/functional/feature_rin3_enforcement.py`. The `PATCH` component will increment to `1` if any sim-internal consensus fix lands before Core v1.0.8.

---

## Credits

Thanks to everyone who contributed to this release:

- @Aevust  (Core Authority Lead / Core Research Lead /
           Principal Architect)
- @ysmreg  (Founder / Core Technical Lead)

As well as everyone who helped with translations and reviews on the Rincoin community channels.
