// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "./utils/Test.sol";
import {Vault} from "../src/Vault.sol";
import {TimelockModule} from "../src/TimelockModule.sol";
import {ModuleAuth} from "../src/ModuleAuth.sol";
import {Multisig} from "../src/Multisig.sol";
import {MultisigHandler} from "../src/MultisigHandler.sol";
import {IERC1271} from "../src/interfaces/IERC1271.sol";

/// @dev A contract signer that approves everything.
contract ApproveAllSigner is IERC1271 {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return 0x1626ba7e;
    }
}

/// Setup: a Vault controlled by a TimelockModule. The only enabled module is a
/// 2-of-3 Multisig (the "operator"). The operator queues payments, either by
/// calling the timelock itself or by signing an authorization that anyone relays.
contract PermissionsTest is Test {
    uint256 constant COOLDOWN = 1 days;

    MultisigHandler handler;
    Multisig operator;
    Vault vault;
    TimelockModule timelock;

    address vaultOwner;
    address recipient = address(0xBEEF);
    address stranger = address(0xBAD);

    uint256[3] ownerKeys; // sorted by address
    address[3] owners;

    function setUp() public {
        uint256[3] memory keys = [uint256(0xA11CE), uint256(0xB0B), uint256(0xC4A11)];
        // sort keys by address (the multisig expects ascending signers)
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
        operator = new Multisig(ownerList, 2, address(handler));

        vaultOwner = vm.addr(0xD00D);
        vault = new Vault(vaultOwner);
        timelock = new TimelockModule(vaultOwner, vault, COOLDOWN);

        vm.prank(vaultOwner);
        vault.setModule(address(timelock));
        vm.prank(vaultOwner);
        timelock.enableModule(address(operator));

        vm.deal(address(vault), 10 ether);
        vm.warp(1_000_000);
    }

    // ------------------------------------------------------------------ helpers

    function _sign(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    /// Signatures from owners[0] and owners[1] (2-of-3), in ascending order.
    function _ownerSigs(bytes32 digest) internal view returns (bytes memory) {
        return abi.encodePacked(_sign(ownerKeys[0], digest), _sign(ownerKeys[1], digest));
    }

    function _operatorExec(address to, bytes memory data) internal {
        bytes32 h = operator.getTransactionHash(to, 0, data, operator.nonce());
        operator.execTransaction(to, 0, data, _ownerSigs(h));
    }

    function _queueCall(address to, uint256 value, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodeCall(TimelockModule.execTransactionFromModule, (to, value, data));
    }

    function _moduleDigest(address to, uint256 value, bytes memory data, uint256 salt)
        internal
        view
        returns (bytes32)
    {
        return timelock.hashTypedData(timelock.moduleTxStructHash(to, value, data, salt));
    }

    /// Operator's ERC-1271 authorization for a relayed module transaction.
    function _operatorAuthorization(address to, uint256 value, bytes memory data, uint256 salt)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = handler.getMessageHash(operator, _moduleDigest(to, value, data, salt));
        return abi.encodePacked(address(operator), _ownerSigs(messageHash));
    }

    // ------------------------------------------------- direct module path

    function test_moduleQueuesAndAnyoneExecutesAfterCooldown() public {
        _operatorExec(address(timelock), _queueCall(recipient, 1 ether, ""));
        assertEq(timelock.queueNonce(), 1, "not queued");

        vm.warp(block.timestamp + COOLDOWN);
        vm.prank(stranger);
        timelock.executeNextTx(recipient, 1 ether, "");

        assertEq(recipient.balance, 1 ether, "recipient not paid");
        assertEq(address(vault).balance, 9 ether, "vault balance");
    }

    function test_cannotExecuteBeforeCooldown() public {
        _operatorExec(address(timelock), _queueCall(recipient, 1 ether, ""));
        vm.warp(block.timestamp + COOLDOWN - 1);
        vm.expectRevert(TimelockModule.CooldownNotOver.selector);
        timelock.executeNextTx(recipient, 1 ether, "");
    }

    function test_cannotExecuteDifferentTransaction() public {
        _operatorExec(address(timelock), _queueCall(recipient, 1 ether, ""));
        vm.warp(block.timestamp + COOLDOWN);
        vm.expectRevert(TimelockModule.WrongTransaction.selector);
        timelock.executeNextTx(stranger, 1 ether, "");
    }

    function test_nonModuleCannotQueue() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ModuleAuth.NotAuthorized.selector, stranger));
        timelock.execTransactionFromModule(stranger, 1 ether, "");
    }

    function test_operatorNeedsTwoOwnerSignatures() public {
        bytes memory data = _queueCall(stranger, 1 ether, "");
        bytes32 h = operator.getTransactionHash(address(timelock), 0, data, operator.nonce());
        vm.expectRevert(bytes("MS01: signatures too short"));
        operator.execTransaction(address(timelock), 0, data, _sign(ownerKeys[0], h));
    }

    function test_operatorRejectsDuplicateSigner() public {
        bytes memory data = _queueCall(stranger, 1 ether, "");
        bytes32 h = operator.getTransactionHash(address(timelock), 0, data, operator.nonce());
        bytes memory sigs = abi.encodePacked(_sign(ownerKeys[0], h), _sign(ownerKeys[0], h));
        vm.expectRevert(bytes("MS05: invalid owner"));
        operator.execTransaction(address(timelock), 0, data, sigs);
    }

    function test_operatorRejectsNonOwnerSigner() public {
        bytes memory data = _queueCall(stranger, 1 ether, "");
        bytes32 h = operator.getTransactionHash(address(timelock), 0, data, operator.nonce());
        uint256 strangerKey = 0x5757;
        bytes memory a = _sign(ownerKeys[0], h);
        bytes memory b = _sign(strangerKey, h);
        bytes memory sigs = owners[0] < vm.addr(strangerKey) ? abi.encodePacked(a, b) : abi.encodePacked(b, a);
        vm.expectRevert(bytes("MS05: invalid owner"));
        operator.execTransaction(address(timelock), 0, data, sigs);
    }

    function test_operatorRejectsNonOwnerContractSigner() public {
        ApproveAllSigner fake = new ApproveAllSigner();
        bytes memory data = _queueCall(stranger, 1 ether, "");
        bytes32 h = operator.getTransactionHash(address(timelock), 0, data, operator.nonce());
        // one contract-signature entry (v = 0) pointing at `fake`, with an empty dynamic part
        bytes memory contractEntry = abi.encodePacked(bytes32(uint256(uint160(address(fake)))), uint256(130), uint8(0));
        bytes memory ownerEntry = _sign(ownerKeys[0], h);
        bytes memory sigs = owners[0] < address(fake)
            ? abi.encodePacked(ownerEntry, contractEntry, uint256(0))
            : abi.encodePacked(contractEntry, ownerEntry, uint256(0));
        vm.expectRevert(bytes("MS05: invalid owner"));
        operator.execTransaction(address(timelock), 0, data, sigs);
    }

    // -------------------------------------------------- signed module path

    function test_relayedAuthorizationFromModuleIsAccepted() public {
        bytes memory auth = _operatorAuthorization(recipient, 2 ether, "", 1);
        vm.prank(stranger); // anyone can relay
        timelock.execTransactionFromModuleSigned(recipient, 2 ether, "", 1, auth);

        vm.warp(block.timestamp + COOLDOWN);
        timelock.executeNextTx(recipient, 2 ether, "");
        assertEq(recipient.balance, 2 ether, "recipient not paid");
    }

    function test_relayedAuthorizationCannotBeReplayed() public {
        bytes memory auth = _operatorAuthorization(recipient, 1 ether, "", 7);
        timelock.execTransactionFromModuleSigned(recipient, 1 ether, "", 7, auth);
        bytes32 digest = _moduleDigest(recipient, 1 ether, "", 7);
        vm.expectRevert(abi.encodeWithSelector(ModuleAuth.HashAlreadyConsumed.selector, digest));
        timelock.execTransactionFromModuleSigned(recipient, 1 ether, "", 7, auth);
    }

    function test_relayedAuthorizationCannotBeModified() public {
        bytes memory auth = _operatorAuthorization(recipient, 1 ether, "", 1);
        vm.expectRevert(abi.encodeWithSelector(ModuleAuth.NotAuthorized.selector, stranger));
        vm.prank(stranger);
        timelock.execTransactionFromModuleSigned(stranger, 10 ether, "", 1, auth);
    }

    function test_relayedAuthorizationNeedsThreshold() public {
        bytes32 messageHash = handler.getMessageHash(operator, _moduleDigest(stranger, 1 ether, "", 1));
        bytes memory auth = abi.encodePacked(address(operator), _sign(ownerKeys[0], messageHash));
        vm.expectRevert(abi.encodeWithSelector(ModuleAuth.NotAuthorized.selector, stranger));
        vm.prank(stranger);
        timelock.execTransactionFromModuleSigned(stranger, 1 ether, "", 1, auth);
    }

    function test_relayedAuthorizationFromStrangerKeysRejected() public {
        bytes32 messageHash = handler.getMessageHash(operator, _moduleDigest(stranger, 1 ether, "", 1));
        bytes memory auth =
            abi.encodePacked(address(operator), _sign(0x5757, messageHash), _sign(0x6868, messageHash));
        vm.expectRevert(abi.encodeWithSelector(ModuleAuth.NotAuthorized.selector, stranger));
        vm.prank(stranger);
        timelock.execTransactionFromModuleSigned(stranger, 1 ether, "", 1, auth);
    }

    function test_strangerEOASignatureRejected() public {
        bytes memory auth = _sign(0x5757, _moduleDigest(stranger, 1 ether, "", 1));
        vm.expectRevert(abi.encodeWithSelector(ModuleAuth.NotAuthorized.selector, stranger));
        vm.prank(stranger);
        timelock.execTransactionFromModuleSigned(stranger, 1 ether, "", 1, auth);
    }

    function test_approveAllContractIsNotAModule() public {
        ApproveAllSigner fake = new ApproveAllSigner();
        bytes memory auth = abi.encodePacked(address(fake), hex"00");
        vm.expectRevert(abi.encodeWithSelector(ModuleAuth.NotAuthorized.selector, stranger));
        vm.prank(stranger);
        timelock.execTransactionFromModuleSigned(stranger, 1 ether, "", 1, auth);
    }

    function test_disabledModuleAuthorizationRejected() public {
        vm.prank(vaultOwner);
        timelock.disableModule(address(operator));
        bytes memory auth = _operatorAuthorization(recipient, 1 ether, "", 1);
        vm.expectRevert(abi.encodeWithSelector(ModuleAuth.NotAuthorized.selector, address(this)));
        timelock.execTransactionFromModuleSigned(recipient, 1 ether, "", 1, auth);
    }

    // ------------------------------------------------------------ admin

    function test_ownerCanCancelQueuedTransaction() public {
        _operatorExec(address(timelock), _queueCall(recipient, 1 ether, ""));
        vm.prank(vaultOwner);
        timelock.setTxNonce(1);
        vm.warp(block.timestamp + COOLDOWN);
        vm.expectRevert(TimelockModule.NothingQueued.selector);
        timelock.executeNextTx(recipient, 1 ether, "");
    }

    function test_onlyOwnerManagesModules() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ModuleAuth.NotOwner.selector, stranger));
        timelock.enableModule(stranger);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ModuleAuth.NotOwner.selector, stranger));
        timelock.setTxNonce(1);
    }

    function test_onlyTimelockCanMoveVaultFunds() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Vault.NotModule.selector, stranger));
        vault.execTransactionFromModule(stranger, 1 ether, "");
    }

    // ------------------------------------------- contract owners (nesting)

    function test_multisigOwnedByAnotherMultisig() public {
        // inner: 1-of-1 multisig; outer: 2-of-2 with one EOA owner and the inner multisig
        address[] memory innerOwners = new address[](1);
        innerOwners[0] = owners[0];
        Multisig inner = new Multisig(innerOwners, 1, address(handler));

        address[] memory outerOwners = new address[](2);
        outerOwners[0] = owners[1];
        outerOwners[1] = address(inner);
        Multisig outer = new Multisig(outerOwners, 2, address(handler));
        vm.deal(address(outer), 1 ether);

        bytes32 h = outer.getTransactionHash(recipient, 1 ether, "", 0);
        bytes memory innerSig = _sign(ownerKeys[0], handler.getMessageHash(inner, h));

        bytes memory eoaEntry = _sign(ownerKeys[1], h);
        bytes memory contractEntry =
            abi.encodePacked(bytes32(uint256(uint160(address(inner)))), uint256(130), uint8(0));
        bytes memory dynamicPart = abi.encodePacked(uint256(innerSig.length), innerSig);
        bytes memory sigs = owners[1] < address(inner)
            ? abi.encodePacked(eoaEntry, contractEntry, dynamicPart)
            : abi.encodePacked(contractEntry, eoaEntry, dynamicPart);

        outer.execTransaction(recipient, 1 ether, "", sigs);
        assertEq(recipient.balance, 1 ether, "nested approval failed");
    }

    // ---------------------------------------------------------------- fuzz

    /// Random bytes never authorize a relayed transaction.
    function testFuzz_randomSignatureRejected(bytes calldata signature, uint256 salt) public {
        vm.expectRevert(abi.encodeWithSelector(ModuleAuth.NotAuthorized.selector, address(this)));
        timelock.execTransactionFromModuleSigned(stranger, 1 ether, "", salt, signature);
    }

    /// Random bytes presented as the operator's contract signature never authorize.
    function testFuzz_randomOperatorSignatureRejected(bytes calldata tail, uint256 salt) public {
        bytes memory auth = abi.encodePacked(address(operator), tail);
        vm.expectRevert(abi.encodeWithSelector(ModuleAuth.NotAuthorized.selector, address(this)));
        timelock.execTransactionFromModuleSigned(stranger, 1 ether, "", salt, auth);
    }
}
