// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC1271} from "./interfaces/IERC1271.sol";

/// @title Multisig
/// @notice An M-of-N wallet. Calls to unknown functions go to a fallback
///         handler (for example, ERC-1271 support).
contract Multisig {
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    // keccak256("EIP712Domain(uint256 chainId,address verifyingContract)")
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;
    bytes32 private constant TX_TYPEHASH =
        keccak256("MultisigTx(address to,uint256 value,bytes data,uint256 nonce)");

    mapping(address => bool) public isOwner;
    uint256 public immutable threshold;
    address public immutable fallbackHandler;
    uint256 public nonce;

    constructor(address[] memory owners, uint256 _threshold, address _fallbackHandler) {
        require(_threshold > 0 && _threshold <= owners.length, "MS00: bad threshold");
        for (uint256 i = 0; i < owners.length; i++) {
            require(owners[i] != address(0) && !isOwner[owners[i]], "MS00: bad owner");
            isOwner[owners[i]] = true;
        }
        threshold = _threshold;
        fallbackHandler = _fallbackHandler;
    }

    receive() external payable {}

    /// @notice Executes a call approved by `threshold` owners.
    function execTransaction(address to, uint256 value, bytes calldata data, bytes memory signatures)
        external
        returns (bool success)
    {
        bytes32 txHash = getTransactionHash(to, value, data, nonce);
        nonce++;
        checkSignatures(txHash, signatures);
        (success,) = to.call{value: value}(data);
        require(success, "MS10: call failed");
    }

    /// @notice Reverts unless `signatures` holds `threshold` valid owner signatures for `dataHash`.
    /// @dev `signatures` is a list of 65-byte entries `r || s || v`, sorted by owner address.
    ///      - v != 0: ECDSA signature.
    ///      - v == 0: contract signature. `r` is the signer contract and `s` is the offset,
    ///        inside `signatures`, of `uint256 length || bytes signature`.
    function checkSignatures(bytes32 dataHash, bytes memory signatures) public view {
        uint256 required = threshold;
        require(signatures.length >= required * 65, "MS01: signatures too short");

        address lastOwner = address(0);
        address currentOwner;
        for (uint256 i = 0; i < required; i++) {
            (uint8 v, bytes32 r, bytes32 s) = _signatureSplit(signatures, i);
            if (v == 0) {
                currentOwner = address(uint160(uint256(r)));
                uint256 offset = uint256(s);
                require(offset >= required * 65, "MS02: bad offset");
                require(offset + 32 <= signatures.length, "MS03: out of bounds");
                uint256 len;
                bytes memory contractSignature;
                assembly {
                    len := mload(add(add(signatures, offset), 0x20))
                    contractSignature := add(add(signatures, offset), 0x20)
                }
                require(offset + 32 + len <= signatures.length, "MS03: out of bounds");
                require(
                    IERC1271(currentOwner).isValidSignature(dataHash, contractSignature) == EIP1271_MAGIC_VALUE,
                    "MS04: invalid contract signature"
                );
            } else {
                currentOwner = ecrecover(dataHash, v, r, s);
            }
            require(currentOwner > lastOwner && isOwner[currentOwner], "MS05: invalid owner");
            lastOwner = currentOwner;
        }
    }

    function domainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_TYPEHASH, block.chainid, address(this)));
    }

    function getTransactionHash(address to, uint256 value, bytes calldata data, uint256 _nonce)
        public
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(TX_TYPEHASH, to, value, keccak256(data), _nonce));
        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator(), structHash));
    }

    /// @dev Forwards unknown calls to the fallback handler and returns its result.
    fallback() external payable {
        address handler = fallbackHandler;
        assembly {
            if iszero(handler) { return(0, 0) }
            calldatacopy(0, 0, calldatasize())
            let success := call(gas(), handler, 0, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(success) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }

    function _signatureSplit(bytes memory signatures, uint256 pos)
        internal
        pure
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        assembly {
            let p := mul(0x41, pos)
            r := mload(add(signatures, add(p, 0x20)))
            s := mload(add(signatures, add(p, 0x40)))
            v := and(mload(add(signatures, add(p, 0x41))), 0xff)
        }
    }
}
