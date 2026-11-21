// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC1271} from "./interfaces/IERC1271.sol";

/// @title SignatureChecker
/// @notice Recovers the signer of an EIP-712 digest. Supports EOA signatures
///         and ERC-1271 contract signatures.
abstract contract SignatureChecker {
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    // keccak256("EIP712Domain(uint256 chainId,address verifyingContract)")
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

    function domainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_TYPEHASH, block.chainid, address(this)));
    }

    function hashTypedData(bytes32 structHash) public view returns (bytes32) {
        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator(), structHash));
    }

    /// @notice Recovers the signer of `hash`.
    /// @dev Signature layout:
    ///      - EOA:      `r || s || v`                  (65 bytes)
    ///      - ERC-1271: `signer || contractSignature`  (signature[0:20] = signer)
    ///      A 65-byte signature is tried as an EOA signature first.
    /// @return signer The signer, or address(0) if the signature is invalid.
    function signedBy(bytes32 hash, bytes calldata signature) internal view returns (address signer) {
        if (signature.length < 20) {
            return address(0);
        }

        if (signature.length == 65) {
            bytes32 r = bytes32(signature[0:32]);
            bytes32 s = bytes32(signature[32:64]);
            uint8 v = uint8(signature[64]);
            signer = ecrecover(hash, v, r, s);
            if (signer != address(0)) {
                return signer;
            }
        }

        signer = address(bytes20(signature[0:20]));
        return _isValidContractSignature(signer, hash, signature[20:]) ? signer : address(0);
    }

    /// @dev Asks the signer contract whether the signature is valid for the hash.
    function _isValidContractSignature(address signer, bytes32 hash, bytes calldata signature)
        private
        view
        returns (bool)
    {
        if (signer.code.length == 0) {
            return false;
        }

        (, bytes memory returnData) =
            signer.staticcall(abi.encodeWithSelector(IERC1271.isValidSignature.selector, hash, signature));

        return bytes4(returnData) == EIP1271_MAGIC_VALUE;
    }
}
