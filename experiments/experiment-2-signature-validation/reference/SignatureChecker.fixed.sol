// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * V1 — HIDDEN REFERENCE REPAIR. Not part of the build.
 *
 * This is the fixed version of src/SignatureChecker.sol. The only change is in
 * _isValidContractSignature: the staticcall's success flag is captured and
 * required. See reference/README.md.
 *
 * Apply it by replacing the body of `_isValidContractSignature` in
 * src/SignatureChecker.sol with the version below.
 */

import {IERC1271} from "../src/interfaces/IERC1271.sol";

abstract contract SignatureCheckerFixed {
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    function _isValidContractSignature(address signer, bytes32 hash, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        if (signer.code.length == 0) {
            return false;
        }

        // FIX: capture `success`. staticcall returns `true` on a normal return
        // and `false` on a revert, but puts the revert data in `returnData`
        // either way. Without this check, a signer that reverts with the magic
        // value as its revert payload is accepted as valid.
        (bool success, bytes memory returnData) =
            signer.staticcall(abi.encodeWithSelector(IERC1271.isValidSignature.selector, hash, signature));

        return success && bytes4(returnData) == EIP1271_MAGIC_VALUE;
    }
}
