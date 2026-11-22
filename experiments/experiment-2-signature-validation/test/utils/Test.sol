// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev The few Foundry cheatcodes these tests use, so the project needs no dependencies.
interface Vm {
    function addr(uint256 privateKey) external pure returns (address);
    function sign(uint256 privateKey, bytes32 digest) external pure returns (uint8 v, bytes32 r, bytes32 s);
    function warp(uint256 timestamp) external;
    function prank(address sender) external;
    function deal(address account, uint256 balance) external;
    function chainId(uint256 newChainId) external;
}

abstract contract Test {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 a, uint256 b, string memory err) internal pure {
        require(a == b, err);
    }

    function assertEq(bytes32 a, bytes32 b, string memory err) internal pure {
        require(a == b, err);
    }

    function assertTrue(bool ok, string memory err) internal pure {
        require(ok, err);
    }
}
