// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TimelockModule} from "../../src/TimelockModule.sol";

/// @notice TimelockModule plus one helper, because CVL cannot concatenate bytes.
contract TimelockHarness is TimelockModule {
    constructor(address _owner, uint256 _cooldown) TimelockModule(_owner, _cooldown) {}

    /// Relays a contract signature: `signer || tail`, the ERC-1271 layout
    /// SignatureChecker expects.
    function relayContractSignature(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        address signer,
        bytes calldata tail
    ) external {
        this.execTransactionFromModuleSigned(to, value, data, salt, abi.encodePacked(signer, tail));
    }
}
