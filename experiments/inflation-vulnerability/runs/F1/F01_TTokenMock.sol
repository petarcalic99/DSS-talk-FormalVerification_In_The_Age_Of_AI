// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @dev Verification model of a Takara (Compound v2) tToken. It reproduces the arithmetic of
/// lib/takara/src/TToken.sol (accrueInterest, exchangeRateStoredInternal, mintFresh, redeemFresh)
/// and the Comptroller gates that can reject a mint or redeem (guardian pause, supply cap, cash).
/// It is also its own interest rate model (`getBorrowRate` returns a stored per-second rate).
contract TTokenMock is ERC20 {
    uint256 internal constant EXP_SCALE = 1e18;

    address public underlying;
    uint256 public totalBorrows;
    uint256 public totalReserves;
    uint256 public reserveFactorMantissa;
    uint256 public accrualBlockTimestamp;
    uint256 public initialExchangeRateMantissa;
    uint256 public borrowRatePerTimestamp;

    // Comptroller-side gates (ComptrollerV2.mintAllowed / redeemAllowedInternal).
    bool public mintGuardianPaused;
    bool public redeemGuardianPaused;
    uint256 public supplyCap;

    constructor() ERC20("Takara Mock", "tMOCK") {}

    function decimals() public pure override returns (uint8) {
        return 8;
    }

    function interestRateModel() external view returns (address) {
        return address(this);
    }

    function getBorrowRate(uint256, uint256, uint256) external view returns (uint256) {
        return borrowRatePerTimestamp;
    }

    function getCash() public view returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    }

    function exchangeRateStored() public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return initialExchangeRateMantissa;
        return ((getCash() + totalBorrows - totalReserves) * EXP_SCALE) / supply;
    }

    function accrueInterest() public returns (uint256) {
        uint256 prior = accrualBlockTimestamp;
        if (prior == block.timestamp) return 0;
        uint256 interest = (borrowRatePerTimestamp * (block.timestamp - prior) * totalBorrows) / EXP_SCALE;
        totalReserves = totalReserves + (reserveFactorMantissa * interest) / EXP_SCALE;
        totalBorrows = totalBorrows + interest;
        accrualBlockTimestamp = block.timestamp;
        return 0;
    }

    function exchangeRateCurrent() external returns (uint256) {
        accrueInterest();
        return exchangeRateStored();
    }

    function mint(uint256 mintAmount) external returns (uint256) {
        accrueInterest();
        require(!mintGuardianPaused, "mint is paused");
        if (supplyCap != 0) {
            require(getCash() + totalBorrows - totalReserves + mintAmount < supplyCap, "market supply cap reached");
        }
        uint256 rate = exchangeRateStored();
        require(IERC20(underlying).transferFrom(msg.sender, address(this), mintAmount));
        uint256 mintTokens = ((EXP_SCALE * mintAmount) * EXP_SCALE / rate) / EXP_SCALE;
        _mint(msg.sender, mintTokens);
        return 0;
    }

    function redeem(uint256 redeemTokens) external returns (uint256) {
        accrueInterest();
        require(!redeemGuardianPaused, "redeem is paused");
        uint256 rate = exchangeRateStored();
        uint256 redeemAmount = (rate * redeemTokens) / EXP_SCALE;
        if (balanceOf(msg.sender) < redeemTokens) return 3; // MATH_ERROR
        if (getCash() < redeemAmount) return 14; // TOKEN_INSUFFICIENT_CASH
        _burn(msg.sender, redeemTokens);
        require(IERC20(underlying).transfer(msg.sender, redeemAmount));
        return 0;
    }

    function redeemUnderlying(uint256) external pure returns (uint256) {
        revert("unused");
    }
}
