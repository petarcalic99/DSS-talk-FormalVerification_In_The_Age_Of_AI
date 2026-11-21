// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Multisig} from "./Multisig.sol";

/// @title MultisigHandler
/// @notice Fallback handler that gives a Multisig ERC-1271 support. The
///         Multisig forwards unknown calls here, so `msg.sender` is the wallet.
contract MultisigHandler {
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;
    bytes32 private constant MESSAGE_TYPEHASH = keccak256("MultisigMessage(bytes32 hash)");

    /// @notice ERC-1271: valid if the wallet's owners signed `getMessageHash(wallet, hash)`.
    /// @dev Reverts if the signatures are invalid.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        Multisig wallet = Multisig(payable(msg.sender));
        wallet.checkSignatures(getMessageHash(wallet, hash), signature);
        return EIP1271_MAGIC_VALUE;
    }

    /// @notice The digest a wallet's owners sign to approve `hash`.
    function getMessageHash(Multisig wallet, bytes32 hash) public view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(MESSAGE_TYPEHASH, hash));
        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), wallet.domainSeparator(), structHash));
    }
}
