# Certora setup

**Status: the rule catches the bug.** It is violated on the current code and verified with the one-line fix. Every violation is the attack: the module reverts with data starting with `0x1626ba7e`. The prover chose those bytes itself; nothing in the spec or the harness mentions them.

## Run

From the experiment folder (needs `CERTORAKEY` and `solc-0.8.24` on the PATH):

```
certora/munge.sh
certoraRun certora/conf/QueueAuthorization.conf
```

## The rule

`specs/QueueAuthorization.spec`, rule `signedQueueRequiresModuleApproval`:

> If a transaction is queued through an enabled module's signature, the module really approved that transaction.

- `harness/ModuleSigner.sol` models the enabled module, a contract wallet.
  - `approved` is the ground truth: the hashes it really approved.
  - For any other hash, the prover chooses how `isValidSignature` answers: return any value except the magic value, or revert with any 32 bytes.
- `harness/TimelockHarness.sol` routes every contract signature to that model, and relays `signer || tail`, because CVL can't concatenate bytes.
- `munge.sh` copies `src/` to `munged/` (git-ignored) and changes one line, explained below.

## What it took: three modelling choices

The property didn't change. What changed was how the call to the signer is modelled. Each wrong choice made the prover either miss the bug or raise false alarms.

1. **Routing the call: hard-code the signer's address.**
   - `SignatureChecker` slices the signer's address out of the signature bytes. The prover can't follow an address taken from symbolic bytes, so the call stays unresolved.
   - The usual fixes failed:
     - With a summary (`DISPATCHER`), a reverting signer never led to a queued transaction, so the bug was hidden.
     - With no summary or `NONDET`, the call returned anything, so the rule also failed on the fixed code.
   - The fix: `munge.sh` makes `SignatureChecker` read the address through a virtual function, and the harness returns the linked model.
   - The function where the bug is, `_isValidContractSignature`, is not touched.
2. **Revert data length: fixed at 32 bytes.**
   - With a prover-chosen length, the prover lost track of the revert data and the rule passed on the vulnerable code.
3. **No fallback.**
   - Certora doesn't run a callee's `fallback` by default (`optimistic_fallback`). The model therefore uses a named `isValidSignature`.

## Certora behaviour we confirmed

- **When a call is resolved to a contract in the scene, revert data is modelled correctly.** We checked this with a separate 10-line contract: the caller sees `success = false` and the exact revert bytes.
- **The documentation doesn't say how revert data is handled.** It is silent for both resolved and summarized calls. CVL call hooks expose the return code, but can't read return data.
- **The documentation says `DISPATCHER` should behave like a normal call.** What we observed (a reverting dispatched call never leading to a queued transaction) doesn't match that. It may be worth reporting to Certora.

## Spec mistakes found along the way

- Declaring `hashTypedData` `envfree` let the rule use a different chain ID from the real call.
- A first version of `ModuleSigner` used assembly that the prover modelled imprecisely.
