# Reviewer notes

These are the orchestrator's review notes from the research behind the talk, kept separate from what the agents produced (in [`../runs`](../runs)). Each note reviews one run's properties, tests or CVL, model and report, and separates what the agent reported from what the reviewer checked.

The notes were written during the research, as each run came in, between 2026-10-25 and 2026-10-31. Earlier notes can describe evidence as missing or pending when a later note covers it, so read them with their dates. They were copied from the private research repository. Links to private material (the evaluation project, the template, prover jobs and sessions) were removed, and file links now point to this folder.

**On isolation.** Some notes say a run's isolation verdict was "not recorded", "unconfirmed" or "pending". That means only that the orchestrator had no written verdict in its own records when it wrote the note. It does not mean isolation failed or went unchecked. Isolation was built into the setup: every run took place in its own cloud session with limited access, as described in the [experiments README](../README.md#setup).

## Start here

- [Final findings](final-findings.md): the overall conclusions. Agents proposed a relevant fix (internal accounting) before they understood the profitable attack. The note also covers which fixes address which guarantees, and what each hypothesis does and does not support.
- [Findings log](findings-log.md): a running list of findings in date order. It covers calibration (reference tests and prover jobs on the vulnerable V0 and fixed V1), the environment, isolation, and the agent runs, including the review of the first Foundry pilot (T0).

## Per run

| Run | Review |
|---|---|
| T0-pilot | In the [findings log](findings-log.md#first-foundry-pilot--static-review-2026-10-26) |
| T1 | [T1.md](T1.md) |
| T2 | [T2.md](T2.md): T2's findings, plus a comparison of the documentation levels and methods |
| F0 | [F0.md](F0.md): includes the timeline of human-directed follow-ups (P8, the challenge to the no-profit claim, the exploit run) |
| F1 | [F1.md](F1.md), [F1-cvl-review.md](F1-cvl-review.md) |
| F2 | [F2.md](F2.md): the original submission and the prover follow-up |

## Cross-run comparisons

- [F0-F1-matched-cvl.md](F0-F1-matched-cvl.md): rules with similar names in F0 and F1 that make different claims.
- [F1-F2-spec-comparison.md](F1-F2-spec-comparison.md): how the explicit requirements given at L2 changed F2's specification compared with F1's.
