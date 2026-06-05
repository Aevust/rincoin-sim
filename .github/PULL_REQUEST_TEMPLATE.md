<!--
*** Please remove the following help text before submitting: ***

Pull requests without a rationale and clear improvement may be closed
immediately.

Rincoin Core is a single integrated repository covering consensus,
node, wallet, and GUI. There is no separate GUI repository — GUI
changes are submitted here.
-->

<!--
Please provide clear motivation for your patch and explain how it
improves Rincoin Core for users, node operators, miners, or
developers:

* Test improvements and new tests that increase coverage are always
  welcome.
* All other changes should have accompanying unit tests (see `src/test/`)
  or functional tests (see `test/functional/`). Please note which tests
  cover the modified code. If no tests exist for the region of modified
  code, new tests should accompany the change.
* For changes that affect simulation behavior, please also run the
  relevant `rincoin-sim` scenarios (e.g., `sim-ch-rin3.sh`,
  `sim-ch-attack.sh`, `feature_*.py`) and include the PASS/FAIL summary
  in the PR description.
* Bug fixes are most welcome when they include steps to reproduce, an
  explanation of the underlying issue, and reasoning for the chosen
  fix. Please indicate whether the bug is Rincoin-specific or inherited
  from upstream (Bitcoin Core / Litecoin Core); if upstream, link the
  relevant upstream issue or commit.
* Features are welcome but may be rejected on design or scope grounds.
  If a feature has many external dependencies, consider building it
  outside Rincoin Core first.
* Refactoring changes are only accepted if they are required for a
  feature or bug fix, or if they significantly improve developer
  experience. Stylistic changes are usually rejected unless they are
  explicitly preferred in `doc/developer-notes.md`.
-->

<!--
== Consensus changes ==

Any change that affects consensus (block validation, transaction
validation, subsidy calculation, deployment parameters, soft/hard
fork activation logic) MUST be backed by a ratified or draft RIP
(Rincoin Improvement Proposal). Link the RIP in this PR description.

RIP repository: https://rips.rincoin.org
                (redirects to https://github.com/Aevust/rincoin-rips)

Consensus changes also require:
* Validation on `rincoin-sim` at 1/1000 regtest scale
* Sign-off from @ysmreg (Founder) as final merge authority
* Approval from Core Strategic Authority per the rules in RIP-0001

PRs that modify consensus without a referenced RIP will be closed.
-->

<!--
== Commit hygiene ==

* Commits MUST be GPG-signed (`git commit -S`). Unsigned commits will
  not be merged.
* Commit messages follow Conventional Commits format
  (https://www.conventionalcommits.org/), e.g.:
    feat(consensus): enforce RIN3 nVersion at fork height
    fix(mempool): prevent zombie tx DoS during CH activation
    docs(rip): clarify dynamic subsidy scaling formula
* Wrap commit message body at 50–70 characters per line.
* One logical change per commit. Separate commits for code, tests,
  release notes, and documentation are preferred over a single mixed
  commit.
-->

<!--
== Review timelines ==

Rincoin Core uses a thorough review process. Even trivial changes are
reviewed by multiple Core role holders before merge. With a small
active reviewer base, patches may sit for some time — please be
patient. PRs touching consensus, wallet, or P2P will receive the
slowest (and most careful) review.
-->
