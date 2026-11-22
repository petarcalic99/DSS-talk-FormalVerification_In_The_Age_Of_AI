// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "./Test.sol";
import {TimelockModule} from "../../src/TimelockModule.sol";
import {Multisig} from "../../src/Multisig.sol";
import {MultisigHandler} from "../../src/MultisigHandler.sol";

/// Setup shared by the unit and invariant tests: a TimelockModule with two
/// enabled modules, an EOA and a 2-of-3 Multisig with ERC-1271 support.
///
/// The test oracle for "validly signed" is independent of SignatureChecker:
///   - EOA module: the module's own key signed this timelock's EIP-712 digest.
///   - Multisig module: at least `threshold` distinct owners signed
///     handler.getMessageHash(multisig, digest).
abstract contract Fixture is Test {
    uint256 internal constant COOLDOWN = 1 days;
    uint256 internal constant EOA_MODULE_KEY = 0xE0A;
    uint256 internal constant STRANGER_KEY = 0x5757;

    TimelockModule internal timelock;
    MultisigHandler internal handler;
    Multisig internal multisig;

    address internal timelockOwner;
    address internal eoaModule;
    address internal stranger = address(0xBAD);
    address internal recipient = address(0xBEEF);

    uint256[3] internal ownerKeys; // sorted by address
    address[3] internal owners;

    function _deployFixture() internal {
        uint256[3] memory keys = [uint256(0xA11CE), uint256(0xB0B), uint256(0xC4A11)];
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                if (vm.addr(keys[j]) < vm.addr(keys[i])) (keys[i], keys[j]) = (keys[j], keys[i]);
            }
        }
        address[] memory ownerList = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            ownerKeys[i] = keys[i];
            owners[i] = vm.addr(keys[i]);
            ownerList[i] = owners[i];
        }

        handler = new MultisigHandler();
        multisig = new Multisig(ownerList, 2, address(handler));

        timelockOwner = vm.addr(0xD00D);
        eoaModule = vm.addr(EOA_MODULE_KEY);
        timelock = new TimelockModule(timelockOwner, COOLDOWN);

        vm.prank(timelockOwner);
        timelock.enableModule(eoaModule);
        vm.prank(timelockOwner);
        timelock.enableModule(address(multisig));

        vm.deal(address(timelock), 100 ether);
        vm.warp(1_000_000);
    }

    // ------------------------------------------------------------- signing

    function _sign(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _digest(TimelockModule tl, address to, uint256 value, bytes memory data, uint256 salt)
        internal
        view
        returns (bytes32)
    {
        return tl.hashTypedData(tl.moduleTxStructHash(to, value, data, salt));
    }

    function _digest(address to, uint256 value, bytes memory data, uint256 salt) internal view returns (bytes32) {
        return _digest(timelock, to, value, data, salt);
    }

    /// EOA-module signature (65 bytes) over the module transaction.
    function _eoaSig(uint256 key, address to, uint256 value, bytes memory data, uint256 salt)
        internal
        view
        returns (bytes memory)
    {
        return _sign(key, _digest(to, value, data, salt));
    }

    /// Owner signatures over `messageHash`, from the given keys, sorted by signer address.
    function _sortedSigs(uint256[] memory keys, bytes32 messageHash) internal pure returns (bytes memory sigs) {
        for (uint256 i = 0; i < keys.length; i++) {
            for (uint256 j = i + 1; j < keys.length; j++) {
                if (vm.addr(keys[j]) < vm.addr(keys[i])) (keys[i], keys[j]) = (keys[j], keys[i]);
            }
        }
        for (uint256 i = 0; i < keys.length; i++) {
            sigs = abi.encodePacked(sigs, _sign(keys[i], messageHash));
        }
    }

    /// Multisig ERC-1271 authorization: `multisig || owner signatures over the message hash`.
    function _multisigAuth(uint256[] memory keys, bytes32 digest) internal view returns (bytes memory) {
        bytes32 messageHash = handler.getMessageHash(multisig, digest);
        return abi.encodePacked(address(multisig), _sortedSigs(keys, messageHash));
    }

    function _twoOwnerKeys() internal view returns (uint256[] memory keys) {
        keys = new uint256[](2);
        keys[0] = ownerKeys[0];
        keys[1] = ownerKeys[1];
    }

    /// Multisig "signature" whose first entry is a contract signature (v = 0)
    /// naming `signer`, followed by a zero entry and an empty dynamic part.
    /// Valid only if `signer` is an owner and approves; here it never is.
    function _multisigAuthWithContractEntry(address signer) internal view returns (bytes memory) {
        bytes memory contractEntry = abi.encodePacked(bytes32(uint256(uint160(signer))), uint256(130), uint8(0));
        bytes memory padding = new bytes(65);
        return abi.encodePacked(address(multisig), contractEntry, padding, uint256(0));
    }
}
