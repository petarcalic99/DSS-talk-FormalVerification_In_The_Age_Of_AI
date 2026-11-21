# Experiments

Each folder is one experiment: can AI agents find a known vulnerability with tests or formal verification? Each one contains the target contract, what the agents produced, the reviewer's notes, and a README that explains the setup and results.

| Experiment | Vulnerability | Contents |
|---|---|---|
| [inflation-vulnerability](inflation-vulnerability/) | ERC-4626 donation/inflation attack in a wrapper vault (the experiment behind the DSS 2026 talk) | 6 agent runs (Foundry and Certora, 3 documentation levels), reviewer notes, simplified contract |
