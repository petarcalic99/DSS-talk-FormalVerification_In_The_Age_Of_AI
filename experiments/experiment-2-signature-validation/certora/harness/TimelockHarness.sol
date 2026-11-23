// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TimelockModule} from "../munged/TimelockModule.sol";

/// @notice TimelockModule for the prover. Generate certora/munged/ first with certora/munge.sh.
contract TimelockHarness is TimelockModule {
    /// The contract signer is fixed to the model wallet (linked in the conf).
    address public signerModel;

    constructor(address _owner, uint256 _cooldown) TimelockModule(_owner, _cooldown) {}

    /// The contract signer is always the linked model wallet, so the prover
    /// knows which contract the staticcall goes to.
    function _contractSigner(bytes calldata) internal view override returns (address) {
        return signerModel;
    }

    /// Relays a contract signature `signer || tail`. CVL cannot concatenate bytes.
    function relayContractSignature(address to, uint256 value, bytes calldata data, uint256 salt, bytes calldata tail)
        external
    {
        this.execTransactionFromModuleSigned(to, value, data, salt, abi.encodePacked(signerModel, tail));
    }
}
