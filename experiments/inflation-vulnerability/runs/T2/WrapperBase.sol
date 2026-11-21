// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {ITToken} from "../src/takara/interface/ITToken.sol";
import {SpectraWrappedTakara} from "../src/takara/SpectraWrappedTakara.sol";
import {StandardERC20} from "../src/tokens/StandardERC20.sol";
import {LocalDeployment} from "./utils/LocalDeployment.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @dev Shared fixture: the full local system from `LocalDeployment` plus small helpers.
abstract contract WrapperBase is LocalDeployment {
    uint256 internal constant EPS = 10; // ε = 10 wei of USDC (README)

    StandardERC20 internal usdc;
    IERC20 internal tToken;
    SpectraWrappedTakara internal wrapper;
    address internal manager;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public virtual {
        (address u, address t, address w, address m) = _deployLocal();
        usdc = StandardERC20(u);
        tToken = IERC20(t);
        wrapper = SpectraWrappedTakara(w);
        manager = m;
    }

    function _fundUsdc(address who, uint256 amount) internal {
        deal(address(usdc), who, usdc.balanceOf(who) + amount);
    }

    /// @dev `who` deposits `assets` USDC into the wrapper, receiving shares itself.
    function _deposit(address who, uint256 assets) internal returns (uint256 shares) {
        _fundUsdc(who, assets);
        vm.startPrank(who);
        usdc.approve(address(wrapper), assets);
        shares = wrapper.deposit(assets, who);
        vm.stopPrank();
    }

    /// @dev `who` supplies `usdcAmount` to Takara directly and gets tTokens.
    function _mintTTokens(address who, uint256 usdcAmount) internal returns (uint256 minted) {
        _fundUsdc(who, usdcAmount);
        uint256 before = tToken.balanceOf(who);
        vm.startPrank(who);
        usdc.approve(address(tToken), usdcAmount);
        require(ITToken(address(tToken)).mint(usdcAmount) == 0, "takara mint failed");
        vm.stopPrank();
        minted = tToken.balanceOf(who) - before;
    }

    function _wrap(address who, uint256 tTokens) internal returns (uint256 shares) {
        vm.startPrank(who);
        tToken.approve(address(wrapper), tTokens);
        shares = wrapper.wrap(tTokens, who);
        vm.stopPrank();
    }

    function _donate(address who, uint256 tTokens) internal {
        vm.prank(who);
        tToken.transfer(address(wrapper), tTokens);
    }

    /// @dev USDC value of one whole wrapper share.
    function _price() internal view returns (uint256) {
        return wrapper.convertToAssets(10 ** uint256(wrapper.decimals()));
    }

    /// @dev Takara exchange rate after accruing to the current block.
    function _rate() internal returns (uint256) {
        return ITToken(address(tToken)).exchangeRateCurrent();
    }
}
