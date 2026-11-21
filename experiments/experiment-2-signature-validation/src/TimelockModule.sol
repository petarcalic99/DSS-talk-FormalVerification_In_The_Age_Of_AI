// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ModuleAuth} from "./ModuleAuth.sol";

/// @title TimelockModule
/// @notice Enabled modules queue transactions. After `cooldown` seconds anyone
///         can execute them, in order. The owner can cancel queued transactions
///         before they run. The module executes the queued call itself.
contract TimelockModule is ModuleAuth {
    bytes32 public constant MODULE_TX_TYPEHASH =
        keccak256("ModuleTx(address to,uint256 value,bytes data,uint256 salt)");

    uint256 public immutable cooldown;

    /// @notice Index of the next transaction to execute.
    uint256 public txNonce;
    /// @notice Index the next queued transaction will get.
    uint256 public queueNonce;
    mapping(uint256 => bytes32) public txHash;
    mapping(uint256 => uint256) public txCreatedAt;

    event TransactionQueued(uint256 indexed index, address to, uint256 value, bytes data);
    event TransactionExecuted(uint256 indexed index);

    error NothingQueued();
    error CooldownNotOver();
    error WrongTransaction();
    error ExecutionFailed();
    error InvalidNonce();

    constructor(address _owner, uint256 _cooldown) ModuleAuth(_owner) {
        cooldown = _cooldown;
    }

    receive() external payable {}

    /// @notice Called by an enabled module to queue a transaction.
    function execTransactionFromModule(address to, uint256 value, bytes calldata data) external moduleOnly {
        _enqueue(to, value, data);
    }

    /// @notice Queues a transaction authorized by an enabled module's signature.
    ///         Anyone can relay it.
    function execTransactionFromModuleSigned(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        bytes calldata signature
    ) external moduleOnlySigned(moduleTxStructHash(to, value, data, salt), signature) {
        _enqueue(to, value, data);
    }

    /// @notice Executes the next queued transaction once its cooldown is over.
    function executeNextTx(address to, uint256 value, bytes calldata data) external {
        uint256 index = txNonce;
        if (index >= queueNonce) revert NothingQueued();
        if (block.timestamp - txCreatedAt[index] < cooldown) revert CooldownNotOver();
        if (txHash[index] != getTransactionHash(to, value, data)) revert WrongTransaction();

        txNonce = index + 1;
        (bool ok,) = to.call{value: value}(data);
        if (!ok) revert ExecutionFailed();
        emit TransactionExecuted(index);
    }

    /// @notice Cancels every queued transaction below `newTxNonce`.
    function setTxNonce(uint256 newTxNonce) external onlyOwner {
        if (newTxNonce <= txNonce || newTxNonce > queueNonce) revert InvalidNonce();
        txNonce = newTxNonce;
    }

    function moduleTxStructHash(address to, uint256 value, bytes calldata data, uint256 salt)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(MODULE_TX_TYPEHASH, to, value, keccak256(data), salt));
    }

    function getTransactionHash(address to, uint256 value, bytes calldata data) public pure returns (bytes32) {
        return keccak256(abi.encode(to, value, keccak256(data)));
    }

    function _enqueue(address to, uint256 value, bytes calldata data) internal {
        uint256 index = queueNonce++;
        txHash[index] = getTransactionHash(to, value, data);
        txCreatedAt[index] = block.timestamp;
        emit TransactionQueued(index, to, value, data);
    }
}
