---
name: Good first issue
about: '(Regular contributors only): Suggest a new good first issue for newcomers'
title: ''
labels: ''
assignees: ''

---

<!-- Needs the label "good first issue" assigned manually before or after opening. -->

<!-- A good first issue is an uncontroversial issue that has a relatively
     unique and obvious solution, and does NOT touch consensus, P2P, or
     wallet on-disk format. -->

<!-- Motivate the issue and explain the solution briefly. -->

#### Useful skills:

<!-- For example:
       - "C++17 std::optional and structured bindings"
       - "Qt5 widget layout and signal/slot wiring"
       - "Python 3 for the functional test framework (test/functional/)"
       - "Bash scripting for rincoin-sim regtest scenarios"
       - "Basic understanding of UTXO model and Rincoin Core RPC interface"
-->

#### Want to work on this issue?

For guidance on contributing, please read
[CONTRIBUTING.md](../CONTRIBUTING.md) before opening your pull request.

Additional Rincoin-specific notes for first-time contributors:

- Commits must be GPG-signed (`git commit -S`) and follow Conventional
  Commits format.
- Files must use UTF-8 (no BOM) and LF line endings.
- For changes that need testing under regtest, use `rincoin-sim`
  (1/1000 scale). Logs go to `~/logs/` (outside the repo) following
  the pattern `script-name-YYYY-MM-DD.log`.
- Consensus, subsidy, P2P, and wallet-format changes are out of scope
  for "good first issue" — those require a RIP at
  https://rips.rincoin.org.
