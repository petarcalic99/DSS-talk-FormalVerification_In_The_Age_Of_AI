// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SpectraWrappedTakara} from "../../src/takara/SpectraWrappedTakara.sol";

/// @dev Exposes a few view helpers for the spec. Adds no state and changes no behaviour.
contract SpectraWrappedTakaraHarness is SpectraWrappedTakara {
    /// @dev USDC value of one whole share (the "price" in the README).
    function sharePrice() external view returns (uint256) {
        return convertToAssets(10 ** decimals());
    }

    function decimalsOffsetHarness() external view returns (uint8) {
        return _decimalsOffset();
    }
}
