# Formal Verification in the Age of AI: New Powers, New Traps

Slides and experiments from a talk at the **DeFi Security Summit 2026** in Mumbai, held during Devcon week in November 2026. Speaker: Petar Calic, Protocol Lead at Spectra.

🎥 [Talk recording (YouTube)](https://youtu.be/LFOlyW6mx4M)

📄 [Slides (PDF)](<Formal Verification in the age of AI - New powers, new traps.pdf>)

🧪 [Experiments](experiments/): one folder per experiment. The talk's experiment is [inflation-vulnerability](experiments/inflation-vulnerability/): the agents' properties, tests, CVL specs and reports, plus a simplified version of the vulnerable contract.

🔍 [Reviewer notes](experiments/inflation-vulnerability/reviews/): the per-run reviews, the findings log and the final findings.

## What this talk is about

The talk looks at how software development changes with AI, especially for critical software like smart contracts, through the case of formal verification. It is not a formal verification tutorial. The aim is to give:

- a practical picture of how to use formal verification on smart contracts, which is less intimidating than most tutorials suggest;
- an agent-based workflow you can reuse (see [experiments](experiments/));
- an understanding of what formal verification can and cannot do.

## The question

Formal verification has become popular, and it does make systems more secure. But it is often presented as the answer to vibe coding: a tool that turns untrusted, AI-written code into trusted code. So the talk asks:

1. If AI writes the code, tests and formal specifications, where is the human still needed?
2. Can formal verification give justified confidence in AI-produced code?

## The pipeline, and who does each step

Formal verification starts from properties the code should always satisfy. Every codebase has some, at least implicitly. For example: depositing and redeeming in the same transaction never returns more than was deposited.

1. **Informal specification:** write the property in plain language.
2. **Formal specification:** translate it into a logical rule (here, Certora's CVL).
3. **Model and assumptions:** describe the external contracts and the states the prover may start from.
4. **Solver:** the prover returns a proof, a counterexample, or a timeout.
5. **Interpretation:** decide what the result means.

A human, an LLM or both can do each step. LLMs are probabilistic: their answers look consistent, but you can't predict or explain them. So the real question is which steps to automate fully, which to supervise, and which to keep manual. In this setting LLMs help most with learning the tools, brainstorming properties, translating them into CVL, writing models and simplifications, explaining results, and building proofs of concept.

## The experiment

The test case is a real ERC-4626 donation (inflation) bug in the `SpectraWrappedTakara` wrapper. It was deliberately only partly fixed: the share maths uses OpenZeppelin's single virtual share, but no decimals offset. With that virtual share an attacker keeps only about half of what they take, so attacking a single victim loses money. The attack becomes profitable with several victims: each victim whose deposit rounds down to zero shares adds to the attacker's balance, until the attacker breaks even and then profits.

Six agents (Claude Opus 5.5) each got the same task: write plain-language properties, then find bugs with checks, then report. Each ran in its own isolated cloud session with only the code template: no Git access and no knowledge of the experiment. Two things varied:

- **Documentation:** no context, a project README, or the README plus explicit security requirements.
- **Method:** Foundry tests and fuzzing, or Certora formal verification.

The [experiment folder](experiments/inflation-vulnerability/) describes the setup and isolation in detail, and how to run a similar experiment.

## What we found

There were two hypotheses. First, the specification decides what gets detected. Second, once the property is fixed, the method (tests or formal verification) matters less. Both held. But the main finding was a third point that turned out to matter more: **interpretation**.

- **No agent interpreted its failing tests or proofs well enough to find the exploit.** All six saw that users lose money, and all stopped at griefing. The profitable attack on several victims only appeared after a human challenged one agent's "no profit" conclusion. This matters because severity follows impact: griefing is usually rated Medium, a profitable theft High or Critical.
- **Better specifications improved the findings and the fixes.** A fair-deposit property ("a deposit loses at most a few units of value") also catches deposits that receive some shares but still lose value, not only deposits rounded to zero.
- **A counterexample can be misread.** The prover shows a failing state, not the transactions that lead to it, and that state can be impossible. Someone has to recognise which counterexamples are real.
- **Timeouts push you to simplify, and simplifications can hide the bug.** Arithmetic-heavy rules often time out. In one case a simplifying assumption made the rule pass on the vulnerable code too.
- **Where formal verification is strongest:** once a rule is verified, every state satisfies it, which tests can never show. Tracking assets internally can be proved to stop donations from moving the price. A decimals offset only makes the attack more expensive, so there is nothing to prove.
- **Formal verification did not find more than tests in these runs.**

## Follow-up experiment: how low-level do you need to go?

[Experiment 2](experiments/experiment-2-signature-validation/) asks how technical the engineer writing the properties needs to be. The target is a signature-validation bug: a timelock accepts an ERC-1271 signer whose call *reverts* with the magic value as revert data, because the success flag is ignored.

- **The spec can stay high-level.** "A transaction is queued only if an enabled module approved it" catches the bug. It just needs "approved" to mean the module's keys, not "the signer's contract said yes", and an attacker who can deploy any contract.
- **Tests and fuzzing need you to know the bug.** The Foundry tests catch it only because one test uses a signer that reverts with the magic value. Fuzzing with random signer behaviour never found it in 25,000 runs, since it has to hit 4 exact bytes.
- **Formal verification covers this kind of bug more easily, but only with good adversarial modelling.** The prover computed the 4 bytes by itself. But first the call to the signer had to be modelled so that the attack stays possible:
  - an unconstrained signer contract;
  - revert data that reaches the caller.

  A first version of the signer model gave a **green result on the vulnerable code**: the prover never produced the attacking execution, and nothing in the output said so. Whether our optimistic prover settings or a Certora modelling bug caused it is still open.
- **The AI didn't build that model on its own.** In this experiment, the AI assistant writing the CVL got there only after repeated challenges from a human. It made spec mistakes that produced a violation that wasn't the bug, and twice blamed the wrong cause for the green result.

So you don't need to go low-level in the specification, but you do in the model. With tests you must imagine the attack. With formal verification the solver finds it, but only inside a model whose adversarial assumptions someone has deliberately kept open.

## Follow-up: Verity (Lean) instead of Certora

We then tried [Verity](https://github.com/lfglabs-dev/verity) on both experiments ([details and files](experiments/verity/)). Verity works differently from Certora:

- **Certora** compiles the contract and an automatic SMT solver searches the bytecode. Any Solidity works, and the answer is a proof, a counterexample or a timeout.
- **Verity** turns the Solidity source into a Lean model. Properties are Lean theorems, and the proofs are written by a person or an AI and checked by Lean's kernel. There are no timeouts and no counterexamples. Its importer accepts a Solidity construct only after testing that its translation matches what `solc` produces, and rejects everything else.

**Walkthrough:**

1. **Setup.** Verity, Lean, the prebuilt Mathlib library and the pinned `solc` were built locally in about 15 minutes. Proofs are checked on the same machine in seconds; nothing runs on a remote service.
2. **Experiment 2 cannot be imported.** The importer rejects `signer.staticcall(...)` in `SignatureChecker`, which is exactly where the bug lives. Verity models the `STATICCALL` opcode, but not the Solidity statement whose raw result (success flag and returned bytes) the code may use freely. The forms it accepts either check the success flag themselves, which removes the bug, or move the call into assembly.
3. **Experiment 1: the original wrapper does not import fully.** The pricing functions import, including OpenZeppelin's `mulDiv`. The state-changing functions hit two Verity limits:
   - OpenZeppelin's `SafeERC20` reads the token's answer from memory it never wrote, which Verity does not model. Plain `transfer` calls fix it.
   - **Re-entrancy:** a state-changing external call must be a function's last action, because the callee could call back into the contract and the importer does not model that yet. Reordering fixed `wrap`, but `deposit` and `redeem` make several external calls each.
4. **A model contract.** We moved the tToken ledger and the market inside the contract, keeping the vulnerable pricing unchanged. All functions import.
5. **One property proved.** "Depositing then redeeming never returns more than was deposited" is proved for any state, any decimals offset and any rate, in a few lines. In Certora, F0's version of it timed out four times at two hours each.

**Conclusions:**

- **Some properties are proved better with Lean.** Arithmetic with chained rounding, statements for any number of victims, and restricting to reachable states are natural in Lean and caused timeouts or misleading counterexamples in Certora.
- **Some, like experiment 2, are not possible yet.** Bugs in low-level byte handling sit exactly in the constructs Verity's importer rejects. Certora handles them as written.
- **Verity forced code changes; Certora needed models.** Both tools needed the external market modelled: F2 used a `TTokenMock`, and F0's `DISPATCHER` summaries route calls to known code, which in practice assumes no unexpected re-entry. But only Verity required rewriting the contract itself (no `SafeERC20`, calls reordered, the market moved inside), so the proofs are about a model contract, not the original.
- **The property still decides everything.** The proved property holds even in the vulnerable code: it bounds what a depositor can gain, while the bug makes victims get less. The properties that catch the bug (exact attacker profit, fair deposit over reachable states) are the next step and are not proved yet.

## Takeaways: how the development process should change

The traditional process was to write specifications, implement, then test and verify. With AI, implementation is fast and formal verification is easier to adopt than it looks. The effort should shift to specifications and tests:

- **Spend more time on specifications.** Writing them down, even without tools, already reveals many vulnerabilities.
- **Maintain and review them, and make them the hardest part to change.** AI can easily adapt tests to fit the implementation, so the specification must be what anchors it.
- **Use fuzzing and formal verification together, early in development,** not as a final exercise.
- **Keep interpretation and impact analysis with an engineer.** A tool's answer is only as good as the property, the model and the reading of the result.

These were exploratory pilots, one run per condition. They support qualitative conclusions, not success rates or a ranking of tools or models.
