Rincoin-Sim
===========

Rincoin-Sim is a 1/1000-scale functional test environment for Rincoin Core protocol development and consensus verification.

**This is not a production node.** All block heights, block rewards, and activation thresholds are scaled to 1/1000 of mainnet values.

| Parameter | Mainnet | Rincoin-Sim (regtest) |
|-----------|---------|----------------------|
| CH hard fork (Customized Halving) | Block 840,000 | Block 840 |
| RIN3 nVersion enforcement | Block 840,000 | Block 840 |
| Block reward at fork | 6.25 → 4.00 RIN | 6.25 → 4.00 RIN |
| MWEB (mainnet) | `NEVER_ACTIVE` | Activates h=432 (BIP9, time-based) |
| MWEB (in RIN3 tests) | — | Disabled via `-vbparams` |

Building
---------------------
The Rincoin-Sim build environment requires Ubuntu 24.04 LTS and BDB 4.8 (built from source via `contrib/install_db4.sh`). A Python virtual environment with `blake3` and `argon2-cffi` is required for the functional test framework.

- [Rincoin-Sim Build & Test Guide](build-unix-rincoin-sim.md)
- [Dependencies](dependencies.md)
- [Unix Build Notes](build-unix.md)

Functional Tests
---------------------
Functional tests live under `test/functional/`. Run a single test directly without registering it in `test_runner.py`:

```bash
source ~/rincoin-venv/bin/activate
python3 test/functional/<test_name>.py
```

Shell simulation scripts live under `scripts/` and can be run from the source directory or from the release tarball directory:

```bash
./scripts/sim-ch.sh
./scripts/sim-ch-rin3.sh
./scripts/sim-ch-attack.sh
./scripts/sim-mweb.sh
```

### Test framework patches

Two files in `test/functional/test_framework/` were modified to replace Litecoin-specific code with Rincoin equivalents:

| File | Change |
|------|--------|
| `messages.py` | `litecoin_scrypt` → pure-Python `rinhash()` (BLAKE3 → Argon2d → SHA3-256) |
| `blocktools.py` | Default `nVersion` 1 → 4 (BIP34/65/66-compliant) |

### Implemented tests

| Test | Coverage | Est. runtime | Status |
|------|----------|--------------|--------|
| `feature_rin3_enforcement.py` | RIN3 nVersion consensus & mempool enforcement (10 subtests) | ~5 min | ✅ ALL 10 SUBTESTS PASSED |
| `sim-ch.sh` | CH full phase advance (h=1→6300) + BVA boundary checks | ~2 min | ✅ |
| `sim-ch-rin3.sh` | CH × RIN3 — BVA + wallet version tests + 4 reorg attack scenarios | ~5 min | ✅ |
| `sim-ch-attack.sh` | CH attack resilience — Omega Edition (5 scenarios, max 5461-block reorg) | ~15–20 min | ✅ |
| `sim-mweb.sh` | MWEB peg-in / peg-out / reorg lifecycle | ~3 min | ✅ |
| `feature_rin3_mweb_exemption.py` | RIN3 + MWEB exemption (HogEx / MWEBOnly) | — | Planned |

#### Script details

**`sim-ch.sh`** — CH full phase advance and BVA. Mines all phases (h=1→6300), then verifies `getblockstats` subsidy at all 8 phase boundaries (839/840, 2099/2100, 4199/4200, 6299/6300). Fastest routine check with no reorg scenarios.

**`sim-ch-rin3.sh`** — CH × RIN3 integration test (v4). Extends BVA with three wallet nVersion scenarios (tip >= 839 → RIN3 version, tip < 839 → legacy) and four escalating reorg attacks to confirm deterministic CH restoration (max 2101-block reorg).

**`sim-ch-attack.sh`** — Omega Edition. Extends the attack suite with scenario [D-2] Omega: a 5461-block reorg that erases the entire CH history (blocks 840–6300), then remines through every phase boundary. External-facing proof that `GetBlockSubsidy` is a pure function of height — correct subsidy is always restored regardless of reorg depth.

```
[A] Minimal        840 ->  839 ->  840      1 block
[B] Super         2100 ->  839 -> 2100   1261 blocks  (Phase 4 erasure)
[C] Cross-Phase   4200 -> 2099 -> 4200   2101 blocks  (Phase 5 erasure)
[D-1] Terminal    6300 -> 4199 -> 6300   2101 blocks  (Phase 6 erasure)
[D-2] Omega       6300 ->  839 -> 6300   5461 blocks  (full CH erasure)
```
**`sim-mweb.sh`** — MWEB lifecycle verification. Covers peg-in (10 RIN), peg-out (5 RIN), and reorg at h=451/452. Set `KEEP_ALIVE=1` to keep rincoind running after the script ends for manual post-test inspection:

    KEEP_ALIVE=1 ./scripts/sim-mweb.sh

Development
---------------------

The [Rincoin Core repository](https://github.com/Rin-coin/rincoin) contains the reference implementation. Rincoin-Sim tracks the same source tree with regtest-specific tooling layered on top.

- [Developer Notes](developer-notes.md)
- [Release Notes](release-notes/README.md)
- [JSON-RPC Interface](JSON-RPC-interface.md)
- [BIPs](bips.md)
- [RIPs (Rincoin Improvement Proposals)](https://github.com/Rin-coin/rips)

### Test Evidence

All functional test screenshots and execution logs are permanently archived on Zenodo with a persistent DOI. Binary files are never committed to this repository.

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20363269.svg)](https://doi.org/10.5281/zenodo.20363269)

- [Test Evidence Archive](release-notes/rincoin-sim/EVIDENCE.md)

### Resources

- [Rincoin Whitepaper](https://doi.org/10.5281/zenodo.17141922)
- [Rincoin Core Repository](https://github.com/Rin-coin/rincoin)
- [RIPs Repository](https://rips.rincoin.org)
- [GitHub Issues](https://github.com/Aevust/rincoin-sim/issues)
- [Rincoin Discord](https://discord.gg/H4Du5YuqFa)

Miscellaneous
---------------------
- [Assets Attribution](assets-attribution.md)
- [Files](files.md)
- [Reduce Memory](reduce-memory.md)
- [Reduce Traffic](reduce-traffic.md)
- [Tor Support](tor.md)
- [ZMQ](zmq.md)

License
---------------------
Distributed under the [MIT software license](/COPYING).
