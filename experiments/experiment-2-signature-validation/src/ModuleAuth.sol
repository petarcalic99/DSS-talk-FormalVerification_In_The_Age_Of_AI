// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SignatureChecker} from "./SignatureChecker.sol";

/// @title ModuleAuth
/// @notice Registry of enabled modules. A module can call protected functions
///         directly, or sign an authorization that anyone can relay.
abstract contract ModuleAuth is SignatureChecker {
    address public owner;
    mapping(address => bool) public isModuleEnabled;
    /// @notice signer => digest => used. Each signed authorization works once.
    mapping(address => mapping(bytes32 => bool)) public consumed;

    event ModuleEnabled(address indexed module);
    event ModuleDisabled(address indexed module);
    event HashExecuted(address indexed signer, bytes32 indexed hash);

    error NotOwner(address caller);
    error NotAuthorized(address caller);
    error HashAlreadyConsumed(bytes32 hash);

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    /// @dev Direct call by an enabled module.
    modifier moduleOnly() {
        if (!isModuleEnabled[msg.sender]) revert NotAuthorized(msg.sender);
        _;
    }

    /// @dev Relayed call carrying an EIP-712 signature from an enabled module.
    modifier moduleOnlySigned(bytes32 structHash, bytes calldata signature) {
        bytes32 hash = hashTypedData(structHash);
        address signer = signedBy(hash, signature);
        if (signer == address(0) || !isModuleEnabled[signer]) revert NotAuthorized(msg.sender);
        if (consumed[signer][hash]) revert HashAlreadyConsumed(hash);
        consumed[signer][hash] = true;
        emit HashExecuted(signer, hash);
        _;
    }

    function enableModule(address module) external onlyOwner {
        isModuleEnabled[module] = true;
        emit ModuleEnabled(module);
    }

    function disableModule(address module) external onlyOwner {
        isModuleEnabled[module] = false;
        emit ModuleDisabled(module);
    }
}
