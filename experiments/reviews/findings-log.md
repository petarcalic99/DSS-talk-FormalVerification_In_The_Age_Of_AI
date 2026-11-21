# Experiment 01 findings

> **Reviewer notes, not agent output.** Written by the orchestrator during the research, from the run artifacts in [`../runs`](../runs). Copied from the private research repository; links to private material (evaluation project, template, prover jobs, sessions) were removed and file links point to this folder. See [the index](README.md).

Running list of findings worth telling in the talk. Each entry records its evidence level; predictions and plans stay in the experiment plan. Agent submissions have static reviews; reported test execution has not been independently reproduced here. Original T2 and F02 artifacts are archived alongside their reviews; F02 compilation is reported and its supplied arithmetic PoC was independently rerun, and its later follow-up reports prover outcomes after model revisions, without supplied revised CVL or raw traces.

## Calibration (reference tests, before any agent run)

- **Our own hand-derived claim was wrong, and a fuzzer caught it.** (2026-10-25)
  - Claim: with the phantom share, two *equal* victims only break even, so a no-profit rule needs three.
  - Observed: true only when the attacker starts with exactly one share. With a seed of `s ≥ 2` shares, two equal victims are profitable: the fuzzer found `s = 100`, two victims of 7,398 tTokens, attacker +4,748, exactly `(s·Σt − D)/(s+1)`.
  - Talk point: humans write wrong specifications too. The attack-specific property depended on an assumption (the seed) nobody wrote down; running it before trusting it exposed that. The general property (P1) needed no such detail.
- **The general property finds the bug almost immediately; the plausible ones never do.** (2026-10-25)
  - P1 (fair deposit, ε in assets) failed on V0 within about 10 fuzz runs once donation states were in scope; D1 (donation keeps price) likewise.
  - I1 (supply = balances), I2 (price never decreases), R1 (round trip, no user gain), P1s (loss ≤ one share) and S1 (slippage enforced) all pass on the vulnerable V0, over 256 fuzz runs and 128,000 invariant calls each.
  - Talk point: the right property matters more than the method or the effort.
- **The existing test suite already had the right property; its setup masked it.** (2026-10-25)
  - The wrapper's suite has a rate-sanity check from the decimals case: one whole share is never worth more than 10 underlying tokens. It passes on the vulnerable V0, because the suite's setup always pre-funds the wrapper with four users' deposits.
  - The identical check, run from an empty wrapper with donations allowed, fails on V0 within 6 fuzz runs: one share worth about 1.5M USDC. It passes on V1.
  - Talk point: a general property was already written, reviewed and passing. The scope (the starting state), not the property, hid the bug. Reviewing a test means reviewing its setup too.
- **A slippage bound can pass while the user is robbed.** (2026-10-25) With `minShares` taken from `previewWrap` in the same transaction, the bound holds and the depositor still loses value (S1-preview fails on V0).
- **ε has a measurable floor.** (2026-10-25) The largest honest loss is 2 wei (two rounding steps through the tToken), and ε = 1 fails on honest deposits. Picking ε is a measured decision, not a guess; we chose 10 wei for margin. What separates P1 from the trap is that ε is in assets, not its exact size.
- **The wrapper's own 49 property tests pass on the vulnerable version,** now reproduced locally on the real Takara market, without a fork. (2026-10-25)

## Certora calibration (6 jobs)

- **The prover found the bug in under two minutes, from an arbitrary state.** (2026-10-25) P1 fails on V0: 144 shares backed by 25,215 tTokens, a 13-wei deposit gets 0 shares. D1 fails on V0 and passes on V1, with a non-vacuous sanity check. No donation step had to be modelled: the arbitrary starting state covers it.
- **The prover's counterexample is broad: nobody had to think of donations.** (2026-10-25)
  - The prover does not replay transactions; it starts from any storage values. A donation's only effect is a wrapper holding many more tTokens than its share supply, and the prover picked such a state directly. The rule never mentions donations.
  - A fuzzer or unit test finds the same bug only if someone adds a donation step and starts from an empty wrapper (see the masked rate-sanity finding above).
  - Talk point: the arbitrary starting state is the prover's real advantage here, covering attack paths the engineer did not imagine. The price is the next finding: it also picks states that can never happen.
- **A counterexample can be spurious, and telling which is the human's job.** (2026-10-25)
  - P1s (the trap) was predicted to pass on V0 but failed. The counterexample starts with the wrapper holding more tTokens than exist (balance 2^256 − 11, supply far lower). OpenZeppelin adds balances unchecked because balance ≤ supply always holds, so the mint wrapped around and the shares became worthless.
  - The genuine P1 counterexample also contained an impossible detail (tToken supply 50 below the wrapper's balance) that did not matter for the failure.
  - Talk point: "unreachable state" is sometimes the right verdict and sometimes the excuse that hides a real bug. Here one counterexample is real and one is an artefact, and only reasoning about reachability separates them. This is hypothesis 3's interpretation step.
- **Proving the fix needs an assumption, and the same assumption hides the bug on the vulnerable version.** (2026-10-25)
  - P1 first failed on the fixed V1, from a state V1 cannot reach (0 shares, a huge tracked balance).
  - The supporting invariant is "the tracked tToken balance equals the share supply": V1's price stays exactly 1:1, so nothing ever rounds. Foundry checked it over 128,000 random calls including donations; it is assumed, not proven, in CVL.
  - With it, P1 is **proven on V1** (job 8). Run with the same assumption on the vulnerable V0, P1 **also passes** (job 9): the assumption excludes every donation state. Both passes are non-vacuous.
  - Talk point: one `require`, two green checks, one of them on the vulnerable code. A pass is only as good as its assumptions, and an assumption that is true for the fixed code can be false for the code under review.
- **Some checks just time out, and timeouts cost the most.** (2026-10-25) P1s timed out on both versions (7 and 14 minutes), using 21 of the 47 prover minutes spent. A timeout is not a pass; Foundry gave the answer for free.

## Environment and setup (what real projects look like)

- **The protocol below the wrapper has the same bug class.** (2026-10-25) Takara's `mint` accepts a mint that yields 0 tTokens, and its cash is its own token balance. On an empty market, a USDC donation to the tToken zeroes deposits one layer below the wrapper, which the wrapper fix (V1) cannot prevent.
  - Consequence: a freshly deployed local market would make the fixed version fail too and corrupt scoring. Seeding the market to its live state removes it.
  - Talk point: where the verification boundary is drawn decides which bug you see. A mock would have hidden this choice; an unseeded deployment would have created a false one.
- **Faithful environments take real work.** (2026-10-25)
  - Sei's USDC is a bank precompile that does not exist in Foundry, so it must be replaced.
  - Takara's linked source repository was not reachable; the code came from verified on-chain source (Sourcify, exact match), and its live parameters were read over RPC.
  - The live market is tiny (about 1,684 USDC supplied) with minting paused, so even reproducing "the real state" involved choices.
- **A prover will likely need a summary of the external protocol, and a summary can mask the bug.** (2026-10-25, design finding) An unconstrained tToken rate brings the Takara-level path back; constraining it can also exclude the wrapper's donation state. Masking assumptions are now scored.
- **Test-harness mistakes look like findings.** (2026-10-25) Porting the wrapper's suite to the local market first produced 5 failures: a missing admin role and a helper that dealt USDC where the original dealt tTokens. Neither was a contract bug. A failing check needs triage before it counts.

## Experiment design (running agent experiments)

- **Isolation is the hardest part of evaluating agents.** (2026-10-25) In one container, the research notes, the hidden evaluation project and the template sat side by side: an agent could find the answer with `ls ..`, in git history, or in a code comment. The fix is an orchestrator that knows everything, frozen run kits as the only instruction channel, and one fresh sandbox per run.

- **An agent can inherit a path to the answer through its own tooling.** (2026-10-25) A nested `claude -p` started inside a Claude cloud session, with a fresh configuration and MCP disabled, still had tools to list and message the user's other sessions and to see their connectors. In this experiment one of those sessions is the orchestrator, which knows the bug. Isolating an agent means checking what its tools can reach, not only which files it can read.

## Agent runs

### Final supplied F02 stage — source review and arithmetic replay, 2026-10-28

- **The main victim-loss mechanism is identified; formal detection is pending.** The original report records compilation/typechecking with exit 0 and no prover jobs. Its Python PoC shows 500 USDC deposited for zero shares after an attacker seed and tToken donation; the reviewer reran the unchanged submission and reproduced the output. All seven [original F02 files](../runs/F2/) are archived with checksums, with reviewer stdout separately labeled. The original expected outcomes are not formal results; the later follow-up below reports actual jobs.
- **Explicit intent improves economic coverage without making every translation faithful.** S5 checks immediate `previewRedeem` value against assets minus 10 base units; S4 executes a donation and compares prices. These supplied guarantees improve on F1's missing protection and F0/T1's narrower zero-share checks. However, F02's S19 CVL checks which selector changes privileged state without checking caller permission. Better central properties coexist with an authorization regression; see [precise rule references](F2.md#cvl-translation-matched-guarantees-and-concrete-gaps).
- **A model can retain the main bug while excluding another returned finding.** F02's mock always reports current-block accrual and stores a rate that can only increase. It omits the actual empty-market rate reset behind T02's reported 1,043,481 → 1,000,000 quote change. Its expected price-monotonicity result is therefore not evidence against T02. The separately archived [F1 mock](../runs/F1/) models more accrual/rate/policy behavior, though it is also partial.
- **Impact interpretation remains weak.** F02 again generalizes from a losing one-victim sequence to griefing-only impact, despite earlier profitable multi-victim calibration and the separately prompted F0 execution report. This assesses economic reasoning in the report; F02 did not see a prover counterexample. The [F02 synthesis](F2.md#place-in-the-research-and-focused-follow-up) maps these observations to hypotheses 1–3 and records the original evaluation plan, later reported proof outcomes and separately labeled evaluator follow-ups. No statistical method ranking or completed scored grid follows.

### F02 prover follow-up — reported results and interpretation, 2026-10-28

- **Discovered mechanism, incomplete economics.** The [later report](../runs/F2/FOLLOWUP_REPORT_F02.md) records failures of donation neutrality and fair deposit after model repairs, while supply consistency and deposit/preview matching verify. This is reported formal detection of the already identified loss mechanism, not evidence that the vulnerability remains undiscovered. The agent still misses profitable multi-victim interpretation by repeating its one-victim griefing-only conclusion.
- **The model required substantive repair after compiling.** Unresolved external calls initially invalidated all four selected results; dispatcher recursion and inconsistent token states produced more artefacts. Revisions added dispatch summaries, token ghosts and rate bounds. Treat these as an evaluator-assisted follow-up, not the untouched original F02 result. Revised source and raw job exports were not supplied; the archived report redacts only three anonymous-access-key parameters.
- **Passing and failing results still need semantic review.** S19's named original rules check privileged selectors, not caller permissions. The reported zero-price donation witness also conflicts with the backing inequality preserved by ordinary offset-zero transitions: `V ≥ S` plus the stated rate floor implies a whole-share quote ≥ 10,000 base units, not zero. This is a reviewer reachability concern, not an independently replayed counterexample. See [the full bullet-list follow-up](F2.md#prover-follow-up-reviewed-on-2026-10-28) for the derivation, dust fund-flow correction, incomplete checks and research implications.

### Final supplied T2 stage — review and method comparison, 2026-10-28

- **Supplied intent becomes a broader executable check.** T2's R5 uses `previewRedeem(shares) + 10 >= assets`, including donation states. The initial report describes a small-donation example receiving positive shares while losing more than epsilon, which a zero-share-only requirement misses. The summary reports 349 units lost versus the initial report's prediction of 358; the exact executed figure remains unresolved without raw output.
- **Scope and interpretation still decide the result.** The same fair-deposit invariant is inherited by handler suites with and without donations; only the donation suite is reported to fail it. The one-victim exploit test still has no attacker exit or profit assertion, so the report's general griefing-only interpretation remains unsupported by that test and conflicts with earlier multi-victim calibration.
- **Completion and evidence:** at the time of T2 review this was the final supplied stage; F02 was supplied afterward and is reviewed above. The summary reports 44 tests / 34 passes / 10 failures; no independent Foundry run or raw log was supplied, and 256 x 500 claimed invariant coverage conflicts with inline 64 x 40 settings. The [six original T2 artifacts](../runs/T2/) are preserved unchanged. See [T2 final findings](T2.md) for source examples, stage/method comparisons, and evidence limits. Do not infer a completed original grid or statistical method ranking.

### F1 pilot — static review, 2026-10-27

- **Recognition in prose is not specification coverage.** F1's report mentions donation-driven zero-share loss, but none of its twenty properties protects deposit value or rejects zero-share deposits. Original F0 had a zero-share rule; T1 inferred a non-dust donation-loss property. F1 again calls the attack unprofitable without establishing multi-victim economics. Evidence and original-upload fingerprints: [F1 findings](F1.md).
- **Similar rule names can hide different claims.** F0 executes deposit/redeem for its round trip; F1 only calls conversion views. F1 improves the deposit-limit statement by checking actual deposits, but narrows redemption availability to owner calls. These differences arise at both property selection and translation; see the [CVL review](F1-cvl-review.md).
- **Evidence status and next action:** compilation is reported, not independently reproduced; no F1 prover outcome is recorded. The [matched-rule findings](F0-F1-matched-cvl.md) give precise source examples. Additional candidate prover checks are deferred as of 2026-10-27; proceed to T2.

### First Foundry pilot — static review, 2026-10-26

- **Evidence:** Petar supplied `REPORT.md`, `PROPERTIES.md`, and `SpectraWrappedTakara.t.sol` in the research conversation, plus the initial prompt below. The orchestrator could not access the run session; the findings below come from those supplied artifacts.
- **Classification:** Foundry (T), unscored pilot. Specification level remains unconfirmed: T0 only if no README was supplied. Model, duration, actual source commit, and complete run configuration are not available. Do not infer FREEZE-2 compliance from a matching prompt alone.
- **Isolation:** Petar handles verification manually; no explicit verdict or repository-write history is recorded here. Lack of a transcript does not block static review.
- **Reported execution, not independently reproduced:** 19 tests, 16 passing and 3 failing; 2,000 fuzz runs per fuzz test and 256 × 500 invariant calls. The report attributes the three failures to two limit-related bugs.
- **The agent recognized victim harm but missed profitable multi-victim exploitation.** Its report acknowledges that a donation can give a victim zero shares, then calls the attack griefing only and claims the attacker never comes out ahead. Its `testFuzz_P9_donationAttackNotProfitable` wraps the attacker seed, donates tTokens, performs exactly one `_deposit(alice, victimAssets)`, exits, and asserts `backT <= spentT`. It never checks Alice's received value or adds further victims. Earlier reference calibration already establishes profitable multi-victim sequences. This is partial discovery followed by an unsupported generalization, not complete failure to notice the mechanism.
- **The stateful campaign cannot fill that gap.** Its selected handlers are deposit, redeem, wrap, unwrap, and passTime; none makes a direct donation. More iterations of these handlers do not add the missing action. P3/P4 only assert round-trip output ≤ input, allowing depositor loss; no general fair-deposit property is stated.
- **Do not confuse property IDs:** this run's P1 is exact deposit preview, not the reference suite's P1 fair-deposit property. Map by meaning, not label.
- **Additional reported bugs remain unverified:** `maxDeposit` ignores mint restrictions/caps; `maxRedeem` ignores market liquidity. The tests exercise those scenarios, but catch all reverts without checking their cause. The redeem test also asserts `max == shares`, which would reject a correctly reduced limit; its synthetic borrowing uses `vm.store` at slot 11 and requires storage-layout/reachability review.
- **Talk point:** recognizing an attack pattern and passing a narrowly scoped test does not establish its economic impact. Separate mechanism discovery, victim harm, attacker profit, and the scope of the conclusion.
- **Record status:** the [original artifacts and exact prompt](../runs/T0-pilot/) are archived at Petar's request, with SHA-256 checksums. Independent execution and any control-repository copy remain pending. No scored success rate or general model-capability conclusion follows from one pilot.

Initial prompt supplied by Petar (verbatim):

```text
Find bugs in the current project.

First, before writing any test, write PROPERTIES.md in the project root: the properties this project must satisfy, each in one plain-language sentence.

Then write Foundry tests that check those properties, run them, and write REPORT.md in the project root: for each property, the test that checks it and its result; then each bug found and its impact.
```

### Organization changes requested after the pilot — 2026-10-26

- Run agents must never write to or access the shared template repository: use disposable source snapshots and export artifacts separately. This prevents later runs from seeing earlier results; it is not evidence that the first run actually pushed anything.
- Petar verifies isolation manually. Each report must reproduce its initial prompt and supplied specifications, so cell classification and input review do not depend on session-link access.
- These changes are specified in the setup procedure; control run kits need a new freeze. Preserve the original pilot and distinguish protocol versions.


