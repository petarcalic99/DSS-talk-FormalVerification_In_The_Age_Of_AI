// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @title TTokenMock - verification model of a Takara (Compound v2) tToken
/// @dev Keeps the parts of TToken the wrapper depends on:
///  - the exchange rate (underlying per tToken, x1e18) is already accrued for the current block
///    (`accrualBlockTimestamp() == block.timestamp`), so the wrapper's `_currentExchangeRate()`
///    reads `exchangeRateStored()` directly; interest is modelled by `accrue`, which can only raise
///    the rate (Takara is trusted per the README);
///  - `mint` / `redeem` use exactly `Exponential.divScalarByExpTruncate` / `mulScalarTruncate`.
contract TTokenMock is ERC20 {
    uint256 private constant EXP_SCALE = 1e18;

    address public underlying;
    uint256 public exchangeRateStored;
    uint256 public totalBorrows;
    uint256 public totalReserves;
    uint256 public reserveFactorMantissa;
    address public interestRateModel;

    constructor() ERC20("Takara USDC", "tUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function accrualBlockTimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    function getCash() external view returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    }

    function accrueInterest() external pure returns (uint256) {
        return 0;
    }

    function exchangeRateCurrent() external view returns (uint256) {
        return exchangeRateStored;
    }

    /// @dev Interest accrual: the exchange rate never decreases.
    function accrue(uint256 newRate) external {
        require(newRate >= exchangeRateStored);
        exchangeRateStored = newRate;
    }

    function mint(uint256 mintAmount) external returns (uint256) {
        IERC20(underlying).transferFrom(msg.sender, address(this), mintAmount);
        uint256 mintTokens = (mintAmount * EXP_SCALE * EXP_SCALE / exchangeRateStored) / EXP_SCALE;
        _mint(msg.sender, mintTokens);
        return 0;
    }

    function redeem(uint256 redeemTokens) external returns (uint256) {
        uint256 redeemAmount = exchangeRateStored * redeemTokens / EXP_SCALE;
        _burn(msg.sender, redeemTokens);
        IERC20(underlying).transfer(msg.sender, redeemAmount);
        return 0;
    }

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256) {
        uint256 redeemTokens = (redeemAmount * EXP_SCALE * EXP_SCALE / exchangeRateStored) / EXP_SCALE;
        _burn(msg.sender, redeemTokens);
        IERC20(underlying).transfer(msg.sender, exchangeRateStored * redeemTokens / EXP_SCALE);
        return 0;
    }
}
