# Rincoin-Sim version 1.1.0 release notes

[![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.21805345-blue)](https://doi.org/10.5281/zenodo.21805345)

---

Rincoin-Sim version 1.1.0 is now available from:

[github.com/Aevust/rincoin-sim/releases/tag/v1.1.0](https://github.com/Aevust/rincoin-sim/releases/tag/v1.1.0)

This is the release v1.0.7 anticipated: the `MAJOR` component moves to `1` because RIN3 is a protocol upgrade. It is the validation target for Rincoin Core v1.1.0, which activates RIN3 at Block 840,000; Core commits cite the Sim commit hashes as provenance.

Please report bugs using the issue tracker at GitHub:

[github.com/Aevust/rincoin-sim/issues](https://github.com/Aevust/rincoin-sim/issues)

---

## Versioning

`rincoin-sim` uses a four-component version scheme:

```
  v[GENERATION].[MAJOR].[MINOR].[PATCH]
```

| Component | Value | Meaning |
| --------- | ----- | ------- |
| GENERATION | 1 | Current PoR epoch (~400-year cycle) |
| MAJOR      | 1 | RIN3 protocol upgrade; activates at Block 840,000 |
| MINOR      | 0 | First release on the 1.1 line |
| PATCH      | 0 | No sim-internal divergence from Core |

v1.0.7 recorded that `MAJOR` would become `1` at v1.1.0. `configure.ac` carries that change (`_CLIENT_VERSION_MINOR` 0 → 1, `_CLIENT_VERSION_REVISION` 7 → 0), which is what `contrib/release` reads when it names the artifacts.

---

## How to upgrade

Shut down any running `rincoind` test instances. Wait until all simulation processes have completely terminated, then rebuild from the v1.1.0 source tree:

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

`--with-pic` remains mandatory: without it, linking the static libraries into `libbitcoinconsensus.la` fails with `R_X86_64_PC32 relocation`.

`contrib/release` automates the packaged build (`make release` runs the `depends` build, snapshots the source from the tag, and signs the manifest). Refer to `doc/build-unix-rincoin-sim.md` for full build instructions.

After upgrading, confirm the version reports as expected:

```
$ src/rincoind -version | head -1
Rincoin Core version v1.1.0.0-<commit>
```

---

## Compatibility

Rincoin-Sim v1.1.0 is supported and tested on:

- Ubuntu 24.04 (x86_64), g++ 13.3.0

---

## Notable changes

### RIN3 service signaling (net)

The node advertises `NODE_RIN3` (service bit 25, RIP-0009) and `PROTOCOL_VERSION` 70018. RIN3 support is signalled as a capability rather than enforced by a version floor: `MIN_PEER_PROTO_VERSION` was not raised for it and stays at 31800, far below the new protocol version, so peers that do not signal RIN3 are still connected and served. Outbound preference is expressed through `GetDesirableServiceFlags` instead. This is what preserves soft-fork topology across the activation.

The service-flag comment now reserves bits 26-31 for experiments, following the same narrowing Bitcoin (24-31) and Litecoin (25-31) applied when they allocated bits inside the band.

The functional framework's expected service mask was updated to match, so `p2p_node_network_limited.py` does not fail on the new bit. That test still fails later for a pre-existing reason, tracked for 1.1.x.

### RIN3 nVersion enforcement (consensus / mempool)

Enforcement is exercised end to end at the regtest fork height 840 (1/1000 scale). The subsidy moves from 6.25 RIN at height 839 to 4.00 RIN at the fork block. Transactions that do not carry `nVersion = 0x52494e33` are rejected with `bad-tx-rinhash-version` in every block-level pattern tested — nVersion 1, 2 and 3, a block mixing RIN3 with legacy, and a block after the fork height — while a pure RIN3 block is accepted as the positive control.

Two paths reject earlier than the block level, and neither uses that reason string: `IsStandardTx` refuses nVersion 3 at the mempool, and `MemPoolAccept::PreChecks` refuses legacy nVersion at or above the fork height, which is what keeps `CreateNewBlock` from being poisoned by a high-fee legacy transaction. Coinbase transactions stay exempt.

### RIP-0011 Taproot wallet guard (wallet)

While the Taproot deployment is sealed, `CWallet::CreateTransaction` refuses to create outputs paying to witness v1 or later. On mainnet Taproot is NEVER_ACTIVE, so without the guard such outputs are anyone-can-spend at the consensus level, and the hazard is reachable from `sendtoaddress` rather than only from the raw transaction APIs.

The guard reads the deployment parameter directly instead of querying activation state, because `VersionBitsState` requires `cs_main` while `cs_wallet` is already held. MWEB recipients are exempted by an `IsMWEB()` early-continue: a StealthAddress carries no script, and asking for one would abort the node rather than fail an RPC. The refusal surfaces as RPC error -6 with the untranslated message text, so matching it is locale-independent.

### Functional test framework repaired (test)

Each of these was previously preventing coverage rather than merely producing noise:

- `MAGIC_BYTES` in the test framework now match `chainparams.cpp` on all three networks, so the p2p tests can connect at all.
- The Litecoin-to-Rincoin rename is carried through the paths the suite exercises: address constants re-encoded for the Rincoin HRPs and verified against the node, and fee-rate strings moved from LTC to RIN units. Older test vectors still carrying Litecoin values are tracked for 1.1.x.
- The cached datadir keeps `indexes/`, so tests relying on the 199-block cache regenerate it instead of crashing in setup.
- `test_runner.py` accepts the `rin` script prefix, which it did not; the suite would not start.
- `feature_loadblock.py` was given the regtest netmagic.

New tests:

- `feature_taproot_wallet_guard.py` — both guard branches from one test: acceptance while the deployment is live, refusal once it is sealed, and a node-survival check for MWEB recipients. All three subtests either complete or raise, so the test cannot pass vacuously.
- `feature_rin3_enforcement.py` — the subsidy schedule across the fork height, five block-level rejection patterns, both mempool paths, and the coinbase exemption.
- `p2p_rin3_services.py` — the service bit and protocol version over RPC and on the wire, and continued service to peers that do not signal RIN3.

### Build and documentation

`build_msvc/bitcoin_config.h` had `PACKAGE_URL` pointing at a former domain; it now matches the URL `configure.ac` passes to `AC_INIT`. That file is a hand-maintained mirror and is not part of any shipping path. Trailing whitespace was stripped from two source files, and the copyright line in one functional test was normalised to `The Rincoin Core developers`.

---

## Verification

Build and test evidence for the exact tree this release was built from is archived at <https://doi.org/10.5281/zenodo.21805345>: the build log, the full suite run, the pre-release baseline it is compared against, four individual test runs, ten standalone runs of `feature_abortnode.py`, the commit signatures, and SHA-256 digests of the test files as committed. The archive carries a digest list signed with the key that signed every commit in this release. Every log produced for this release is headed by the commit it was produced under, and the build log records a clean working tree. The baseline predates that convention, and it also predates the exclusion below; both differences are set out in the archive's own manifest.

### Functional suite

```
python3 -u test/functional/test_runner.py -j 3 --exclude feature_loadblock.py

  112 passed, 55 failed, 42 skipped        (runtime 1168 s)
```

Fifty-four of those failures were already failing in the pre-release baseline and fall into classes tracked for 1.1.x: block-identity assumptions (SHA256d vs RinHash) in p2p helpers, Litecoin address vectors and the `tmweb` MWEB prefix in older tests, and deployment-dependent tests. None of them are caused by the changes in this release.

The remaining one is a status change from that baseline rather than a regression. `feature_abortnode.py` mines three blocks, deletes the undo file covering them, and expects the node to abort later, when a reorg cannot disconnect them. In this tree the block filter index is on by default — a Litecoin default inherited here, unchanged by this release — and it reads that same undo data on a background thread. When the deletion lands inside the few milliseconds the index still needs to catch up with those three blocks, the node aborts from the scheduler thread first, before the test has connected the nodes at all: 4 of 15 standalone runs on an idle machine, and once during the suite run. The abort is correct either way — the same missing undo data, reached by a different reader — and only the order varies. Nothing in this release touches the node's block storage, indexing, shutdown, or the RPC server, and the same test passed under the same parallelism in the baseline run.

Passing jobs are compared as sets rather than counts, so the one status change is named rather than absorbed into a total.

`feature_loadblock.py` is excluded because `contrib/linearize` identifies blocks by SHA256d, which never matches on a RinHash chain; the scan reaches the end of the preallocated block file and stops advancing, so the test hangs rather than fails. The test-side netmagic was corrected in this release; the tool-side problem is tracked separately.

### Individual runs

| Test | Result |
| ---- | ------ |
| `feature_taproot_wallet_guard.py` | 3 subtests PASS |
| `feature_rin3_enforcement.py`     | 10 subtests PASS |
| `p2p_rin3_services.py`            | 3 subtests PASS |
| `rpc_fundrawtransaction.py`       | PASS (no guard side effect on ordinary funding) |

Observed values: `localservices = 0x3800449` with `RIN3` among the names, `protocolversion = 70018` over both RPC and the wire, `getblockstats` subsidy `625000000` sat at height 839 and `400000000` sat at height 840.

---

## Known issues

- MWEB remains NEVER_ACTIVE on Rincoin mainnet (RIP-0004 / RIP-0011). The guard's MWEB path is exercised on regtest, where MWEB addresses are available to the wallet.
- The guard also refuses witness versions above 1, but that path is not covered by a dedicated test case; planned for 1.1.1.
- `src/tools/genesis_miner.cpp` is not referenced by any build target; its disposition is being handled separately from this release.

---

## Relation to Rincoin Core

Sim leads on this line. The consensus and wallet changes above are implemented and exercised here first, then ported to Core with the Sim commit hash recorded in the Core commit, and Core v1.1.0 follows. Line numbers cited in commit messages are re-measured on the Core tree during the port, since the two trees differ in length.

Sim-only in this release: the three functional tests listed under Notable changes, and the framework repairs they depend on.

---

## Credits

Thanks to everyone who contributed to this release:

- @Aevust
