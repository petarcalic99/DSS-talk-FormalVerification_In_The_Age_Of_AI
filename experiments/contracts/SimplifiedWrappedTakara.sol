// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * SIMPLIFIED AND MODIFIED VERSION — NOT THE AUDITED CONTRACT
 *
 * The experiment ran on the real SpectraWrappedTakara contract (an ERC-4626 wrapper
 * around a Takara lending-market tToken). For compliance reasons, that contract has
 * been simplified and modified here: access control, pausing, initialization, interest
 * accrual and error handling are removed, and the code is rewritten.
 *
 * The idea, and the vulnerability, are the same:
 *   - Shares are priced from the wrapper's RAW tToken balance (see totalVaultShares()).
 *   - Conversions round down, with one virtual share and one virtual tToken
 *     (decimals offset 0).
 *   - Anyone can transfer tTokens directly to the wrapper. This "donation" increases
 *     the backing without minting shares, so later deposits can round down to zero
 *     shares while the attacker's share absorbs their value.
 *
 * The agents' tests and CVL specs in ../runs target the original contract, so some
 * names, imports and storage details differ from this file.
 */

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Minimal view of a Compound-style market token (cToken / tToken).
interface ITToken is IERC20 {
    function underlying() external view returns (address);
    function exchangeRateStored() external view returns (uint256); // underlying per tToken, 1e18-scaled
    function mint(uint256 underlyingAmount) external returns (uint256 err);
    function redeem(uint256 tTokenAmount) external returns (uint256 err);
}

contract SimplifiedWrappedTakara is ERC20 {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 private constant SCALE = 1e18;

    IERC20 public immutable asset; // e.g. USDC
    ITToken public immutable tToken; // the Takara market token held as backing

    constructor(ITToken _tToken) ERC20("Wrapped Takara", "wTKR") {
        tToken = _tToken;
        asset = IERC20(_tToken.underlying());
        asset.forceApprove(address(_tToken), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                    PRICING — WHERE THE BUG LIVES
    //////////////////////////////////////////////////////////////*/

    /// @dev VULNERABLE: reads the raw balance, so a direct tToken transfer moves the price.
    /// The reference repair (V1 in the experiment) tracks backing in storage instead,
    /// updated only by wrap/unwrap/deposit/redeem, so donations do not change the price.
    function totalVaultShares() public view returns (uint256) {
        return tToken.balanceOf(address(this));
    }

    /// @dev 0 in the audited code. OpenZeppelin's mitigation raises it (e.g. 6),
    /// which makes a zero-share donation about 10^offset times more expensive.
    function _decimalsOffset() internal pure virtual returns (uint8) {
        return 0;
    }

    /// shares = floor(t * (S + 10^offset) / (V + 1))
    function previewWrap(uint256 tTokens) public view returns (uint256) {
        return tTokens.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalVaultShares() + 1);
    }

    /// tTokens = floor(s * (V + 1) / (S + 10^offset))
    function previewUnwrap(uint256 shares) public view returns (uint256) {
        return shares.mulDiv(totalVaultShares() + 1, totalSupply() + 10 ** _decimalsOffset());
    }

    /// Asset-level views go through the market's exchange rate (rounding down).
    function previewDeposit(uint256 assets) public view returns (uint256) {
        return previewWrap(assets * SCALE / tToken.exchangeRateStored());
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return previewUnwrap(shares) * tToken.exchangeRateStored() / SCALE;
    }

    /*//////////////////////////////////////////////////////////////
                    tTOKEN LAYER: WRAP / UNWRAP
    //////////////////////////////////////////////////////////////*/

    function wrap(uint256 tTokens, address receiver) external returns (uint256 shares) {
        shares = previewWrap(tTokens); // computed BEFORE the transfer, can be 0
        IERC20(address(tToken)).safeTransferFrom(msg.sender, address(this), tTokens);
        _mint(receiver, shares);
    }

    function unwrap(uint256 shares, address receiver) external returns (uint256 tTokens) {
        tTokens = previewUnwrap(shares);
        _burn(msg.sender, shares);
        IERC20(address(tToken)).safeTransfer(receiver, tTokens);
    }

    /*//////////////////////////////////////////////////////////////
                    ASSET LAYER: DEPOSIT / REDEEM
    //////////////////////////////////////////////////////////////*/

    /// @dev No zero-share check: a deposit that rounds to 0 shares still succeeds
    /// and its value accrues to existing shareholders.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = previewDeposit(assets);
        asset.safeTransferFrom(msg.sender, address(this), assets);
        require(tToken.mint(assets) == 0, "mint failed");
        _mint(receiver, shares);
    }

    function redeem(uint256 shares, address receiver) external returns (uint256 assets) {
        uint256 tTokens = previewUnwrap(shares);
        _burn(msg.sender, shares);
        uint256 balanceBefore = asset.balanceOf(address(this));
        require(tToken.redeem(tTokens) == 0, "redeem failed");
        assets = asset.balanceOf(address(this)) - balanceBefore;
        asset.safeTransfer(receiver, assets);
    }
}
