# Experiment: can AI agents find an inflation attack with tests or formal verification?

This folder contains what the agents actually produced in the experiments behind the talk: their property lists, Foundry tests, Certora CVL specifications, harnesses, models and reports. It also contains a simplified version of the vulnerable contract.

> **This is an archive of runs, not a reproducible project.** The agents worked on the real `SpectraWrappedTakara` codebase, which is not included here. Their tests and specs import that code, so they will not compile from this folder alone. Results are as the agents reported them unless stated otherwise.

## The target

- [`contracts/SimplifiedWrappedTakara.sol`](contracts/SimplifiedWrappedTakara.sol): a simplified and modified version of the audited wrapper. The real contract has been simplified and rewritten for compliance reasons, but the mechanism and the bug are the same.
- **V0** is the vulnerable code the agents received. It prices shares from the wrapper's raw tToken balance, rounds down, and uses one virtual share (decimals offset 0). A direct donation of tTokens raises the price without minting shares, so later deposits can round down to zero shares.
- **V1** is our hidden reference repair. It tracks backing in storage, so donations cannot move the price. The agents never saw it.
- **The attack:** the attacker wraps 1 unit, then donates. With one victim it loses money; with several victims it profits. For example, wrapping 1 and donating 200 turns three 100-unit deposits into zero shares, and the attacker exits with a 50-unit profit.

## Setup

Each agent got the code and one task: find bugs. It had to write plain-language properties first (`PROPERTIES.md`), then checks, then a report mapping each property to its check, its result, and each finding with its impact.

| Documentation supplied | Foundry: unit, fuzz and invariant tests | Certora: CVL and proofs |
|---|---|---|
| L0: code only | [T0-pilot](runs/T0-pilot)* | [F0](runs/F0) |
| L1: a project README | [T1](runs/T1) | [F1](runs/F1) |
| L2: README plus five explicit security requirements, including fair deposit | [T2](runs/T2) | [F2](runs/F2) |

\* T0-pilot was the first Foundry pilot. Its documentation level was not recorded; its prompt is in [`PROMPT.txt`](runs/T0-pilot/PROMPT.txt).

**Isolation.** An orchestrator agent prepared the inputs and evaluated the results; it knew the answer. A human launched each run and checked isolation. Every run was a fresh cloud session with its own copy of the source and no Git history, other repositories, earlier sessions or web access. Certora runs started with compilation only. Selected prover jobs were then run and their results fed back to the agent.

**Fair deposit**, the key requirement supplied at L2, says: immediately after depositing `a` assets, the shares received are worth at least `a − 10` base units according to `previewRedeem`.

## Runs

| Run | What the agent found | Files |
|---|---|---|
| **T0-pilot** | Saw that a donation can give a victim zero shares, then called the attack griefing. Its fuzz test runs one victim, asserts the attacker never profits, and never checks the victim's loss. Its invariant handlers include no donation. Reported 19 tests: 16 pass, 3 fail. | properties, report, tests |
| **T1** | Inferred a `shares > 0` property. A test with a donation showed a 10,000 USDC deposit minting zero shares, so the bug was caught as a symptom. Attacker profit was not established. | properties, report, tests |
| **T2** | Translated fair deposit into `previewRedeem(shares) + 10 >= assets`. This also caught a 1,000 USDC deposit that received shares but lost about 350 micro-USDC (358 in the initial report, 349 in the summary). The one-victim exploit test led it to call the attack griefing. Reported 44 tests: 34 pass, 10 fail. | properties, initial report, summary, tests, fixture |
| **F0** | Its rule `P8_noZeroShareDeposit` was violated by a 7,939-unit deposit minting zero shares. The trace showed no donation and no victims, and the agent stopped at a rounding bug. In two human-directed follow-ups (`P8_FOLLOWUP.md`, `P8_EXPLOIT_REPORT.md`), it showed a two-victim theft by concrete execution: 1,000 USDC becomes 1,110.05. It also tested fix variants: offset 6 removed the attack, while reverting on zero shares was not enough (the attacker still gains 122.98 USDC with four victims). The full profit rule timed out. | properties, report, CVL, config, harness, fix variants, follow-ups |
| **F1** | None of its 20 properties protects deposit value. It called the attack unprofitable. Only its tToken model survives; the original report and spec are not available. | tToken mock |
| **F2** | Wrote a `fairDeposit` rule matching the requirement. The first submission was compile-only. Its Python proof of concept shows a 500 USDC deposit getting zero shares, and it concluded griefing. A later follow-up ran four prover jobs after model repairs: fair deposit and donation neutrality fail, and supply consistency verifies. One reported witness starts from a state that cannot be reached from an empty wrapper (999,999 shares with zero value). | properties, report, CVL, config, harness, tToken model, PoC, follow-up |

## What it shows

- **No agent found the profitable attack on its own.** All six saw the donation mechanism and victim loss. Every initial report either called it griefing or unprofitable from a one-victim example, or did not assess profit. The multi-victim theft appeared only after a human challenged F0's no-profit claim.
- **Explicit requirements produced better properties, not better impact analysis.** Fair deposit catches any loss, including the small positive-share loss and an insufficient revert-on-zero fix that `shares > 0` passes.
- **Formal verification did not find more than tests here.** A violation shows a failing state, not the sequence that reaches it. Witnesses can start from states that cannot be reached, and model simplifications and timeouts move reasoning back to the human.

## Notes on the files

- Files keep their original content. Markdown reports were renamed from `.md.txt` back to `.md`.
- Certora job links were replaced with `[Certora job link removed]`. The `BUSL-1.1` headers in agent-written test files come from the original project's template.
- Left out: the original contract, the F0 patch that made its private helpers `internal` for the harness, F1's report and spec, F2's revised CVL, and raw prover traces.
- Test counts and prover outcomes are as reported by the agents or the follow-up reports. F2's Python proof of concept is the only artifact that was independently re-run (its output is in `reviewer-poc-output.txt`).
- These are exploratory pilots, one run per condition. They support qualitative conclusions, not success rates or a ranking of tools or models.
