# Certora setup (work in progress)

**Status: the rule does not catch the bug yet.** Every way we modelled the signer call either hid the bug or also failed on the fixed code.

## The rule

`specs/QueueAuthorization.spec`, rule `signedQueueRequiresModuleApproval`:

> If a transaction is queued through an enabled module's signature, the module really approved that transaction.

- `harness/ModuleSigner.sol` models the enabled module, a contract wallet.
  - `approved` is the ground truth: the hashes the module really approved.
  - For any other hash, the prover chooses how `isValidSignature` answers: return any value except the magic value, or revert with any data of up to 32 bytes.
- `harness/TimelockHarness.sol` adds one helper to relay `signer || tail`, because CVL can't concatenate bytes.

Nothing in the spec or the harness describes the attack. The prover would have to find it.

Run it from the experiment folder (needs `CERTORAKEY` and `solc-0.8.24` on the PATH):

```
certoraRun certora/conf/QueueAuthorization.conf
```

## What we observed

`SignatureChecker` calls the module with a low-level `staticcall`, to an address read from the signature bytes. The prover can't resolve that call by itself, so it has to be modelled. Each of the four options we tried got the revert data wrong:

| How the call is modelled | Vulnerable code | Fixed code | Diagnosis |
|---|---|---|---|
| `DISPATCHER(true)` (committed) | passes | passes | The call reaches `ModuleSigner`. But a reachability check shows a reverting module can never lead to a queued transaction, which is wrong on a real chain. **The summary hides the bug.** |
| No summary | violated | violated | The call isn't resolved. It may return anything, including a normal return of the magic value. False alarm. |
| `unresolved external … DISPATCH […] default NONDET` | violated | violated | Same as no summary. |
| `unresolved external … DISPATCH(optimistic=true) […]` | violated | violated | A reverting module can queue even on the fixed code, which is impossible. False alarm. |

Two problems with the spec were found and fixed along the way:
1. Declaring `hashTypedData` `envfree` let the rule use a different chain ID from the real call.
2. A first version of `ModuleSigner` used assembly that the prover modelled imprecisely.

## What this means for the experiment

This is the "model and assumptions" step from the talk. The property is fine, and the prover's solver could in principle compute the attacker's input. But the call that carries the bug has to be modelled, and the summaries we tried either drop revert data or make the result meaningless.

So far, formal verification needs the same knowledge as testing: you have to know that the revert data of that call matters before you can check that the model keeps it.

## Next steps

- Ask Certora, or check their documentation, how summarized low-level calls handle reverts and revert data.
- Find a way to resolve the `staticcall` to `ModuleSigner` without a summary.
