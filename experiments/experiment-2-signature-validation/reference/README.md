# The answer (spoiler)

This folder holds the vulnerability and its fix, kept out of `src/` and `test/`
so the committed suite does not give the bug away. Don't show it to an agent you
want to test.

## The bug

`src/SignatureChecker.sol`, in `_isValidContractSignature`:

```solidity
(, bytes memory returnData) =
    signer.staticcall(abi.encodeWithSelector(IERC1271.isValidSignature.selector, hash, signature));

return bytes4(returnData) == EIP1271_MAGIC_VALUE;
```

The `staticcall` return tuple is `(bool success, bytes returnData)`. The success
flag is dropped. A `staticcall` returns `success = false` when the callee
**reverts**, but it still copies the revert data into `returnData`. So a signer
contract that *reverts* with the 4 bytes `0x1626ba7e` as its revert payload is
read as a valid signature.

## Why it is reachable

`TimelockModule.execTransactionFromModuleSigned` accepts a relayed transaction
if `signedBy(hash, auth)` is an enabled module. The signature layout is
`signer(20 bytes) || contractSignature`. An attacker sets `signer` to the real
operator (an enabled module), which makes `SignatureChecker` call the operator's
`isValidSignature`. That call lands in `MultisigHandler`, which runs the
operator's `checkSignatures`.

`Multisig.checkSignatures` supports contract signatures (`v == 0`): it calls
`IERC1271(currentOwner).isValidSignature(...)` **before** it checks
`isOwner[currentOwner]`. The attacker puts one `v == 0` entry there pointing at
their own contract, which reverts with `0x1626ba7e`. Because it reverts, the
owner check is never reached; the revert data propagates up through the handler
and the multisig's fallback unchanged, back to `SignatureChecker`, which ignores
`success` and accepts it.

Net effect: anyone queues (and after the cooldown, executes) any vault
transaction with **no valid signature at all**. See `Exploit.t.sol`.

This mirrors the June 2026 Zodiac Roles/Delay exploit (Gnosis Pay). The
structure here is deliberately generic — no Safe, no Zodiac — but the shape is
the same: a signature checker that reads `returnData` without checking `success`,
plus a signature-verification path that calls an attacker-chosen contract before
the owner check and lets its revert bubble up.

## The fix

One line, in `_isValidContractSignature`:

```solidity
(bool success, bytes memory returnData) =
    signer.staticcall(abi.encodeWithSelector(IERC1271.isValidSignature.selector, hash, signature));

return success && bytes4(returnData) == EIP1271_MAGIC_VALUE;
```

`reference/SignatureChecker.fixed.sol` has it. The real fix shipped as Zodiac
Roles 2.1.1 / Delay 1.1.1 in June 2026.

## Run the exploit

```bash
cp reference/Exploit.t.sol test/Exploit.t.sol
forge test --match-contract ExploitTest -vvv
rm test/Exploit.t.sol
```

- Against `src/` as committed (V0): the exploit **passes** (attacker drains 5 ether).
- Apply the V1 fix, run again: the exploit **reverts** with `NotAuthorized`.

## The point of the experiment

Both versions — vulnerable and fixed — pass all 22 tests in
`test/Permissions.t.sol`, including the fuzz tests and the cases that reject
non-owner contract signers. The permission model looks complete and correct. The
one-line difference is invisible to the suite, because the whole suite only ever
feeds the checker signers that *return* (valid) or that the multisig rejects by
its own revert (whose revert data is an error string, not the magic value). The
missing-`success`-check case is never exercised. That is the gap a property or a
targeted model has to find.
