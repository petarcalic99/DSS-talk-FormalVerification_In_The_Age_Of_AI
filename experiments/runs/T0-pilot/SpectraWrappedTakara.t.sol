// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ComptrollerV2} from "../lib/takara/src/ComptrollerV2.sol";
import {TToken} from "../lib/takara/src/TToken.sol";
import {SpectraWrappedTakara} from "../src/takara/SpectraWrappedTakara.sol";
import {ITToken} from "../src/takara/interface/ITToken.sol";
import {StandardERC20} from "../src/tokens/StandardERC20.sol";
import {LocalDeployment} from "./utils/LocalDeployment.sol";
import {IAccessManaged} from "openzeppelin-contracts/access/manager/IAccessManaged.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";

/// @dev Shared fixture: local Takara tUSDC market + wrapper, plus helpers to simulate borrowing.
abstract contract WrapperFixture is LocalDeployment {
    uint256 internal constant TOTAL_BORROWS_SLOT = 11;

    StandardERC20 internal usdc;
    ITToken internal tToken;
    SpectraWrappedTakara internal wrapper;
    address internal manager;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public virtual {
        vm.warp(1_750_000_000);
        (address u, address t, address w, address m) = _deployLocal();
        usdc = StandardERC20(u);
        tToken = ITToken(t);
        wrapper = SpectraWrappedTakara(w);
        manager = m;
    }

    /// @dev Moves `borrowFraction` (1e18 = 100%) of the market's cash into outstanding borrows
    /// (rate-neutral at the moment of the move), sets the reserve factor, then lets `dt` seconds pass
    /// WITHOUT accruing, so the tToken's stored exchange rate is stale.
    function _simulateBorrows(uint256 borrowFraction, uint256 reserveFactor, uint256 dt) internal {
        require(tToken.accrueInterest() == 0, "accrue");
        require(TToken(address(tToken))._setReserveFactor(reserveFactor) == 0, "rf");
        uint256 cash = usdc.balanceOf(address(tToken));
        uint256 borrows = cash * borrowFraction / 1e18;
        vm.store(address(tToken), bytes32(TOTAL_BORROWS_SLOT), bytes32(borrows));
        deal(address(usdc), address(tToken), cash - borrows);
        vm.warp(block.timestamp + dt);
    }

    function _deposit(address user, uint256 assets) internal returns (uint256 shares) {
        deal(address(usdc), user, usdc.balanceOf(user) + assets);
        vm.startPrank(user);
        usdc.approve(address(wrapper), assets);
        shares = wrapper.deposit(assets, user);
        vm.stopPrank();
    }

    function _redeem(address user, uint256 shares) internal returns (uint256 assets) {
        vm.prank(user);
        assets = wrapper.redeem(shares, user, user);
    }

    /// @dev Gives `user` freshly minted tTokens by supplying `underlying` to Takara directly.
    function _mintTTokens(address user, uint256 underlying) internal returns (uint256 minted) {
        deal(address(usdc), user, usdc.balanceOf(user) + underlying);
        uint256 before = _tBal(user);
        vm.startPrank(user);
        usdc.approve(address(tToken), underlying);
        require(tToken.mint(underlying) == 0, "tToken mint");
        vm.stopPrank();
        minted = _tBal(user) - before;
    }

    function _wrap(address user, uint256 vaultShares) internal returns (uint256 shares) {
        vm.startPrank(user);
        StandardERC20(address(tToken)).approve(address(wrapper), vaultShares);
        shares = wrapper.wrap(vaultShares, user);
        vm.stopPrank();
    }

    function _unwrap(address user, uint256 shares) internal returns (uint256 vaultShares) {
        vm.prank(user);
        vaultShares = wrapper.unwrap(shares, user, user);
    }

    function _tBal(address a) internal view returns (uint256) {
        return StandardERC20(address(tToken)).balanceOf(a);
    }

    function _comptroller() internal view returns (ComptrollerV2) {
        return ComptrollerV2(address(TToken(address(tToken)).comptroller()));
    }
}

contract SpectraWrappedTakaraTest is WrapperFixture {
    /*//////////////////////////////////////////////////////////////
                          ACCOUNTING AND PRICING
    //////////////////////////////////////////////////////////////*/

    /// P1 — previewDeposit equals minted shares, with stale interest pending in the market.
    function testFuzz_P1_previewDepositExact(
        uint256 seed,
        uint256 assets,
        uint256 borrowFraction,
        uint256 reserveFactor,
        uint256 dt
    ) public {
        seed = bound(seed, 1, 1e12);
        assets = bound(assets, 1, 1e14);
        borrowFraction = bound(borrowFraction, 0, 0.95e18);
        reserveFactor = bound(reserveFactor, 0, 1e18);
        dt = bound(dt, 0, 365 days);

        _deposit(carol, seed);
        _simulateBorrows(borrowFraction, reserveFactor, dt);

        uint256 preview = wrapper.previewDeposit(assets);
        uint256 before = wrapper.balanceOf(alice);
        uint256 shares = _deposit(alice, assets);
        assertEq(shares, preview, "returned shares != preview");
        assertEq(wrapper.balanceOf(alice) - before, preview, "minted shares != preview");
    }

    /// P2 — previewRedeem equals underlying received, with stale interest pending in the market.
    function testFuzz_P2_previewRedeemExact(
        uint256 assets,
        uint256 redeemFraction,
        uint256 borrowFraction,
        uint256 reserveFactor,
        uint256 dt
    ) public {
        assets = bound(assets, 1, 1e14);
        redeemFraction = bound(redeemFraction, 1, 1e18);
        borrowFraction = bound(borrowFraction, 0, 0.5e18);
        reserveFactor = bound(reserveFactor, 0, 1e18);
        dt = bound(dt, 0, 365 days);

        uint256 shares = _deposit(alice, assets);
        _simulateBorrows(borrowFraction, reserveFactor, dt);

        uint256 toRedeem = shares * redeemFraction / 1e18;
        uint256 preview = wrapper.previewRedeem(toRedeem);
        // Market liquidity is P12's concern; here only redeems the market can pay are considered.
        vm.assume(preview <= usdc.balanceOf(address(tToken)));
        uint256 before = usdc.balanceOf(alice);
        uint256 out = _redeem(alice, toRedeem);
        assertEq(out, preview, "returned assets != preview");
        assertEq(usdc.balanceOf(alice) - before, preview, "received assets != preview");
    }

    /// P3 — deposit then redeem never returns more underlying than deposited.
    function testFuzz_P3_depositRoundTripNoProfit(
        uint256 seed,
        uint256 assets,
        uint256 borrowFraction,
        uint256 dt
    ) public {
        seed = bound(seed, 0, 1e12);
        assets = bound(assets, 1, 1e14);
        borrowFraction = bound(borrowFraction, 0, 0.5e18);
        dt = bound(dt, 0, 365 days);
        if (seed > 0) _deposit(carol, seed);
        _simulateBorrows(borrowFraction, 0.1e18, dt);

        uint256 shares = _deposit(alice, assets);
        uint256 out = _redeem(alice, shares);
        assertLe(out, assets, "round trip profit");
    }

    /// P4 — wrap then unwrap never returns more tTokens than wrapped.
    function testFuzz_P4_wrapRoundTripNoProfit(uint256 seed, uint256 underlying) public {
        seed = bound(seed, 0, 1e12);
        underlying = bound(underlying, 2, 1e14);
        if (seed > 0) _deposit(carol, seed);
        uint256 t = _mintTTokens(alice, underlying);
        uint256 shares = _wrap(alice, t);
        uint256 back = _unwrap(alice, shares);
        assertLe(back, t, "wrap round trip profit");
    }

    /// P7 — another user's deposit/redeem/wrap/unwrap never lowers Alice's redeemable value.
    function testFuzz_P7_isolation(
        uint256 aliceAssets,
        uint256 bobAssets,
        uint256 bobRedeemFraction,
        uint256 bobTUnderlying,
        uint256 dt
    ) public {
        aliceAssets = bound(aliceAssets, 1, 1e14);
        bobAssets = bound(bobAssets, 1, 1e14);
        bobRedeemFraction = bound(bobRedeemFraction, 0, 1e18);
        bobTUnderlying = bound(bobTUnderlying, 2, 1e14);
        dt = bound(dt, 0, 30 days);

        uint256 aliceShares = _deposit(alice, aliceAssets);
        _simulateBorrows(0.3e18, 0.1e18, dt);
        require(tToken.accrueInterest() == 0, "accrue");

        uint256 v0 = wrapper.previewRedeem(aliceShares);
        uint256 bobShares = _deposit(bob, bobAssets);
        assertGe(wrapper.previewRedeem(aliceShares), v0, "bob deposit hurt alice");
        _redeem(bob, bobShares * bobRedeemFraction / 1e18);
        assertGe(wrapper.previewRedeem(aliceShares), v0, "bob redeem hurt alice");
        uint256 bobWrapped = _wrap(bob, _mintTTokens(bob, bobTUnderlying));
        assertGe(wrapper.previewRedeem(aliceShares), v0, "bob wrap hurt alice");
        _unwrap(bob, bobWrapped);
        assertGe(wrapper.previewRedeem(aliceShares), v0, "bob unwrap hurt alice");
    }

    /// P8 — deposit and redeem leave the wrapper's own underlying balance untouched, even when
    /// some underlying sits in the wrapper for an unrelated reason.
    function testFuzz_P8_noStuckOrStolenUnderlying(
        uint256 stray,
        uint256 assets,
        uint256 borrowFraction,
        uint256 dt
    ) public {
        stray = bound(stray, 0, 1e12);
        assets = bound(assets, 1, 1e14);
        borrowFraction = bound(borrowFraction, 0, 0.5e18);
        dt = bound(dt, 0, 365 days);
        deal(address(usdc), address(wrapper), stray);

        _simulateBorrows(borrowFraction, 0.1e18, dt);
        uint256 shares = _deposit(alice, assets);
        assertEq(usdc.balanceOf(address(wrapper)), stray, "deposit changed wrapper underlying");
        vm.warp(block.timestamp + dt);
        // Market liquidity is P12's concern; here only redeems the market can pay are considered.
        vm.assume(wrapper.previewRedeem(shares) <= usdc.balanceOf(address(tToken)));
        _redeem(alice, shares);
        assertEq(usdc.balanceOf(address(wrapper)), stray, "redeem changed wrapper underlying");
    }

    /// P9 — first depositor + tToken donation cannot profit at a later depositor's expense.
    function testFuzz_P9_donationAttackNotProfitable(
        uint256 attackerUnderlying,
        uint256 donationUnderlying,
        uint256 victimAssets
    ) public {
        attackerUnderlying = bound(attackerUnderlying, 2, 1e8);
        donationUnderlying = bound(donationUnderlying, 2, 1e14);
        victimAssets = bound(victimAssets, 1, 1e14);

        address attacker = makeAddr("attacker");
        uint256 entryT = _mintTTokens(attacker, attackerUnderlying);
        uint256 donationT = _mintTTokens(attacker, donationUnderlying);
        uint256 spentT = entryT + donationT;

        uint256 attackerShares = _wrap(attacker, entryT);
        vm.prank(attacker);
        StandardERC20(address(tToken)).transfer(address(wrapper), donationT);

        _deposit(alice, victimAssets);
        uint256 backT = _unwrap(attacker, attackerShares);
        assertLe(backT, spentT, "attacker profited");
    }

    /*//////////////////////////////////////////////////////////////
                              ERC-4626 LIMITS
    //////////////////////////////////////////////////////////////*/

    /// P10 — mint/withdraw always revert; maxMint/maxWithdraw are 0.
    function test_P10_unsupportedEntryPoints() public {
        _deposit(alice, 1e9);
        assertEq(wrapper.maxMint(alice), 0);
        assertEq(wrapper.maxWithdraw(alice), 0);
        vm.startPrank(alice);
        vm.expectRevert(SpectraWrappedTakara.NotImplemented.selector);
        wrapper.mint(1, alice);
        vm.expectRevert(SpectraWrappedTakara.NotImplemented.selector);
        wrapper.withdraw(1, alice, alice);
        vm.expectRevert(SpectraWrappedTakara.NotImplemented.selector);
        wrapper.previewMint(1);
        vm.expectRevert(SpectraWrappedTakara.NotImplemented.selector);
        wrapper.previewWithdraw(1);
        vm.stopPrank();
    }

    /// P11 — a deposit within maxDeposit succeeds (here: Takara has paused minting on the market).
    function test_P11_maxDepositHonestWhenTakaraMintPaused() public {
        _comptroller()._setMintPaused(TToken(address(tToken)), true);

        uint256 assets = 1e9;
        uint256 max = wrapper.maxDeposit(alice);
        deal(address(usdc), alice, assets);
        vm.startPrank(alice);
        usdc.approve(address(wrapper), assets);
        bool ok;
        try wrapper.deposit(assets, alice) {
            ok = true;
        } catch {}
        vm.stopPrank();
        assertTrue(ok || max < assets, "maxDeposit allows an amount that deposit rejects");
    }

    /// P11 — a deposit within maxDeposit succeeds (here: Takara supply cap is reached).
    function test_P11_maxDepositHonestWhenSupplyCapReached() public {
        TToken[] memory markets = new TToken[](1);
        markets[0] = TToken(address(tToken));
        uint256[] memory caps = new uint256[](1);
        caps[0] = 1; // already exceeded by existing supply
        _comptroller()._setMarketSupplyCaps(markets, caps);

        uint256 assets = 1e9;
        uint256 max = wrapper.maxDeposit(alice);
        deal(address(usdc), alice, assets);
        vm.startPrank(alice);
        usdc.approve(address(wrapper), assets);
        bool ok;
        try wrapper.deposit(assets, alice) {
            ok = true;
        } catch {}
        vm.stopPrank();
        assertTrue(ok || max < assets, "maxDeposit allows an amount that deposit rejects");
    }

    /// P12 — redeeming maxRedeem(owner) succeeds (here: the market is highly utilized).
    function test_P12_maxRedeemHonestUnderHighUtilization() public {
        uint256 shares = _deposit(alice, 1e9); // 1000 USDC, a large share of the ~1757 USDC market
        _simulateBorrows(0.9e18, 0.1e18, 0);

        uint256 max = wrapper.maxRedeem(alice);
        assertEq(max, shares);
        vm.prank(alice);
        bool ok;
        try wrapper.redeem(max, alice, alice) {
            ok = true;
        } catch {}
        assertTrue(ok, "redeem(maxRedeem) reverted");
    }

    /*//////////////////////////////////////////////////////////////
                      PAUSE / ACCESS CONTROL / ALLOWANCES
    //////////////////////////////////////////////////////////////*/

    /// P13 — pause blocks every state-changing path; unpause restores them.
    function test_P13_pause() public {
        uint256 shares = _deposit(alice, 1e9);
        uint256 t = _mintTTokens(alice, 1e8);
        deal(address(usdc), alice, 1e9);
        vm.startPrank(alice);
        usdc.approve(address(wrapper), type(uint256).max);
        StandardERC20(address(tToken)).approve(address(wrapper), type(uint256).max);
        vm.stopPrank();

        wrapper.pause();
        assertTrue(wrapper.paused());
        assertEq(wrapper.maxDeposit(alice), 0);
        assertEq(wrapper.maxRedeem(alice), 0);

        vm.startPrank(alice);
        vm.expectRevert();
        wrapper.deposit(1e6, alice);
        vm.expectRevert();
        wrapper.redeem(1, alice, alice);
        vm.expectRevert();
        wrapper.wrap(t, alice);
        vm.expectRevert();
        wrapper.unwrap(1, alice, alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        wrapper.transfer(bob, 1);
        vm.stopPrank();

        wrapper.unpause();
        vm.startPrank(alice);
        wrapper.deposit(1e6, alice);
        wrapper.wrap(t, alice);
        wrapper.transfer(bob, 1);
        wrapper.unwrap(1, alice, alice);
        wrapper.redeem(shares / 2, alice, alice);
        vm.stopPrank();
    }

    /// P14 — restricted functions reject unauthorized callers and accept the admin.
    function test_P14_accessControl() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, bob));
        wrapper.pause();
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, bob));
        wrapper.unpause();
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, bob));
        wrapper.setRewardsProxy(bob);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, bob));
        wrapper.claimRewards("");
        vm.stopPrank();

        // The AccessManager admin (this contract) is authorized.
        wrapper.pause();
        wrapper.unpause();
        wrapper.setRewardsProxy(bob);
        assertEq(wrapper.rewardsProxy(), bob);
    }

    /// P15 — third-party redeem/unwrap need and consume allowance.
    function testFuzz_P15_allowances(uint256 allowance, uint256 amount) public {
        uint256 shares = _deposit(alice, 1e9);
        allowance = bound(allowance, 0, shares);
        amount = bound(amount, 1, shares);
        vm.prank(alice);
        wrapper.approve(bob, allowance);

        vm.startPrank(bob);
        if (amount > allowance) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, bob, allowance, amount
                )
            );
            wrapper.redeem(amount, bob, alice);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, bob, allowance, amount
                )
            );
            wrapper.unwrap(amount, bob, alice);
        } else {
            wrapper.redeem(amount, bob, alice);
            assertEq(wrapper.allowance(alice, bob), allowance - amount);
            if (allowance - amount > 0) {
                wrapper.unwrap(allowance - amount, bob, alice);
                assertEq(wrapper.allowance(alice, bob), 0);
            }
        }
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                  SETUP
    //////////////////////////////////////////////////////////////*/

    /// P16 — no re-initialization of the proxy, no initialization of the implementation.
    function test_P16_initializeOnce() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        wrapper.initialize(address(tToken), manager);

        SpectraWrappedTakara impl = new SpectraWrappedTakara();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(address(tToken), manager);
    }

    /// P17 — metadata.
    function test_P17_metadata() public view {
        assertEq(wrapper.asset(), address(usdc));
        assertEq(wrapper.vaultShare(), address(tToken));
        assertEq(wrapper.decimals(), StandardERC20(address(tToken)).decimals());
    }
}

/// @dev Random sequences of user actions with interest accruing between them.
contract WrapperHandler is WrapperFixture {
    address[3] internal actors;

    constructor(StandardERC20 _usdc, ITToken _tToken, SpectraWrappedTakara _wrapper) {
        usdc = _usdc;
        tToken = _tToken;
        wrapper = _wrapper;
        actors = [alice, bob, carol];
    }

    function setUp() public override {}

    function deposit(uint256 who, uint256 assets) external {
        _deposit(actors[who % 3], bound(assets, 1, 1e13));
        tToken.accrueInterest();
    }

    function redeem(uint256 who, uint256 fraction) external {
        address a = actors[who % 3];
        uint256 shares = wrapper.balanceOf(a) * bound(fraction, 0, 1e18) / 1e18;
        _redeem(a, shares);
        tToken.accrueInterest();
    }

    function wrap(uint256 who, uint256 underlying) external {
        address a = actors[who % 3];
        _wrap(a, _mintTTokens(a, bound(underlying, 2, 1e13)));
        tToken.accrueInterest();
    }

    function unwrap(uint256 who, uint256 fraction) external {
        address a = actors[who % 3];
        _unwrap(a, wrapper.balanceOf(a) * bound(fraction, 0, 1e18) / 1e18);
        tToken.accrueInterest();
    }

    function passTime(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 1, 30 days));
        tToken.accrueInterest();
    }
}

contract SpectraWrappedTakaraInvariants is WrapperFixture {
    WrapperHandler internal handler;

    function setUp() public override {
        super.setUp();
        _simulateBorrows(0.3e18, 0.1e18, 0);
        handler = new WrapperHandler(usdc, tToken, wrapper);
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = WrapperHandler.deposit.selector;
        selectors[1] = WrapperHandler.redeem.selector;
        selectors[2] = WrapperHandler.wrap.selector;
        selectors[3] = WrapperHandler.unwrap.selector;
        selectors[4] = WrapperHandler.passTime.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// P5 — tTokens owed to all shares never exceed tTokens held.
    function invariant_P5_solvency() public view {
        assertLe(wrapper.previewUnwrap(wrapper.totalSupply()), wrapper.totalVaultShares());
    }

    /// P6 — totalAssets never exceeds the underlying value of the held tTokens.
    function invariant_P6_totalAssetsBacked() public view {
        uint256 backing = wrapper.totalVaultShares() * tToken.exchangeRateStored() / 1e18;
        assertLe(wrapper.totalAssets(), backing);
    }

    /// P8 — no underlying is ever left in the wrapper.
    function invariant_P8_noUnderlyingInWrapper() public view {
        assertEq(usdc.balanceOf(address(wrapper)), 0);
    }
}
