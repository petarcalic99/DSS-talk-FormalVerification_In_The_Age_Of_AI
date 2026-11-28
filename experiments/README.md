# Experiments

Each folder is one experiment: can AI agents find a known vulnerability with tests or formal verification? Each one contains the target contract, what the agents produced, the reviewer's notes, and a README that explains the setup and results.

| Experiment | Vulnerability | Contents |
|---|---|---|
| [inflation-vulnerability](inflation-vulnerability/) | ERC-4626 donation/inflation attack in a wrapper vault (the experiment behind the DSS 2026 talk) | 6 agent runs (Foundry and Certora, 3 documentation levels), reviewer notes, simplified contract |
| [experiment-2-signature-validation](experiment-2-signature-validation/) | A module-permissioned delay accepts a forged ERC-1271 authorization | The authorization-core contracts |
| [verity](verity/) | Both of the above, with Verity (Lean) instead of Certora | Import attempts, a model contract of the wrapper, and one fully proved property |

## Experiment 2: signature-validation

A timelock module (the "delay") that lets enabled modules queue transactions, either by calling directly or by relaying an EIP-712 signature that the module's `SignatureChecker` verifies against enabled modules (EOA or ERC-1271 contract signatures).

**Property we want to test:** every transaction added to the delay queue was authorized by a currently-enabled module — either that module called directly, or it produced a valid signature over exactly that transaction.

Contrapositive (the testable form): if `msg.sender` is not a currently-enabled module, and no currently-enabled module validly signed the exact `(to, value, data, salt)`, then the transaction is not queued.
