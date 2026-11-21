// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {SpectraWrappedTakara} from "../munged/SpectraWrappedTakara.sol";

/// @dev Exposes the wrapper's internal rate math to CVL. No behavior is changed.
contract SpectraWrappedTakaraHarness is SpectraWrappedTakara {
    function currentExchangeRate() external view returns (uint256) {
        return _currentExchangeRate();
    }

    function divScalarByExpTruncate(uint256 scalar, uint256 e) external pure returns (uint256) {
        return _divScalarByExpTruncate(scalar, e);
    }

    function mulScalarTruncate(uint256 e, uint256 scalar) external pure returns (uint256) {
        return _mulScalarTruncate(e, scalar);
    }
}
