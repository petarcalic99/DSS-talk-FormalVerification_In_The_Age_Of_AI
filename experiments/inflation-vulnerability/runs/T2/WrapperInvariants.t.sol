// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {ITToken} from "../src/takara/interface/ITToken.sol";
import {SpectraWrappedTakara} from "../src/takara/SpectraWrappedTakara.sol";
import {StandardERC20} from "../src/tokens/StandardERC20.sol";
import {WrapperBase} from "./WrapperBase.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @dev Drives arbitrary sequences of user and admin calls and records property violations
/// in ghost flags that the invariant functions check after every call.
contract Handler is CommonBase, StdCheats, StdUtils {
    uint256 internal constant EPS = 10;

    SpectraWrappedTakara internal wrapper;
    StandardERC20 internal usdc;
    IERC20 internal tToken;
    address internal admin;

    address[] public actors;

    uint256 public lastPrice;
    bool public priceDecreased; // R2
    bool public pausedOpSucceeded; // R3
    bool public unfairDeposit; // R5

    constructor(SpectraWrappedTakara w, StandardERC20 u, IERC20 t, address admin_) {
        wrapper = w;
        usdc = u;
        tToken = t;
        admin = admin_;
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA401));
        lastPrice = _price();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _price() internal view returns (uint256) {
        return wrapper.convertToAssets(10 ** uint256(wrapper.decimals()));
    }

    function _checkPrice() internal {
        uint256 p = _price();
        if (p < lastPrice) priceDecreased = true;
        lastPrice = p;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _mintTTokens(address who, uint256 usdcAmount) internal returns (uint256 minted) {
        deal(address(usdc), who, usdc.balanceOf(who) + usdcAmount);
        uint256 before = tToken.balanceOf(who);
        vm.startPrank(who);
        usdc.approve(address(tToken), usdcAmount);
        require(ITToken(address(tToken)).mint(usdcAmount) == 0, "takara mint failed");
        vm.stopPrank();
        minted = tToken.balanceOf(who) - before;
    }

    function deposit(uint256 seed, uint256 assets) external {
        address a = _actor(seed);
        assets = bound(assets, 0, 1e13);
        deal(address(usdc), a, usdc.balanceOf(a) + assets);
        vm.prank(a);
        usdc.approve(address(wrapper), assets);
        if (wrapper.paused()) {
            vm.prank(a);
            try wrapper.deposit(assets, a) returns (uint256) {
                pausedOpSucceeded = true;
            } catch {}
            return;
        }
        vm.prank(a);
        uint256 shares = wrapper.deposit(assets, a);
        if (wrapper.previewRedeem(shares) + EPS < assets) unfairDeposit = true;
        _checkPrice();
    }

    function redeem(uint256 seed, uint256 shares) external {
        address a = _actor(seed);
        shares = bound(shares, 0, wrapper.balanceOf(a));
        if (wrapper.paused()) {
            vm.prank(a);
            try wrapper.redeem(shares, a, a) returns (uint256) {
                pausedOpSucceeded = true;
            } catch {}
            return;
        }
        vm.prank(a);
        wrapper.redeem(shares, a, a);
        _checkPrice();
    }

    function wrap(uint256 seed, uint256 usdcAmount) external {
        address a = _actor(seed);
        if (wrapper.paused()) {
            vm.prank(a);
            try wrapper.wrap(0, a) returns (uint256) {
                pausedOpSucceeded = true;
            } catch {}
            return;
        }
        uint256 t = _mintTTokens(a, bound(usdcAmount, 1, 1e13));
        vm.startPrank(a);
        tToken.approve(address(wrapper), t);
        wrapper.wrap(t, a);
        vm.stopPrank();
        _checkPrice();
    }

    function unwrap(uint256 seed, uint256 shares) external {
        address a = _actor(seed);
        shares = bound(shares, 0, wrapper.balanceOf(a));
        if (wrapper.paused()) {
            vm.prank(a);
            try wrapper.unwrap(shares, a, a) returns (uint256) {
                pausedOpSucceeded = true;
            } catch {}
            return;
        }
        vm.prank(a);
        wrapper.unwrap(shares, a, a);
        _checkPrice();
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 shares) external {
        if (wrapper.paused()) return;
        address from = _actor(fromSeed);
        shares = bound(shares, 0, wrapper.balanceOf(from));
        vm.prank(from);
        wrapper.transfer(_actor(toSeed), shares);
        _checkPrice();
    }

    function donate(uint256 seed, uint256 usdcAmount) external {
        address a = _actor(seed);
        uint256 t = _mintTTokens(a, bound(usdcAmount, 1, 1e12));
        vm.prank(a);
        tToken.transfer(address(wrapper), t);
        _checkPrice();
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 1, 30 days));
        _checkPrice();
    }

    function togglePause() external {
        bool isPaused = wrapper.paused();
        vm.prank(admin);
        if (isPaused) wrapper.unpause();
        else wrapper.pause();
        _checkPrice();
    }
}

abstract contract InvariantBase is WrapperBase {
    Handler internal handler;

    function _selectors() internal pure virtual returns (bytes4[] memory);

    function setUp() public virtual override {
        super.setUp();
        handler = new Handler(wrapper, usdc, tToken, address(this));
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: _selectors()}));
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 40
    function invariant_R1_supplyEqualsSumOfBalances() public view {
        uint256 sum;
        for (uint256 i; i < handler.actorCount(); ++i) {
            sum += wrapper.balanceOf(handler.actors(i));
        }
        assertEq(sum, wrapper.totalSupply());
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 40
    function invariant_R2_priceNeverDecreases() public view {
        assertFalse(handler.priceDecreased());
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 40
    function invariant_R3_pausedMeansClosed() public view {
        assertFalse(handler.pausedOpSucceeded());
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 40
    function invariant_R5_fairDeposit() public view {
        assertFalse(handler.unfairDeposit());
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 40
    function invariant_I1_solvency() public view {
        uint256 claimable = ITToken(address(tToken)).exchangeRateStored()
            * tToken.balanceOf(address(wrapper)) / 1e18;
        assertLe(wrapper.totalAssets(), claimable);
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 40
    function invariant_I4_noStrandedUsdc() public view {
        assertEq(usdc.balanceOf(address(wrapper)), 0);
    }
}

/// @dev All actions, including direct tToken donations to the wrapper.
contract WrapperInvariantTest is InvariantBase {
    function _selectors() internal pure override returns (bytes4[] memory s) {
        s = new bytes4[](8);
        s[0] = Handler.deposit.selector;
        s[1] = Handler.redeem.selector;
        s[2] = Handler.wrap.selector;
        s[3] = Handler.unwrap.selector;
        s[4] = Handler.transfer.selector;
        s[5] = Handler.donate.selector;
        s[6] = Handler.warp.selector;
        s[7] = Handler.togglePause.selector;
    }
}

/// @dev Same actions without donations, to isolate donations as the root cause of R5 failures.
contract WrapperInvariantNoDonationTest is InvariantBase {
    function _selectors() internal pure override returns (bytes4[] memory s) {
        s = new bytes4[](7);
        s[0] = Handler.deposit.selector;
        s[1] = Handler.redeem.selector;
        s[2] = Handler.wrap.selector;
        s[3] = Handler.unwrap.selector;
        s[4] = Handler.transfer.selector;
        s[5] = Handler.warp.selector;
        s[6] = Handler.togglePause.selector;
    }
}
