// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {SpectraWrappedTakara} from "../../src/takara/SpectraWrappedTakara.sol";

/// @dev Candidate fix 1: revert when a deposit would mint zero shares.
contract WrapperRevertZeroShares is SpectraWrappedTakara {
    error ZeroShares();

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        if (previewDeposit(assets) == 0) revert ZeroShares();
        return super.deposit(assets, receiver);
    }
}

/// @dev Candidate fix 2: 10**6 virtual shares (OpenZeppelin's inflation-attack defence).
contract WrapperOffset6 is SpectraWrappedTakara {
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }
}
