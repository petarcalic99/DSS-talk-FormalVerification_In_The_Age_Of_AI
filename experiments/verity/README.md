# Verity (Lean) on experiments 1 and 2

We tried [Verity](https://github.com/lfglabs-dev/verity) on both experiments and compared it with Certora. Verity is a framework in Lean 4: a contract becomes a Lean model, properties are Lean theorems, and the proofs are written by a person or an AI and checked by Lean's kernel. Verity's Solidity importer generates that model from Solidity source.

> **Status: partial.** Experiment 2 cannot be imported. For experiment 1, a model contract imports in full and one property (round trips never gain) is fully proved over the contract's formulas. The bridge theorem linking those formulas to the imported contract is not written yet, and the properties that catch the bug are planned, not proved.

## How Verity differs from Certora

| | Certora | Verity |
|---|---|---|
| Input | the compiled bytecode, so any Solidity works | a Lean model of the source; the importer accepts only constructs it has validated |
| Proof | automatic SMT solver: verified, counterexample or timeout | written in Lean (by hand or AI), checked by the kernel; no counterexample, no timeout |
| Where it runs | Certora's servers | locally |
| External calls | modelled by the user (summaries, mocks) | a callee may return or revert with any bytes; state-changing calls must come last |

**Why the importer rejects code.** A theorem about the model says something about the contract only if each translated construct behaves byte for byte like the code `solc` emits. `solc` is not verified, so Verity checks each construct with differential and mutation tests, admits them one validated shape at a time, and rejects everything else with `outside this slice`. A rejection means "not validated yet", not "impossible".

## Setup

Everything ran in one cloud container (4 cores):

- Verity at commit `a10dcd4` (26 Nov 2026), Lean 4.31.0, the prebuilt Mathlib cache, and the importer's pinned `solc` 0.8.34.
- Building the importer and its dependencies took about 15 minutes. Afterwards, an import takes seconds and checking the proofs takes a few seconds.

To reproduce, copy this folder's `wrapper/` and `lean/` into a Verity checkout at that commit (for experiment 2, also copy `../experiment-2-signature-validation/src` to `exp2/src`), then:

```bash
python3 scripts/setup_solc_import.py --version 0.8.34
lake exe cache get
lake build Compiler.SolidityImport.Import
lake env lean lean/RoundTrip.lean
```

## Experiment 2: not importable

[`lean/Exp2Import.lean`](lean/Exp2Import.lean) fails at `SignatureChecker.sol:60`, the `signer.staticcall(...)` that returns `(bool, bytes memory)`:

```
external contract calls are outside this slice
closure: TimelockModule.execTransactionFromModuleSigned -> ModuleAuth.moduleOnlySigned
         -> SignatureChecker.signedBy -> SignatureChecker._isValidContractSignature
```

The `STATICCALL` opcode itself is modelled. What is missing is the Solidity statement around it, whose raw result the code may use freely. The bug is one such free use (ignore the success flag, read the revert bytes). The forms Verity accepts are a typed interface call, which checks success itself and so removes the bug (and also rejects the `bytes` argument), or inline assembly. Certora handles this contract as written because it reads the bytecode, where `STATICCALL` is one more opcode.

## Experiment 1: import, blockers, model contract

### Import of the original contract

The experiment 1 wrapper ([`../inflation-vulnerability/contracts/`](../inflation-vulnerability/contracts/)) with OpenZeppelin 5.4.0. We removed one blocker at a time:

| Step | Change | Result | Cause |
|---|---|---|---|
| 0 | none | previews and `totalVaultShares` import, including OpenZeppelin's `Math.mulDiv`; `wrap`, `unwrap`, `deposit`, `redeem` fail in `SafeERC20` | Verity does not model memory that `solc` left behind. `SafeERC20`'s assembly reads the token's answer from scratch memory it did not write |
| 1 | `safeTransfer*` → plain `transfer*` | `unwrap` imports; `wrap`, `deposit`, `redeem` fail: "interactions after an external CALL" | Verity has no re-entrancy model in the importer: a state-changing external call must be the function's last action |
| 2 | `wrap` mints shares first, then pulls tTokens | `wrap` imports; `deposit`, `redeem` still fail | they make 2 to 4 external calls each, so no reordering fits |

Using the return value of a state-changing call (`require(tToken.mint(assets) == 0)`) was not a blocker.

**Re-entrancy.** After a state-changing call, unknown code can call back into the wrapper and change its storage. Translating the next lines as if that never happened would let you prove false theorems, so the importer refuses. Verity's own language has a `nonreentrant` guard for this, and its proof library supports bounded re-entrancy, but the Solidity importer does not use them yet. Functions written checks-effects-interactions style, with one call at the end, import fine.

**Did Certora need the same?** Partly. Both tools needed the external world modelled: F0 summarised the market's calls with `DISPATCHER` and `NONDET`, and F2 replaced the market with `TTokenMock`. `DISPATCHER` routes calls to known code, which in practice assumes no unexpected re-entry. But Certora never required changing the contract's code: no removal of `SafeERC20`, no reordering (F0's harness only exposed private math). Verity did.

### Model contract

[`wrapper/src/WrapperModel.sol`](wrapper/src/WrapperModel.sol) keeps the vulnerable pricing exactly (shares priced from the raw tToken balance, so a donation moves the price) and simplifies the plumbing:

- the tToken ledger, the asset ledger and the market are internal, so there are no external calls;
- `Math.mulDiv` becomes plain checked arithmetic (it differs only above 2^256);
- the market rate is fixed (the simplified contract accrues no interest), with Compound's floor rounding on mint and redeem;
- `donate(t)` is an explicit function; the offset is a deployment parameter (`virtualShares = 10^k`).

All ten functions import ([`lean/Model.lean`](lean/Model.lean)). It is the same kind of simplification as Certora's `TTokenMock`, and it is a model for proving properties, not the audited code.

## Properties

We chose properties where Certora struggled in experiment 1:

| # | Property | Certora in experiment 1 | Status |
|---|---|---|---|
| 1 | Exact attacker payout for any donation and any number of zero-share victims; profit ⇔ `a·Σx ≥ a+d+1` | `P8d` witness: timeout | planned |
| 2 | With offset k, no profit from at most 10^k zero-share victims (k = 0: one victim is only griefing; k = 6: over a million needed) | offset 6 only tested | planned |
| 3 | Fair deposit over reachable states: shares never exceed backing; without donations deposits are fair; a donation breaks it | counterexamples from unreachable states (F2 witness, V1 calibration) | planned |
| 4 | A round trip never gains, from any state | F0 `P9`: 4 × 2 h timeouts; F2 S13: timeout | **proved** |

### Property 4, proved

[`lean/RoundTrip.lean`](lean/RoundTrip.lean) holds two theorems:

- `wrap_unwrap_no_gain`: wrap then unwrap never returns more tTokens than wrapped.
- `deposit_redeem_no_gain`: deposit then redeem never returns more assets than deposited, including the market's two roundings.

Both hold for any state, any offset and any rate. `#print axioms` lists only Lean's three standard axioms, with no `sorryAx`. The proof is short because the argument is short: the wrap rounds down, so `s·(V+1) ≤ t·(S+10^k)`; adding `s·t` to both sides gives exactly what the unwrap needs. The person (or AI) supplies that idea and Lean checks the steps, while Certora's solver had to search for it over 256-bit numbers.

Two caveats:

- **Not like for like.** F0's `P9` ran on the real lending market code with interest; ours is over the model's formulas with a fixed rate.
- **It does not detect the bug.** Property 4 bounds what a depositor can gain. The donation bug makes victims get less, down to zero, which still satisfies it. Properties 1 to 3 are the ones about the bug.

## What we concluded

- **Arithmetic properties suit Lean.** The property that cost Certora eight hours of timeouts is a few lines of proof here, holds for any state, and cannot time out. Lean can also state "for any number of victims" and restrict theorems to reachable states, both of which hurt in experiment 1.
- **Low-level byte handling does not suit Verity's importer, for now.** Experiment 2 cannot be imported, and the only accepted rewrites either remove the bug or move it into assembly. Certora handled it as written.
- **The importer forces code changes.** External library assembly (`SafeERC20`) and the lack of a re-entrancy model meant we proved properties of a model contract, not the original. Certora also needed the external world modelled, but not the contract rewritten.
- **The property still decides everything.** Property 4 is proved and blind to the bug. In Lean as in Certora, a proof says exactly what its statement says.
- **No counterexamples.** When a Lean theorem is false, the proof simply does not go through. Exposing the bug means stating and proving a counterexample theorem yourself.
