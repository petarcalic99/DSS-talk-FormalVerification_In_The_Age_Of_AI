# Formal Verification in the Age of AI: New Powers, New Traps

Slides from a talk at the **DeFi Security Summit 2026** in Mumbai, held during Devcon week in November 2026. Speaker: Petar Calic, Protocol Lead.

📄 [Slides (PDF)](<Formal Verification in the age of AI - New powers, new traps.pdf>)

🧪 [Experiment runs](experiments/): the agents' properties, tests, CVL specs and reports, plus a simplified version of the vulnerable contract.

## The question

AI can now write code, tests and formal specifications. If we delegate that work, where is the human still needed? And can formal verification give us justified confidence in AI-produced code?

## What we did

We used a real ERC-4626 donation/inflation bug in the `SpectraWrappedTakara` wrapper as the test case. The wrapper prices shares from its raw token balance, so an attacker's donation makes later deposits round down to zero shares. The attack only becomes profitable once there are several victims.

Six coding agents, each in a separate, isolated session, were asked to find bugs. Each had to write plain-language security properties first, then the checks, then a report. Two things varied:

- **Documentation:** the agents got the code alone, a project README, or the README plus five explicit security requirements.
- **Method:** Foundry tests and fuzzing, or Certora CVL specifications and proofs.

## What we found

- **No agent found the real vulnerability on its own.** All six saw the donation mechanism and the victims' losses. However, each one called the attack griefing, judged it unprofitable from a single-victim example, or never assessed the attacker's profit. The profitable theft from several victims only appeared after a human challenged one agent's conclusion that there was no profit.
- **Explicit requirements improved the properties, not the impact analysis.** A fair-deposit property catches every kind of loss, not just zero-share deposits. Even so, the agent that wrote it still misjudged the economics.
- **Formal verification did not find more than tests in these runs.** The prover shows a failing state, but not the sequence of transactions that reaches it. It can also report states that can never be reached. Its limits force rules and models to be split or simplified, and one simplifying assumption hid the bug entirely.
- **Where formal verification is stronger:** it can prove that a fix holds in every state and for every donation amount, whereas tests only sample cases.
- **What a rule proves depends on how it is written.** The functions it calls, what it asserts and every `require` together determine what a passing result means.

## Takeaway

AI speeds up writing properties, tests and CVL. Formal verification gives confidence only in the guarantees we state, review and model faithfully. Choosing those guarantees and judging the impact of a finding stay with the engineer. Use tests, fuzzing and focused formal verification together, early in development, rather than treating formal verification as a final exercise.

These were exploratory pilots, so they support qualitative conclusions, not success rates or a ranking of tools.
