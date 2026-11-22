// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Fixture} from "./utils/Fixture.sol";
import {TimelockModule} from "../src/TimelockModule.sol";
import {
    ApproveAllSigner,
    RevertingMagicSigner,
    RevertingEmptySigner,
    WrongValueSigner,
    SilentSigner
} from "./utils/Signers.sol";

/// Property: a transaction is added to the queue only if a currently-enabled
/// module either called directly, or validly signed exactly that
/// (to, value, data, salt).
///
/// "Rejected" means: the call reverts AND queueNonce does not change.
contract QueueAuthorizationTest is Fixture {
    function setUp() public {
        _deployFixture();
    }

    // -------------------------------------------------------------- helpers

    function _assertQueued(uint256 nonceBefore, address to, uint256 value, bytes memory data) internal view {
        assertEq(timelock.queueNonce(), nonceBefore + 1, "not queued");
        assertEq(timelock.txHash(nonceBefore), timelock.getTransactionHash(to, value, data), "wrong tx queued");
    }

    function _assertDirectRejected(address caller, address to, uint256 value, bytes memory data) internal {
        uint256 before = timelock.queueNonce();
        vm.prank(caller);
        (bool ok,) =
            address(timelock).call(abi.encodeCall(TimelockModule.execTransactionFromModule, (to, value, data)));
        assertTrue(!ok, "call did not revert");
        assertEq(timelock.queueNonce(), before, "unauthorized tx was queued");
    }

    function _assertSignedRejected(address to, uint256 value, bytes memory data, uint256 salt, bytes memory sig)
        internal
    {
        uint256 before = timelock.queueNonce();
        vm.prank(stranger); // anyone can relay
        (bool ok,) = address(timelock).call(
            abi.encodeCall(TimelockModule.execTransactionFromModuleSigned, (to, value, data, salt, sig))
        );
        assertTrue(!ok, "call did not revert");
        assertEq(timelock.queueNonce(), before, "unauthorized tx was queued");
    }

    function _enableModule(address module) internal {
        vm.prank(timelockOwner);
        timelock.enableModule(module);
    }

    // ============================================ A. intended paths work

    function test_directCall_enabledModule_queues() public {
        uint256 before = timelock.queueNonce();
        vm.prank(eoaModule);
        timelock.execTransactionFromModule(recipient, 1 ether, hex"1234");
        _assertQueued(before, recipient, 1 ether, hex"1234");
    }

    function test_signed_enabledEOAModule_queues() public {
        bytes memory sig = _eoaSig(EOA_MODULE_KEY, recipient, 1 ether, hex"1234", 1);
        uint256 before = timelock.queueNonce();
        vm.prank(stranger);
        timelock.execTransactionFromModuleSigned(recipient, 1 ether, hex"1234", 1, sig);
        _assertQueued(before, recipient, 1 ether, hex"1234");
    }

    function test_signed_enabledMultisigModule_queues() public {
        bytes memory auth = _multisigAuth(_twoOwnerKeys(), _digest(recipient, 2 ether, "", 7));
        uint256 before = timelock.queueNonce();
        vm.prank(stranger);
        timelock.execTransactionFromModuleSigned(recipient, 2 ether, "", 7, auth);
        _assertQueued(before, recipient, 2 ether, "");
    }

    // ====================================== B. direct path: who is the caller

    function test_directCall_nonModule_rejected() public {
        _assertDirectRejected(stranger, stranger, 1 ether, "");
    }

    function test_directCall_owner_rejected() public {
        _assertDirectRejected(timelockOwner, stranger, 1 ether, "");
    }

    function test_directCall_disabledModule_rejected() public {
        vm.prank(timelockOwner);
        timelock.disableModule(eoaModule);
        _assertDirectRejected(eoaModule, stranger, 1 ether, "");
    }

    // ========================================== C. signed path: who signed

    function test_signed_nonModuleEOA_rejected() public {
        bytes memory sig = _eoaSig(STRANGER_KEY, stranger, 1 ether, "", 1);
        _assertSignedRejected(stranger, 1 ether, "", 1, sig);
    }

    function test_signed_nonModuleContract_rejected() public {
        ApproveAllSigner fake = new ApproveAllSigner();
        _assertSignedRejected(stranger, 1 ether, "", 1, abi.encodePacked(address(fake), hex"00"));
    }

    function test_signed_disabledModule_rejected() public {
        bytes memory eoaSig = _eoaSig(EOA_MODULE_KEY, stranger, 1 ether, "", 1);
        bytes memory msAuth = _multisigAuth(_twoOwnerKeys(), _digest(stranger, 1 ether, "", 2));
        vm.prank(timelockOwner);
        timelock.disableModule(eoaModule);
        vm.prank(timelockOwner);
        timelock.disableModule(address(multisig));
        _assertSignedRejected(stranger, 1 ether, "", 1, eoaSig);
        _assertSignedRejected(stranger, 1 ether, "", 2, msAuth);
    }

    function test_signed_moduleAddressWithoutCode_rejected() public {
        // An enabled module with no code cannot produce an ERC-1271 signature.
        _assertSignedRejected(stranger, 1 ether, "", 1, abi.encodePacked(eoaModule, hex"00"));
    }

    // ============================ D. signature covers exactly this transaction

    function test_signed_changedTo_rejected() public {
        bytes memory sig = _eoaSig(EOA_MODULE_KEY, recipient, 1 ether, "", 1);
        _assertSignedRejected(stranger, 1 ether, "", 1, sig);
    }

    function test_signed_changedValue_rejected() public {
        bytes memory sig = _eoaSig(EOA_MODULE_KEY, recipient, 1 ether, "", 1);
        _assertSignedRejected(recipient, 50 ether, "", 1, sig);
    }

    function test_signed_changedData_rejected() public {
        bytes memory sig = _eoaSig(EOA_MODULE_KEY, recipient, 0, hex"1234", 1);
        _assertSignedRejected(recipient, 0, hex"5678", 1, sig);
    }

    function test_signed_changedSalt_rejected() public {
        bytes memory sig = _eoaSig(EOA_MODULE_KEY, recipient, 1 ether, "", 1);
        _assertSignedRejected(recipient, 1 ether, "", 2, sig);
    }

    function test_signed_otherTimelockDomain_rejected() public {
        TimelockModule other = new TimelockModule(timelockOwner, COOLDOWN);
        bytes32 otherDigest = _digest(other, recipient, 1 ether, "", 1);
        _assertSignedRejected(recipient, 1 ether, "", 1, _sign(EOA_MODULE_KEY, otherDigest));
        _assertSignedRejected(recipient, 1 ether, "", 1, _multisigAuth(_twoOwnerKeys(), otherDigest));
    }

    function test_signed_otherChainId_rejected() public {
        uint256 chainId = block.chainid;
        vm.chainId(chainId + 1);
        bytes32 otherDigest = _digest(recipient, 1 ether, "", 1);
        bytes memory eoaSig = _sign(EOA_MODULE_KEY, otherDigest);
        bytes memory msAuth = _multisigAuth(_twoOwnerKeys(), otherDigest);
        vm.chainId(chainId);
        _assertSignedRejected(recipient, 1 ether, "", 1, eoaSig);
        _assertSignedRejected(recipient, 1 ether, "", 1, msAuth);
    }

    // ============================ E. multisig owners must actually approve

    function test_multisigSig_belowThreshold_rejected() public {
        uint256[] memory keys = new uint256[](1);
        keys[0] = ownerKeys[0];
        _assertSignedRejected(stranger, 1 ether, "", 1, _multisigAuth(keys, _digest(stranger, 1 ether, "", 1)));
    }

    function test_multisigSig_nonOwnerSigners_rejected() public {
        uint256[] memory keys = new uint256[](2);
        keys[0] = STRANGER_KEY;
        keys[1] = 0x6868;
        _assertSignedRejected(stranger, 1 ether, "", 1, _multisigAuth(keys, _digest(stranger, 1 ether, "", 1)));
        keys[0] = ownerKeys[0]; // one owner + one stranger
        _assertSignedRejected(stranger, 1 ether, "", 1, _multisigAuth(keys, _digest(stranger, 1 ether, "", 1)));
    }

    function test_multisigSig_duplicateOwner_rejected() public {
        bytes32 messageHash = handler.getMessageHash(multisig, _digest(stranger, 1 ether, "", 1));
        bytes memory one = _sign(ownerKeys[0], messageHash);
        bytes memory auth = abi.encodePacked(address(multisig), one, one);
        _assertSignedRejected(stranger, 1 ether, "", 1, auth);
    }

    function test_multisigSig_signedOtherDigest_rejected() public {
        // Owners approve a different transaction; that approval is replayed for this one.
        bytes memory auth = _multisigAuth(_twoOwnerKeys(), _digest(recipient, 1 ether, "", 1));
        _assertSignedRejected(stranger, 1 ether, "", 1, auth);
        // Owners sign the raw digest instead of the multisig message hash.
        bytes memory raw = abi.encodePacked(address(multisig), _sortedSigs(_twoOwnerKeys(), _digest(stranger, 1 ether, "", 1)));
        _assertSignedRejected(stranger, 1 ether, "", 1, raw);
    }

    // ============================ F. contract signers that behave badly

    /// A revert is never a valid signature, whatever its revert data.
    /// (a) The enabled module itself reverts with the magic value.
    function test_erc1271_revertsWithMagicData_moduleItself_rejected() public {
        RevertingMagicSigner m = new RevertingMagicSigner();
        _enableModule(address(m));
        _assertSignedRejected(stranger, 1 ether, "", 1, abi.encodePacked(address(m), hex"00"));
    }

    /// (b) A signer nested in the multisig's signature reverts with the magic value.
    function test_erc1271_revertsWithMagicData_nestedInMultisig_rejected() public {
        RevertingMagicSigner evil = new RevertingMagicSigner();
        _assertSignedRejected(stranger, 1 ether, "", 1, _multisigAuthWithContractEntry(address(evil)));
    }

    function test_erc1271_revertsEmpty_rejected() public {
        RevertingEmptySigner m = new RevertingEmptySigner();
        _enableModule(address(m));
        _assertSignedRejected(stranger, 1 ether, "", 1, abi.encodePacked(address(m), hex"00"));
        _assertSignedRejected(stranger, 1 ether, "", 2, _multisigAuthWithContractEntry(address(m)));
    }

    function test_erc1271_returnsWrongValue_rejected() public {
        WrongValueSigner m = new WrongValueSigner();
        _enableModule(address(m));
        _assertSignedRejected(stranger, 1 ether, "", 1, abi.encodePacked(address(m), hex"00"));
        _assertSignedRejected(stranger, 1 ether, "", 2, _multisigAuthWithContractEntry(address(m)));
    }

    function test_erc1271_returnsNothing_rejected() public {
        SilentSigner m = new SilentSigner();
        _enableModule(address(m));
        _assertSignedRejected(stranger, 1 ether, "", 1, abi.encodePacked(address(m), hex"00"));
        _assertSignedRejected(stranger, 1 ether, "", 2, _multisigAuthWithContractEntry(address(m)));
    }

    function test_erc1271_nonOwnerNestedSigner_rejected() public {
        ApproveAllSigner fake = new ApproveAllSigner();
        _assertSignedRejected(stranger, 1 ether, "", 1, _multisigAuthWithContractEntry(address(fake)));
    }

    // ===================================================== G. fuzz

    function testFuzz_signed_arbitrarySignature_neverQueues(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        bytes calldata signature
    ) public {
        _assertSignedRejected(to, value, data, salt, signature);
    }

    function testFuzz_signed_arbitraryBytesAfterModuleAddress_neverQueues(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        bytes calldata tail
    ) public {
        _assertSignedRejected(to, value, data, salt, abi.encodePacked(address(multisig), tail));
    }
}
