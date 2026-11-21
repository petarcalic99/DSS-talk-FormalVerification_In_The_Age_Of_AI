# Experiment 2: a signature-validation bug behind a correct-looking permission system

A self-contained Foundry project modelling a module-permissioned vault. The
access control looks complete and passes a full test suite, but one function
accepts a forged authorization. The task for an agent is the same as in
experiment 1: find the bug with tests or formal verification.

> **The vulnerability is real and runnable.** This is not an archive of agent
> runs (yet) — it is the target. The code compiles and the tests pass as
> committed. The bug and its fix live in [`reference/`](reference/), kept out of
> the build so the committed suite doesn't reveal them. **Don't show `reference/`
> to an agent you want to test.**
>
> The contracts are a simplified, renamed model of the system behind the June
> 2026 Zodiac Roles/Delay exploit (Gnosis Pay). No Safe, no Zodiac, no external
> dependencies — but the mechanism and the bug are the same.

## The system

A vault holds funds. A timelock module queues transactions for it; after a
cooldown anyone can execute them. Only **enabled modules** may queue. A module
can act in two ways:

- **directly**, by calling `execTransactionFromModule` (checked by `msg.sender`); or
- **by signature**, by signing an EIP-712 authorization that anyone relays
  through `execTransactionFromModuleSigned`.

The signed path accepts both EOA signatures and **ERC-1271 contract signatures**,
so a module can itself be a smart-contract wallet. In this setup the one enabled
module is a 2-of-3 multisig (the "operator").

| Contract | Role |
|---|---|
| [`Vault.sol`](src/Vault.sol) | Holds funds; only its module can move them. |
| [`TimelockModule.sol`](src/TimelockModule.sol) | Queues and executes module transactions after a cooldown. |
| [`ModuleAuth.sol`](src/ModuleAuth.sol) | Module registry; the `moduleOnly` / `moduleOnlySigned` checks. |
| [`SignatureChecker.sol`](src/SignatureChecker.sol) | Recovers the signer of a digest (EOA or ERC-1271). |
| [`Multisig.sol`](src/Multisig.sol) | An M-of-N wallet used as the enabled module. |
| [`MultisigHandler.sol`](src/MultisigHandler.sol) | Fallback handler giving the multisig ERC-1271 support. |
| [`interfaces/IERC1271.sol`](src/interfaces/IERC1271.sol) | The ERC-1271 interface. |

## The test suite

[`test/Permissions.t.sol`](test/Permissions.t.sol) — 22 tests, all passing.
They cover the direct path, the signed path, replay protection, admin controls,
nested contract owners, and two fuzz tests that throw random bytes at the signed
path. They assert the things you would expect of a permission system:

- a non-module cannot queue;
- a disabled module cannot queue;
- the multisig needs its threshold of real owner signatures;
- a non-owner signer — EOA **or contract** — is rejected;
- an authorization cannot be replayed or modified;
- random signatures are rejected.

Everything passes. Nothing in the suite is wrong. The bug is in a case the suite
never constructs.

## Run it

Foundry only; there are no dependencies to install.

```bash
cd experiments/experiment-2-signature-validation
forge test
```

Expected: `22 passed; 0 failed`.

## The bug (spoiler)

In [`reference/`](reference/): the one-line root cause, why it is reachable, the
fix, and an `Exploit.t.sol` that drains the vault with no signature. Both the
vulnerable and the fixed code pass all 22 tests, so the fix is invisible to the
suite — which is the whole point.

## Relation to experiment 1

Same question, different vulnerability class. Experiment 1 is an arithmetic /
value bug (ERC-4626 inflation); here it is an authorization bug (a dropped
success flag on an external call). Experiment 1's README explains the method
(plain-language properties → tests / CVL → a report mapping each property to its
result) and how to run an isolated agent session. The intended property here is
roughly:

> `execTransactionFromModuleSigned` succeeds only if `msg.sender` is an enabled
> module, or an enabled module genuinely authorized this exact transaction.

A model where the external ERC-1271 signer may **revert with arbitrary data**
(not only return) should expose the counterexample on the committed code and
prove it on the fixed code.
