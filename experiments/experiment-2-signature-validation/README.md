# Experiment 2: signature validation

## Setup

A timelock queues transactions for later execution. Enabled modules queue them in one of two ways: by calling the timelock directly, or by signing an authorization that anyone can relay. A module can be an EOA or a contract wallet. Contract signatures are checked with ERC-1271: the timelock calls the signer's `isValidSignature`, which must answer with the magic value `0x1626ba7e`.

The contracts in `src/`:
- `TimelockModule`: the queue.
- `ModuleAuth`: the module registry.
- `SignatureChecker`: recovers the signer, for EOA and ERC-1271 signatures.
- `Multisig` and `MultisigHandler`: a 2-of-3 wallet with ERC-1271 support.

**Property:** a transaction is added to the queue only if a currently-enabled module either called directly, or validly signed exactly that `(to, value, data, salt)`.

## The bug

`SignatureChecker` calls the signer with `staticcall`, ignores whether the call succeeded, and checks only the bytes that come back. When a call reverts, the EVM still hands the caller the revert data, through the same return-data area that a normal return uses. A signer that **reverts** with the magic value as its revert data is therefore accepted as valid.

The attack:
1. Name the enabled multisig as the signer.
2. In its signature, include a "contract owner" entry pointing at the attacker's contract.
3. That contract reverts with the magic value. The revert passes up through the multisig unchanged and reaches `SignatureChecker`, which reads it as "valid".

Result: the transaction is queued, and runs after the cooldown, with **no owner signature at all**.

The fix is one line: `return success && bytes4(returnData) == EIP1271_MAGIC_VALUE;`

## The tests

`test/QueueAuthorization.t.sol` contains 28 tests derived from the property. The file's header comment lists what each section covers.

| Code | Result |
|---|---|
| Current `src/` | 26 pass, **2 fail** |
| `src/` with the fix | 28 pass |

The two failing tests are `test_erc1271_revertsWithMagicData_*`. Both use a signer that reverts with the magic value.

Run them with `forge test`. No dependencies are needed.

## What we learned: the property is fine, the method is the problem

The property catches the bug: the exploit queues a transaction that no enabled module authorized. It needs two things made explicit:
- "Validly signed" means **the keys behind the module approved it**. For the multisig, that's a threshold of owner keys. It does not mean "the module's contract said yes", because that would trust the code being tested.
- **The attacker** holds no keys, but can deploy any contract and pass any bytes. Any external contract called during validation may return or revert with any data.

Neither point requires knowing about the bug.

**With tests and fuzzing, finding the bug requires already knowing it.**
- The failing tests exist only because someone thought of "a signer that reverts with the magic value".
- Blind fuzzing doesn't get there. We tried a fuzz test (not committed) with a signer whose behaviour was fuzzer-chosen: return or revert, with arbitrary bytes. In 25,000 runs over 5 seeds it never found the bug. Given the right input by hand, the same test failed immediately.
- The fuzzer must choose to revert *and* get the first 4 bytes exactly right: about 1 chance in 8 billion per input.
- Two other suites passed on the vulnerable code: an earlier 22-test permission suite, and the "random signature" fuzz tests in this file.

**With formal verification, the solver computed the input instead of guessing it.**
- The Certora rule in [certora/](certora/) states the property: if a transaction is queued through a module's signature, the module approved it.
- The signer model only says: "when the module hasn't approved, it may return any non-approval value or revert with any bytes".
- The prover found the attack by itself: it chose revert data starting with `0x1626ba7e`. The rule is violated on the current code and verified with the fix.

**But it only worked after getting the model of the signer call right**, and each wrong choice either hid the bug or produced false alarms (details in [certora/README.md](certora/README.md)):
- **Routing the call to the model.** Certora's usual summary (`DISPATCHER`) hid the bug. With no summary, the call could return anything, so the rule also failed on the fixed code. We had to hard-code the signer's address (one munged line, outside the buggy function).
- **Revert data of variable length.** The prover lost track of it and missed the bug, so the model reverts with exactly 32 bytes.
- **Our own spec mistakes**, which produced a violation that wasn't the bug: an `envfree` declaration that let the chain ID differ, and assembly the prover modelled imprecisely.

To get there, we had to check that the model keeps one specific behaviour: a failed call hands its revert data back to the caller. Knowing which behaviour to check is close to knowing the bug.

**Conclusion:** the property can stay at a high level, and for this bug the prover does what fuzzing can't: it computes the 4 bytes nobody told it about. The expertise doesn't disappear, though. With tests and fuzzing, the engineer has to **imagine the attack**. With formal verification, they have to **build a model that keeps the attack possible**, and recognise false alarms and silent passes along the way.
