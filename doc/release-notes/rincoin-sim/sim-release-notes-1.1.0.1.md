# Rincoin-Sim version 1.1.0.1 release notes

Rincoin-Sim is a 1/1000-scale functional-test build of Rincoin Core.
It is not a Core release and is not for mainnet use.

Release page: https://github.com/Aevust/rincoin-sim/releases/tag/v1.1.0.1

This is a patch release on v1.1.0. Six commits, none of which touch
consensus: the Customized Halving implementation, the RIN3 enforcement
and the P2P behaviour are byte-identical to v1.1.0. What changes is how
the daemon refuses the networks it must not join, what the binaries
call themselves, how the release tooling derives version numbers, a
startup self-check over the chain parameters, and the README.

---

## Versioning

The version scheme is GENERATION.MAJOR.MINOR.PATCH, defined in
configure.ac. This release is the first use of the PATCH field:

| Field | Value | Meaning |
| --- | --- | --- |
| GENERATION | 1 | PoR epoch (~400 years) |
| MAJOR | 1 | Protocol upgrade line |
| MINOR | 0 | Maintenance line |
| PATCH | 1 | Sim-internal fixes. Core keeps this field at 0 |

The version string reads:

    Rincoin-Sim version v1.1.0.1            (built on the tag)
    Rincoin-Sim version v1.1.0.1-<commit>   (built off the tag)

Two things changed in that line since v1.1.0: the name -- these
binaries no longer announce themselves as Rincoin Core -- and the
statement above of both forms. The v1.1.0 notes gave only the
off-tag form, and the shipped binaries, built on the tag, printed
the other one. Both are stated here so neither reads as a mismatch.

---

## How to upgrade

Shut down any running node, replace the binaries, restart with
-regtest. This tree runs regtest only; there is no chain data
migration to consider. Release archives are named

    rincoin-sim-1.1.0.1.tar.gz                     (source)
    rincoin-sim-1.1.0.1-x86_64-linux-gnu.tar.gz    (Linux binaries)

For native builds from source, --with-pic remains required, as in
v1.1.0.

---

## Compatibility

Built and tested on Ubuntu 24.04 (g++ 13.3.0, x86_64). Other
platforms are untested.

---

## Notable changes

### Chain selection (init)

The daemon-level guard is inverted from a denylist to an allowlist:
rincoind now refuses every chain except regtest, with an error naming
the chain. Previously it refused mainnet and testnet by name and let
everything else through, and this tree had a name it did not account
for: signet, which the inherited code resolves to the testnet
parameter set. On the v1.1.0 binaries, -chain=signet and -signet both
started a node carrying the 1/1000-scaled testnet parameters under a
datadir named signet/. Both spellings are now refused at startup.

The guard also moved inside the existing exception handler. On
v1.1.0, conflicting chain flags (for example -regtest -testnet)
aborted with SIGABRT through an assertion in chainparamsbase; they
now produce a normal one-line error and exit 1.

### Release tooling (build)

contrib/release/Makefile now parses the PATCH field from
configure.ac. It previously read only the first three fields, and
everything it derives -- VERSION, TAG, the artifact names, and the
ref `make dist` hands to git archive -- comes from that base. On a
tree with PATCH set, `make release` would have packaged the previous
tag's source under the previous version's name while the binaries
reported the new one, with no error anywhere. This release is the
first to depend on the fix.

### Package name (build)

The AC_INIT package name is now Rincoin-Sim. Only the name changed:
the tarname, the bug report URL, the home page and the copyright
attribution are untouched -- the copyright is held by the Rincoin
Core developers, and this build does not change that. Nothing on the
wire moves; the P2P user agent is built from CLIENT_NAME, not from
the package name.

### Startup self-check (chainparams)

Each chain parameter constructor now documents and asserts that the
Customized Halving fork height equals four times the halving
interval (RIP-0002 / RIP-0009). GetBlockSubsidy derives every CH
phase boundary from the interval alone, so the two fields must agree,
and nothing in the tree said so before. The daemon constructs all
four networks at startup to fill in its help text, so every rincoind
start checks all three parameter sets, even though this tree only
ever runs regtest. Measured: with the mainnet fork height changed by
one, `rincoind -regtest` aborts in the CMainParams constructor,
naming the assertion; reverted, it starts normally.

### Documentation

The README's killswitch attribution, network table and extraction
commands were stale, in ways that mattered: the extraction example
named a v1.0.7 file that no current release produces, and the
network table did not mention signet. All four chains are now listed,
the extraction commands use a version placeholder so they stay
correct across releases, some two hundred lines of quoted test logs
now point at the archived evidence instead, and the DOI links are
three, labelled: the concept DOI, the v1.1.0 release evidence, and
the v1.0.7 simulation artifacts.

---

## Verification

Verified at commit 6660e300b, the parent of this tag's target; the
tag adds only these release notes on top of it, and touches no code.
On a clean tree with no local modifications:

- `rincoind -version` reports `Rincoin-Sim version v1.1.0.1-6660e300b`
  with no -dirty suffix.
- `make check` passes: the Rincoin-Sim unit test suites (run via
  check-local), libsecp256k1 (2) and univalue (3), with zero
  failures and zero errors. The chainparams assertions of this
  release are exercised on that path by the suites that construct
  chain parameters, pow_tests and validation_tests among them.
- The three functional tests written for Rincoin all pass:
  feature_rin3_enforcement.py (10 subtests),
  feature_taproot_wallet_guard.py (3), p2p_rin3_services.py (3).
- scripts/sim-ch.sh reproduces the eight Customized Halving boundary
  values recorded in the v1.1.0 evidence bundle: 6.25 -> 4.00 at
  block 840, 4.00 -> 2.00 at 2100, 2.00 -> 1.00 at 4200,
  1.00 -> 0.60 at 6300 (Sim's 1/1000 scale).

This release ships with a GPG-signed SHA256SUMS on the release page
and no separate evidence bundle. That is a deliberate, and smaller,
evidence level than v1.1.0 carried: this release does not change
consensus behaviour, so the v1.1.0 evidence bundle
(https://doi.org/10.5281/zenodo.21805345) remains the evidence for
the consensus behaviour of this tree. The concept DOI resolves to
the latest bundle, which remains the v1.1.0 one.

---

## Known issues

- The built-in -help text still lists main, test, signet and regtest
  as allowed values for -chain=. That text is inherited and shared
  with the RPC-client tools, where loading other networks' parameters
  is legitimate; the daemon's refusal is what governs.
- The bug report URL baked into the binaries still points at
  Rin-coin/rincoin, Core's tracker. Where simulator reports should
  land is a separate decision this release does not make.
- build_msvc/bitcoin_config.h is hand-maintained, is not built by
  this tree, and remains stale.

Three defects found in v1.1.0 after it was tagged are fixed by this
release: the binaries announced themselves as Rincoin Core; signet
started a scaled testnet node; and the bundled README predated the
tree it shipped with.

---

## Relation to Rincoin Core

One commit in this release is written to be ported to Core: the
chainparams comment-and-assert (this repository, commit 176746747).
The rest are simulator-only and must not be ported -- Core starts
mainnet, is named Rincoin Core, and keeps the PATCH field at zero.
Porting works from the commits this section names, never from a
tag-to-tag diff of the simulator.

---

## Credits

Rincoin-Sim is maintained by Aevust. It builds on Rincoin Core,
itself derived from Litecoin Core and Bitcoin Core; the copyright
lines in the binaries name those projects' developers, and this
release keeps them intact.
