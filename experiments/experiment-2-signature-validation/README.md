# Experiment 2: signature validation

## Setup

A timelock (`src/TimelockModule.sol`) queues transactions from enabled modules. A module either calls directly, or signs an authorization that anyone can relay. Contract wallets sign through ERC-1271: their `isValidSignature` must answer with the magic value `0x1626ba7e`.

**Property:** a transaction is queued only if a currently-enabled module called directly, or validly signed exactly that `(to, value, data, salt)`.

## The bug

`SignatureChecker` ignores the `staticcall` success flag and reads only the returned bytes. A reverted call still hands its revert data back to the caller, so a signer that **reverts with the magic value** counts as valid. An attacker names the enabled multisig as the signer and puts a contract that reverts this way inside its signature. The transaction is queued with no owner signature.

Fix: `return success && bytes4(returnData) == EIP1271_MAGIC_VALUE;`

## Results

| | Current code | With the fix |
|---|---|---|
| Foundry, `test/QueueAuthorization.t.sol` (28 tests) | 2 fail (the revert-with-magic tests) | all pass |
| Certora, `certora/` rule | violated | verified |

- Run the tests with `forge test`.
- Run the prover with `certoraRun certora/conf/QueueAuthorization.conf` (needs `CERTORAKEY`).

## What we learned

**The property is fine.** It needs two things made explicit:
- "Validly signed" means the module's keys approved, not "the signer's contract said yes".
- The attacker can deploy any contract.

**Tests and fuzzing need the bug already in mind.**
- The two failing tests exist because someone thought of "revert with the magic value".
- A fuzz test with a signer that returns or reverts with random bytes never found it in 25,000 runs. It would need to hit 4 exact bytes, about 1 in 8 billion per input.

**The prover computed the bytes, once the model was right.**
- The CVL rule only says that the module never approved. The signer model only says that it may return any non-approval value or revert with any bytes.
- The prover then found the revert data `0x1626ba7e…` by itself.
- **But a first version of the signer model gave a green result on the vulnerable code.** It reverted from a freshly allocated buffer with a prover-chosen length (`revert(add(reason, 32), len)`). With it, the prover never produced the execution "signer reverts with the magic value and `SignatureChecker` reads it", so the rule held and Certora reported it verified. The sanity check didn't flag it, because it only checks that *some* execution reaches the assertion.
- Reverting with a fixed 32 bytes made the prover find the attack. An allocated buffer alone (in this setup) and a prover-chosen length alone (in a small test contract) are both modelled correctly. Only the combination failed.
- **Why is still open:** either our optimistic settings (`optimistic_loop` with `loop_iter: 2`, `optimistic_hashing`) silently dropped the attacking execution, which is documented behaviour, or it's a Certora modelling bug. A run with those settings off will decide.
- Along the way, the AI assistant twice blamed the wrong cause: first Certora's `DISPATCHER` summary, then the variable length alone. Both were ruled out by isolated runs. The final setup uses `DISPATCHER` on the unmodified source.

**Conclusion:** with tests, the engineer must **imagine the attack**. With formal verification, the solver finds the attack, but the engineer must **build a model that keeps it possible**. Here that meant checking that a failed call's revert data reaches the caller, which is close to knowing the bug.
