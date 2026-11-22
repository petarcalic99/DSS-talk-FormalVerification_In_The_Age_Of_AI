// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Fixture} from "./utils/Fixture.sol";
import {TimelockModule} from "../src/TimelockModule.sol";
import {Multisig} from "../src/Multisig.sol";
import {MultisigHandler} from "../src/MultisigHandler.sol";
import {
    ApproveAllSigner,
    RevertingMagicSigner,
    RevertingEmptySigner,
    WrongValueSigner,
    SilentSigner
} from "./utils/Signers.sol";

/// The fuzzer drives this handler. Before each call, the handler decides with
/// its own oracle whether the call is authorized (independent of
/// SignatureChecker). After the call, it records any queued transaction the
/// oracle did not authorize.
contract QueueHandler is Fixture {
    address[5] internal badSigners;

    uint256 public authorizedQueued;
    uint256 public unauthorizedQueued;

    constructor(
        TimelockModule _timelock,
        MultisigHandler _handler,
        Multisig _multisig,
        address _timelockOwner,
        uint256[3] memory _ownerKeys
    ) {
        timelock = _timelock;
        handler = _handler;
        multisig = _multisig;
        timelockOwner = _timelockOwner;
        eoaModule = vm.addr(EOA_MODULE_KEY);
        ownerKeys = _ownerKeys;
        for (uint256 i = 0; i < 3; i++) {
            owners[i] = vm.addr(_ownerKeys[i]);
        }
        badSigners = [
            address(new ApproveAllSigner()),
            address(new RevertingMagicSigner()),
            address(new RevertingEmptySigner()),
            address(new WrongValueSigner()),
            address(new SilentSigner())
        ];
    }

    // ------------------------------------------------------------ bookkeeping

    function _record(uint256 before, bool authorized, address to, uint256 value, bytes memory data) internal {
        uint256 afterNonce = timelock.queueNonce();
        if (afterNonce == before) return;
        bool exact = afterNonce == before + 1 && timelock.txHash(before) == timelock.getTransactionHash(to, value, data);
        if (authorized && exact) authorizedQueued += afterNonce - before;
        else unauthorizedQueued += afterNonce - before;
    }

    function _relay(address to, uint256 value, bytes memory data, uint256 salt, bytes memory sig, bool authorized)
        internal
    {
        uint256 before = timelock.queueNonce();
        vm.prank(stranger);
        (bool ok,) = address(timelock).call(
            abi.encodeCall(TimelockModule.execTransactionFromModuleSigned, (to, value, data, salt, sig))
        );
        ok;
        _record(before, authorized, to, value, data);
    }

    // ---------------------------------------------------------------- actions

    /// Admin: enable or disable one of the two real modules.
    function toggleModule(bool useMultisig, bool enable) external {
        address m = useMultisig ? address(multisig) : eoaModule;
        vm.prank(timelockOwner);
        if (enable) timelock.enableModule(m);
        else timelock.disableModule(m);
    }

    /// Direct call by an enabled module, a disabled module, or a stranger.
    function directQueue(uint8 callerSeed, address to, uint256 value, bytes calldata data) external {
        address caller = callerSeed % 3 == 0 ? eoaModule : callerSeed % 3 == 1 ? address(multisig) : stranger;
        bool authorized = timelock.isModuleEnabled(caller);
        uint256 before = timelock.queueNonce();
        vm.prank(caller);
        (bool ok,) =
            address(timelock).call(abi.encodeCall(TimelockModule.execTransactionFromModule, (to, value, data)));
        ok;
        _record(before, authorized, to, value, data);
    }

    /// EOA signature from the module key or a stranger key, over this tx or another one.
    function signedEOA(bool moduleKey, bool signOtherTx, address to, uint256 value, bytes calldata data, uint256 salt)
        external
    {
        uint256 key = moduleKey ? EOA_MODULE_KEY : STRANGER_KEY;
        bytes32 signedDigest = signOtherTx ? _digest(to, value, data, salt ^ 1) : _digest(to, value, data, salt);
        bool authorized = moduleKey && !signOtherTx && timelock.isModuleEnabled(eoaModule);
        _relay(to, value, data, salt, _sign(key, signedDigest), authorized);
    }

    /// Multisig authorization signed by any subset of owners and/or a stranger.
    function signedMultisig(uint8 signerMask, bool signOtherTx, address to, uint256 value, bytes calldata data, uint256 salt)
        external
    {
        uint256 n;
        for (uint256 i = 0; i < 4; i++) {
            if (signerMask & (1 << i) != 0) n++;
        }
        if (n == 0) return;
        uint256[] memory keys = new uint256[](n);
        uint256 ownerCount;
        uint256 k;
        for (uint256 i = 0; i < 4; i++) {
            if (signerMask & (1 << i) == 0) continue;
            if (i < 3) {
                keys[k++] = ownerKeys[i];
                ownerCount++;
            } else {
                keys[k++] = STRANGER_KEY;
            }
        }
        bytes32 signedDigest = signOtherTx ? _digest(to, value, data, salt ^ 1) : _digest(to, value, data, salt);
        // Oracle: threshold (2) distinct owners approved exactly this tx, and the multisig is enabled.
        bool authorized = ownerCount >= 2 && !signOtherTx && timelock.isModuleEnabled(address(multisig));
        _relay(to, value, data, salt, _multisigAuth(keys, signedDigest), authorized);
    }

    /// Multisig "signature" with a contract entry pointing at a misbehaving signer. Never authorized.
    function signedMultisigBadNestedSigner(uint8 signerSeed, address to, uint256 value, bytes calldata data, uint256 salt)
        external
    {
        address signer = badSigners[signerSeed % badSigners.length];
        _relay(to, value, data, salt, _multisigAuthWithContractEntry(signer), false);
    }

    /// Arbitrary signature bytes. Never authorized.
    function signedArbitrary(bool prefixMultisig, address to, uint256 value, bytes calldata data, uint256 salt, bytes calldata sig)
        external
    {
        bytes memory s = prefixMultisig ? abi.encodePacked(address(multisig), sig) : sig;
        _relay(to, value, data, salt, s, false);
    }
}

contract QueueAuthorizationInvariantTest is Fixture {
    QueueHandler internal queueHandler;

    function setUp() public {
        _deployFixture();
        queueHandler = new QueueHandler(timelock, handler, multisig, timelockOwner, ownerKeys);
    }

    /// Only the handler is fuzzed.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(queueHandler);
    }

    /// Every queued transaction was authorized by a currently-enabled module,
    /// directly or by a valid signature over exactly that transaction.
    function invariant_everyQueuedTxWasAuthorized() public view {
        assertEq(queueHandler.unauthorizedQueued(), 0, "an unauthorized transaction was queued");
    }

    /// The queue only grows through authorized calls.
    function invariant_queueOnlyGrowsThroughAuthorizedCalls() public view {
        assertEq(timelock.queueNonce(), queueHandler.authorizedQueued(), "queue grew without authorization");
    }
}
