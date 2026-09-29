# Rincoin-Sim version 1.1.0.2 release notes

Rincoin-Sim is a 1/1000-scale functional-test build of Rincoin Core.
It is not a Core release and is not for mainnet use.

Release page: https://github.com/Aevust/rincoin-sim/releases/tag/v1.1.0.2

This is a patch release on v1.1.0.1. It carries the three branches
merged since that tag, nineteen commits in all, plus the version bump
and these notes: supply accounting (Aevust/rincoin-sim#3, merged as
1fa01d3418), the comment references (Aevust/rincoin-sim#4,
927497cdd5) and the RIN3 version carried through FundTransaction()
(Aevust/rincoin-sim#5, 7a50a4171e). None of them changes
consensus: GetBlockSubsidy() is untouched, the RIN3 enforcement and
the P2P code are unchanged, and emission is identical at every height.
What changes is the version a transaction gets when the wallet funds
it for a caller, the accounting (not the enforcement) of the
168,000,000 RIN supply cap, the way comments in this tree point at
other code, and the tests and the measurement script that come with
those.

---

## Versioning

The version scheme is GENERATION.MAJOR.MINOR.PATCH, defined in
configure.ac.

| Field | Value | Meaning |
| --- | --- | --- |
| GENERATION | 1 | PoR epoch (~400 years) |
| MAJOR | 1 | Protocol upgrade line |
| MINOR | 0 | Maintenance line |
| PATCH | 2 | Sim-internal fixes. Core keeps this field at 0 |

The version string reads:

    Rincoin-Sim version v1.1.0.2            (built on the tag)
    Rincoin-Sim version v1.1.0.2-<commit>   (built off the tag)

The field is defined for simulator-internal fixes, which is what
v1.1.0.1 used it for. This release increments it for a simulator
release most of whose content is written to be ported. That content
reaches Core under Core's own version numbers, so no Core version
carries a PATCH value, and the meaning of the field is unchanged.

---

## How to upgrade

Shut down any running node, replace the binaries, restart with
-regtest. This tree runs regtest only; there is no chain data
migration to consider. Release archives are named

    rincoin-sim-1.1.0.2.tar.gz                     (source)
    rincoin-sim-1.1.0.2-x86_64-linux-gnu.tar.gz    (Linux binaries)

For native builds from source, --with-pic remains required, as in
v1.1.0.

---

## Compatibility

Built and tested on Ubuntu 24.04 (g++ 13.3.0, x86_64). Other
platforms are untested.

---

## Notable changes

### Funded transactions carry the RIN3 version (wallet)

On v1.1.0 and v1.1.0.1, as on Rincoin Core v1.1.0-rc1, which carry
the same CWallet::FundTransaction(), createrawtransaction followed by
fundrawtransaction, and walletcreatefundedpsbt, produced a transaction
with nVersion 2 after the fork height, and from block 840,000 such a
transaction is rejected with bad-tx-rinhash-version. Only transactions
the wallet built itself, as sendtoaddress and sendmany do, carried the
RIN3 marker. The send RPC funds through the same function and was
affected less visibly: on the published v1.1.0-rc1 binaries it returned
a txid and "complete": true for a transaction with nVersion 2 that the
node did not accept into its mempool (measured 2026-09-25).
The defect was found on Rincoin Core v1.1.0-rc1 on 2026-09-18 and was
not listed as a known issue of either earlier Sim release. It was
measured on the published v1.1.0.1 binaries on 2026-09-27: the
boundary script of this release, run against them, failed its three
raw-transaction checks and passed the other twenty-one.

CWallet::FundTransaction() copied the output amounts and the inputs of
the transaction CreateTransaction() built, but not its version, so the
caller's default of 2 survived. The function was inherited unchanged
from Bitcoin Core v0.21.2 through Litecoin. It now copies the version as
well, when the caller's transaction has CTransaction::CURRENT_VERSION,
the value rawtransaction_util.cpp gives a transaction it constructs.
Measured on this tree, fundrawtransaction, walletcreatefundedpsbt and
send all switch to the marker at tip 839, where the wallet's own
transactions switch.

Three points about the condition. Any other version the caller set is
kept, so the workaround published on the Rincoin Core v1.1.0-rc1
release page (https://github.com/Rin-coin/rincoin/releases/tag/v1.1.0-rc1),
setting the version right after createrawtransaction and before
funding, keeps working. The fork height is not consulted in
FundTransaction(): wallet/txassembler.cpp, which switches once the
wallet's last processed block is at nRinHashForkHeight - 1 or above,
stays the only place in the wallet that decides when the version
switches. And a caller that sets 2 itself cannot be told apart from
one that left the default, so it gets the wallet's version; a caller
that wants a legacy-version transaction after the fork height sets the
version after funding and before signing, and this node refuses the
result at mempool entry.

### A legacy transaction across the fork height (wallet, mempool)

A new two-node test follows two legacy-version transactions that were
broadcast before the fork height and did not confirm, one that
signals BIP 125 and one that does not. What it measured:

- A mempool that accepted such a transaction before the fork height
  keeps it. Block assembly leaves it out from the fork height on, and
  nothing in the fork rule removes it from a mempool.
- A replacement is refused. Bitcoin Core v0.21.2 honours BIP 125
  signalling without an option; Litecoin gates that check on
  -mempoolreplacement, off by default, and this tree carries the same
  gate and default. A conflicting transaction is refused with
  txn-mempool-conflict whether or not the one it conflicts with
  signalled. bumpfee returns the txid of a replacement that carries
  the marker, and the node's own mempool refuses it.
- A restart drops the legacy transaction: LoadMempool() offers the saved
  transactions to the mempool again, skipping any that have expired, and
  from the fork height the legacy version is refused there. After the
  restart the wallet puts the bumpfee replacement back into the mempool
  on its own, and the transaction that did not signal can be abandoned
  and re-created from its own inputs through fundrawtransaction, with
  the marker.
- A node that still holds the legacy transactions refuses the
  re-creations, one txn-mempool-conflict refusal per transaction.
  After it too restarts, it accepts them and mines them, and the
  wallet shows the originals as conflicted.

Expiry (-mempoolexpiry, 336 hours by default), eviction and a
conflicting transaction in a connected block would also remove a
legacy transaction from a mempool. Those were not measured.
The guidance for operators that follows from this was added to the
Rincoin Core v1.1.0-rc1 release page on 2026-09-25 and belongs in the
release notes of the next Core candidate, not here.

### Supply accounting for the 168,000,000 RIN cap, Stage A (validation)

Whitepaper v1.6.4 Section 3, Scenario II defines the maximum total
supply, 168,000,000 RIN, the cumulative supply at t_fix, 31,027,500
RIN, and the year mining ends, t_trans, about 446.3232. The schedule
integral existed only in the paper; it is now expressed in code as
GetTotalSubsidy(), a closed form over the Customized Halving phase
boundaries of RIP-0002, clamped at a cap derived as
SUPPLY_CAP_PER_INTERVAL (800 RIN) times the halving interval:
168,000,000 RIN at the mainnet interval of 210,000 and 168,000 RIN at
this tree's interval of 210. CMainParams asserts the mainnet
derivation equals MAX_MONEY, so the constant cannot drift from the
sanity bound in amount.h.

Unit tests pin GetTotalSubsidy() against a brute-force sum of
GetBlockSubsidy(): S_fix at height 6,300,000, and the cap reached
exactly at height 234,587,500 and held above it. That height is
446.3232 years at the 60-second target spacing, matching t_trans.
The cap height is 13405 * interval / 12, an integer only when 12
divides the interval, so scaled networks reach the cap mid-block
with a 0.3 RIN residual that mainnet never sees; the regtest sweep
covers that boundary.

This is accounting, not enforcement. GetBlockSubsidy() is untouched
and no consensus rule reads the new constant. Enforcing the cap in
GetBlockSubsidy(), the subsidy going to zero at height 234,587,500,
is Stage B and will be proposed as a new RIP before any implementation.

### Comments cite identifiers, not line numbers (docs)

Every file:line cross-reference that Rincoin had written into this
tree is removed: from the RIP-0011 Taproot wallet guard in
src/wallet/wallet.cpp, its functional test, and the netmagic table in
the P2P test framework. Where a pointer is still useful the function
or class is named instead; where the sentence already carried the
identifier, the reference is dropped. Comments and docstrings only.

The change was motivated by observation. Of twenty distinct references
read before removal, eight had gone stale, all of them into
src/chainparams.cpp, because later commits added twenty-two lines to
that file above them. They went false in place, with no diff, no build
failure and no lint warning to say so. The values they annotated were
still correct; only the citations had rotted. The thirty occurrences
of the pattern that remain in the tree are verbatim sanitizer, fuzzer
and compiler output under src/test/fuzz, in doc/fuzzing.md and in
src/crypto/blake3/README.md, where the line number is part of a quoted
diagnostic.

### Tests and measurement (test)

- wallet_rin3_fund_version.py, new: seven subtests on the version the
  wallet puts on transactions it funds for a caller, on one node at
  tips 838, 839 and 840, including a PSBT taken through processing and
  finalizing. Registered in test_runner.py. The framework skips its
  --descriptors run on this tree, so that variant is not registered.
- wallet_rin3_boundary_rescue.py, new: the two-node scenario above,
  nine subtests. Registered in test_runner.py.
- validation_tests gains total_subsidy_sweep_test and
  supply_cap_boundary_test, four cases in all.
- scripts/sim-rin3-boundary.sh, new: a two-node measurement of the
  boundary behaviour RIP-0009 specifies, at the regtest fork height
  840. Without EXPECT_FUND_MARKER it records what the raw-transaction
  RPCs produce; with EXPECT_FUND_MARKER=1 it checks them. The same
  script, unchanged between the two runs, recorded the defect on the
  tree before the wallet change (PASS 21 / FAIL 3) and the acceptance
  after it (PASS 24 / FAIL 0). Its labels for the marker check were
  reworded afterwards; the checks did not change.

### Corrections in this tree's own history

Four of the eleven commits in the wallet branch correct what earlier
commits of that branch put in files: statements broader than the code
or the measurement supported, and one log check that did not tie the
refusal reason to each transaction. Where the message of an earlier
commit made the same statement, the correcting commit names it; no
pushed commit of that branch was rewritten. In the comment-reference
branch, by contrast, the first commit was reworded before its pull
request was opened, by a force-push that its merge message records,
with the superseded commit c1f3a8ec9 left reachable by hash.

---

## Verification

Verified at commit 7d0731643, the parent of this tag's target; the tag
adds only these release notes on top of it, and touches no code.
On a clean tree with no local modifications, 2026-09-27:

- `rincoind -version` reports `Rincoin-Sim version v1.1.0.2-7d0731643`
  with no -dirty suffix. rincoind sha256
  206a939f91b4942a4bbd0babb61e20712798ab6638ccd772e19274a3f5f8948c,
  BuildID c39fc4b0ea71720b1c01b56ad93291aa5f629134; rincoin-cli sha256
  b71bbb5386a7a67c1535446e65e3d6f51f25903b90882aae1769a01d0aa7e2aa,
  BuildID 794f58c7a31d32967cd404b8bbb9980f9079637b. These are the
  digests of the native build the checks below ran on; the binaries in
  the release archive are built separately by contrib/release and are
  covered by the signed SHA256SUMS on the release page.
- test_rincoin, run directly: 500 test cases, no errors. Log sha256
  94c007035e3508d976ad1c3279d08eafc81a52a56f61c497a6de3771c97117f8.
  make check was not run at this commit. The build used here includes
  the GUI, and at 3a863e58a3 make check stopped at test_rincoin-qt,
  whose RPCNestedTests expects the genesis merkle root of Litecoin;
  that test is inherited, and the make check of v1.1.0.1 was run on a
  build without the GUI, which does not build it.
- The three functional tests of v1.1.0 pass through test_runner.py:
  feature_rin3_enforcement.py, feature_taproot_wallet_guard.py and
  p2p_rin3_services.py (their ten, three and three subtests are not
  printed on a pass).
- wallet_rin3_fund_version.py 7/7 and wallet_rin3_boundary_rescue.py
  9/9, run directly, with the output of every subtest. Log sha256
  a0f406149f087bef418416de5ba21f31349521291ec98f9e2f2e23032a93cf00
  and 2016378bca59f076388414d68dd4efbe2cee751bfcc4b348e0aa9bc7749fdfef.
  Both also pass through test_runner.py, so their registration is
  exercised.
- scripts/sim-rin3-boundary.sh with EXPECT_FUND_MARKER=1: PASS 24 /
  FAIL 0 / INCONCLUSIVE 0. Log sha256
  fb87024fb1e87c12b24dc537d9873a377788833d2624fc456fa603d55e3473d6.
  The coinbase of blocks 839 to 842 on its node A has nVersion 2,
  and blocks 840 to 842 were accepted by both nodes: the coinbase
  exemption of ContextualCheckBlock(), observed.
- scripts/sim-ch.sh reproduces the eight Customized Halving boundary
  values recorded in the v1.1.0 evidence bundle: 6.25 -> 4.00 at
  block 840, 4.00 -> 2.00 at 2100, 2.00 -> 1.00 at 4200,
  1.00 -> 0.60 at 6300 (Sim's 1/1000 scale). Log sha256
  bea55960e65fd4c5323bd777629f44b737f4884ac2f98ab4021b71e16cf89112.
- contrib/release: make help reports VERSION 1.1.0.2 and TAG v1.1.0.2,
  and make -n dist archives the source under rincoin-sim-1.1.0.2/,
  so the archive names above are the ones the tooling produces.

The logs of the boundary script and of the two wallet tests begin
with the commit, a clean-tree check, the digests of the two binaries
and the version string; the unit-test and sim-ch logs carry the
program output alone, taken on the same tree in the same session.

Also on 2026-09-27, the same scripts/sim-rin3-boundary.sh, from this
tree, was run with EXPECT_FUND_MARKER=1 against the binaries of the
published v1.1.0.1 archive, rincoin-sim-1.1.0.1-x86_64-linux-gnu.tar.gz
(sha256
c240bc353928108bcbbd07d6e7abe7ec85ca1e16ffe5a682f3ecc681113b98c5,
verified by its signed SHA256SUMS; rincoind sha256
5f53e9ce92730eaf616a2d062e427fda0d03a61b827fb079bb6308d9c3c8fdf9,
reporting Rincoin-Sim version v1.1.0.1): PASS 21 / FAIL 3. The three
failures are fundrawtransaction emitting nVersion 2, that transaction
rejected with -26 bad-tx-rinhash-version, and walletcreatefundedpsbt
emitting nVersion 2; the marker set before funding survives, and
sendtoaddress emits the marker. Log sha256
bbaa83d176480399471446208d6219f1f5f570858349e82a170be494f31eeb58.
That is the defect this release fixes, on the binaries of the release
before it.

Evidence gathered earlier on this line, before the merge and the bump:

- The same scripts/sim-rin3-boundary.sh (sha256
  a8a804d3a745f848fcb50962b490278bd827a4ae8cd2061049544dbb03a6e368)
  at cc4508b724, before the wallet change: PASS 21 / FAIL 3, exit 1;
  at 3a863e58a3, after it: PASS 24 / FAIL 0, exit 0 (2026-09-20).
- The boundary script and the two wallet tests at b7d12d5327, the tip
  of the wallet branch (2026-09-23), with the same results and the
  same coinbase observation; their digests are recorded in the merge
  commit 7a50a4171e. The tree verified here, 7d0731643, differs from
  that commit's tree in configure.ac only.
- Of the eight functional tests on the funding path, the four that
  fail after the wallet change also fail before it, so none regressed.
  The four that pass were not run before the change on 2026-09-20; in
  the baseline of 2026-09-03 below, taken at 927497cdd5, the commit
  the wallet branch starts from, all four passed.
- The full functional suite was run to completion once after the
  wallet change, on 2026-09-20 at 3a863e58a3 with feature_loadblock.py
  excluded: 55 failures in the runner's summary, the four funding-path
  failures among them. Only the tail of that run was kept; it holds
  every failure, since the summary lists failures last, but not the
  passed and skipped counts. It is published as an excerpt of the
  terminal transcript, the command and its output with the shell
  prompt replaced by "$ " (sha256
  651fc2d90fabd490ebfebd49c3d0a22981e765f616fe6d47578d18d09d494bcd);
  the full transcript, which also holds the shell prompts and two
  unrelated commands, is kept but not published (sha256
  2e82e4200635c07847cfd4b1feaa55cadb6f9c3b85b72ff6c4e4f5a91c0c0c4c).
  No clean-tree check was recorded for that run; HEAD stood at
  3a863e58a3 from 17:26 that day, per the reflog read on 2026-09-23.
  The baseline of this tree at 927497cdd5, before the wallet change
  (2026-09-03, same exclusion, 209 tests: 113 passed, 54 failed, 42
  skipped; log sha256
  511c68466b5cfb5d841ff09cf9d35f79cb803c3918772315ec6e80382fbe4704),
  has a failure set that differs from it in one test: p2p_timeouts.py
  failed on 2026-09-20 and passed on 2026-09-03, and every failure of
  the baseline recurs. That one failure was not investigated. Neither
  set was compared with v1.1.0's run. Two earlier starts on
  2026-09-20 were stopped before their summary, one piped to tail
  with nothing kept and one without the exclusion, which hung at
  feature_loadblock.py: contrib/linearize identifies blocks by
  sha256d of the header, and this chain identifies them by RinHash.
- For the supply accounting branch (2026-08): make check with all 88
  unit suite logs clean; validation_tests four cases, no errors;
  the mainnet assertion verified by breaking it (rincoind -help
  aborts with exit 134 with the cap off by one satoshi).
- The comment-reference branch had no build: every changed line is a
  comment or docstring, git diff --check reports nothing, and both
  Python files compile.

This release ships with a GPG-signed SHA256SUMS on the release page
and, new in this release, eight logs as release assets: the five logs
taken at 7d0731643, the log of the boundary script against the
v1.1.0.1 binaries, the excerpt of the 2026-09-20 run and the baseline
log of 2026-09-03. This release does not change consensus behaviour,
so the v1.1.0 evidence bundle
(https://doi.org/10.5281/zenodo.21805345) remains the evidence for the
consensus behaviour of this tree.

---

## Known issues

- This tree's mempool refuses replacements by default
  (-mempoolreplacement, inherited from Litecoin). A legacy-version
  transaction that a node accepted before the fork height blocks any
  re-creation on that node until the transaction leaves its mempool; a
  restart is the measured way out, and bumpfee is not one.
  The operator guidance that follows is on the Rincoin Core v1.1.0-rc1
  release page and is for the next Core candidate's release notes.
- The defect fixed by the wallet change was present in v1.1.0.1,
  measured on its published binaries, and in v1.1.0, which shipped the
  same wallet code: none of v1.1.0.1's six commits touches it. Neither
  release listed it as a known issue.
- The supply cap is accounted for, not enforced (Stage B, new RIP).
- The full functional suite had 55 failures when last run to
  completion on this line (2026-09-20, after the wallet change,
  feature_loadblock.py excluded), one more than the baseline of
  2026-09-03 before it, p2p_timeouts.py; neither set was compared
  with v1.1.0's run. feature_loadblock.py still hangs and is excluded.
- Carried from v1.1.0.1, unchanged: the built-in -help text still lists
  main, test, signet and regtest for -chain=; the bug report URL baked
  into the binaries still points at Core's tracker; and
  build_msvc/bitcoin_config.h is hand-maintained and stale.

---

## Relation to Rincoin Core

| Branch | Ported to Core |
| --- | --- |
| Supply accounting (Aevust/rincoin-sim#3, five commits) | In Core v1.1.0-rc1. Its release notes list four commits for Stage A, merged as 70ed956ba via rincoin-core/rincoin#2, and name src/amount.h, src/validation.h, src/validation.cpp and src/test/validation_tests.cpp as byte-identical to this tree at 927497cdd5. The Core list has four commits for the five here; the content of 13d9823ed9, which changes two comment lines in src/amount.h and nothing else, is in Core, since that list names src/amount.h byte-identical. |
| Comment references (Aevust/rincoin-sim#4) | In Core v1.1.0-rc1. src/wallet/wallet.cpp was byte-identical between the two trees before the wallet branch, and the Core release notes list every file under test/functional/ as byte-identical to this tree at 927497cdd5, the merge of that branch. |
| Wallet version (Aevust/rincoin-sim#5, eleven commits) | The wallet change and the two functional tests are to be ported for the next Core release candidate, so that the files stay byte-identical between the two trees. Whether scripts/sim-rin3-boundary.sh is ported, or run from this tree against Core's binaries, is not decided. |

Simulator-only and not for porting: the version bump and these notes.
Porting works from the commits this section names, never from a
tag-to-tag diff of the simulator.

---

## Credits

Rincoin-Sim is maintained by Aevust. It builds on Rincoin Core,
itself derived from Litecoin Core and Bitcoin Core; the copyright
lines in the binaries name those projects' developers, and this
release keeps them intact.
