// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Vault
/// @notice Holds funds. The owner controls it directly; one module (the
///         timelock) can also make it execute transactions.
contract Vault {
    address public owner;
    address public module;

    error NotOwner(address caller);
    error NotModule(address caller);

    constructor(address _owner) {
        owner = _owner;
    }

    receive() external payable {}

    function setModule(address _module) external {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        module = _module;
    }

    function execTransactionFromModule(address to, uint256 value, bytes calldata data)
        external
        returns (bool success)
    {
        if (msg.sender != module) revert NotModule(msg.sender);
        (success,) = to.call{value: value}(data);
    }
}
