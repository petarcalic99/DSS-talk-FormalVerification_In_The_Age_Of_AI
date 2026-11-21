# Experiments

Each folder is one experiment: can AI agents find a known vulnerability with tests or formal verification? Each one contains the target contract, what the agents produced, the reviewer's notes, and a README that explains the setup and results.

| Experiment | Vulnerability | Contents |
|---|---|---|
| [inflation-vulnerability](inflation-vulnerability/) | ERC-4626 donation/inflation attack in a wrapper vault (the experiment behind the DSS 2026 talk) | 6 agent runs (Foundry and Certora, 3 documentation levels), reviewer notes, simplified contract |
| [experiment-2-signature-validation](experiment-2-signature-validation/) | Signature-check accepts a forged ERC-1271 authorization — a dropped `staticcall` success flag (modelled on the June 2026 Zodiac/Gnosis Pay exploit) | Runnable Foundry target: vulnerable contracts, a 22-test permission suite that passes on both the vulnerable and fixed code, and the bug/fix/exploit in `reference/` |
