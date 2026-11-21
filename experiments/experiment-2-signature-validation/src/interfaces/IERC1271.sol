// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice ERC-1271: standard signature validation for contracts.
interface IERC1271 {
    /// @return magicValue 0x1626ba7e if the signature is valid for `hash`.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue);
}
