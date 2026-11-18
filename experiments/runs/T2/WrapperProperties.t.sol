// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {WrapperBase} from "./WrapperBase.sol";
import {TToken} from "../lib/takara/src/TToken.sol";
import {ITToken} from "../src/takara/interface/ITToken.sol";
import {SpectraWrappedTakara} from "../src/takara/SpectraWrappedTakara.sol";
import {StdStorage, stdStorage} from "forge-std/Test.sol";

/// @dev Unit and fuzz tests for the properties in PROPERTIES.md (R* = README, E* = README ERC-4626
/// section, I* = inferred). Tests named `..._Bug_...` are expected to FAIL on the current code;
/// each one is a reproduction of a finding in REPORT.md.
contract WrapperPropertiesTest is WrapperBase {
    using stdStorage for StdStorage;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                         R1 SUPPLY CONSISTENCY
    //////////////////////////////////////////////////////////////*/

    function testFuzz_R1_supplyEqualsSumOfBalances(uint256 a, uint256 b, uint256 t, uint256 r)
        public
    {
        a = bound(a, 0, 1e13);
        b = bound(b, 0, 1e13);
        t = bound(t, 1, 1e13);
        _deposit(alice, a);
        _deposit(bob, b);
        _wrap(carol, _mintTTokens(carol, t));
        r = bound(r, 0, wrapper.balanceOf(alice));
        vm.prank(alice);
        wrapper.redeem(r, alice, alice);
        uint256 half = wrapper.balanceOf(bob) / 2;
        vm.prank(bob);
        wrapper.transfer(carol, half);
        assertEq(
            wrapper.balanceOf(alice) + wrapper.balanceOf(bob) + wrapper.balanceOf(carol),
            wrapper.totalSupply()
        );
    }

    /*//////////////////////////////////////////////////////////////
                        R2 PRICE NEVER DECREASES
    //////////////////////////////////////////////////////////////*/

    function testFuzz_R2_priceNonDecreasingAcrossOps(uint256 a, uint256 t, uint256 r, uint256 u)
        public
    {
        uint256 p0 = _price();
        _deposit(alice, bound(a, 0, 1e13));
        uint256 p1 = _price();
        assertGe(p1, p0, "deposit lowered price");
        _wrap(bob, _mintTTokens(bob, bound(t, 1, 1e13)));
        uint256 p2 = _price();
        assertGe(p2, p1, "wrap lowered price");
        r = bound(r, 0, wrapper.balanceOf(alice));
        vm.prank(alice);
        wrapper.redeem(r, alice, alice);
        uint256 p3 = _price();
        assertGe(p3, p2, "redeem lowered price");
        u = bound(u, 0, wrapper.balanceOf(bob));
        vm.prank(bob);
        wrapper.unwrap(u, bob, bob);
        assertGe(_price(), p3, "unwrap lowered price");
    }

    /// @dev Inferred edge case of R2: when every Takara tToken (the existing holder's and the
    /// wrapper's) is redeemed, Takara resets its exchange rate to the initial 1e18, so the
    /// quoted value of one whole wrapper share drops from ~1.0435 USDC to 1 USDC.
    function test_R2_Bug_priceDropsWhenTakaraMarketEmpties() public {
        uint256 shares = _deposit(alice, 1000e6);
        vm.prank(alice);
        wrapper.redeem(shares, alice, alice);
        uint256 before = _price();
        uint256 holderBal = tToken.balanceOf(existingHolder);
        vm.prank(existingHolder);
        require(ITToken(address(tToken)).redeem(holderBal) == 0, "holder redeem failed");
        assertEq(tToken.totalSupply(), 0, "market not empty");
        assertGe(_price(), before, "R2: price of one whole share decreased");
    }

    /*//////////////////////////////////////////////////////////////
                        R3 PAUSED MEANS CLOSED
    //////////////////////////////////////////////////////////////*/

    function testFuzz_R3_pausedClosesAllEntryPoints(uint256 d, uint256 r, uint256 w, uint256 u)
        public
    {
        _deposit(alice, 1000e6);
        uint256 t = _mintTTokens(alice, 1000e6);
        _wrap(alice, t / 2);
        _fundUsdc(alice, 1000e6);
        vm.startPrank(alice);
        usdc.approve(address(wrapper), type(uint256).max);
        tToken.approve(address(wrapper), type(uint256).max);
        vm.stopPrank();
        uint256 bal = wrapper.balanceOf(alice);

        wrapper.pause();

        d = bound(d, 0, 1000e6);
        r = bound(r, 0, bal);
        w = bound(w, 0, t - t / 2);
        u = bound(u, 0, bal);
        vm.startPrank(alice);
        vm.expectRevert();
        wrapper.deposit(d, alice);
        vm.expectRevert();
        wrapper.redeem(r, alice, alice);
        vm.expectRevert();
        wrapper.wrap(w, alice);
        vm.expectRevert();
        wrapper.unwrap(u, alice, alice);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    R4 DONATIONS DO NOT MOVE THE PRICE
    //////////////////////////////////////////////////////////////*/

    /// @dev Concrete reproduction: a 1000 USDC tToken donation doubles the share price.
    function test_R4_Bug_tTokenDonationDoublesPrice() public {
        _deposit(alice, 1000e6);
        uint256 d = _mintTTokens(bob, 1000e6);
        uint256 before = _price();
        _donate(bob, d);
        assertEq(_price(), before, "R4: tToken donation changed share price");
    }

    function testFuzz_R4_Bug_tTokenDonationDoesNotMovePrice(uint256 a, uint256 donation) public {
        _deposit(alice, bound(a, 1e6, 1e13));
        uint256 d = _mintTTokens(bob, bound(donation, 1e6, 1e13));
        uint256 before = _price();
        _donate(bob, d);
        assertEq(_price(), before, "R4: tToken donation changed share price");
    }

    /*//////////////////////////////////////////////////////////////
                            R5 FAIR DEPOSIT
    //////////////////////////////////////////////////////////////*/

    /// @dev Honest state (other users deposit/wrap, nobody donates).
    function testFuzz_R5_fairDeposit_honestState(uint256 prior, uint256 wrapped, uint256 a)
        public
    {
        _deposit(bob, bound(prior, 0, 1e13));
        _wrap(carol, _mintTTokens(carol, bound(wrapped, 1, 1e13)));
        a = bound(a, 0, 1e13);
        uint256 shares = _deposit(alice, a);
        assertGe(wrapper.previewRedeem(shares) + EPS, a, "R5: deposit lost more than eps");
    }

    /// @dev Concrete reproduction: first depositor wraps 1 tToken and donates ~1 USDC of tTokens;
    /// a 1000 USDC deposit afterwards loses ~358 wei (> ε).
    function test_R5_Bug_fairDepositAfterSmallDonation() public {
        _mintTTokens(bob, 2e6);
        _wrap(bob, 1);
        _donate(bob, 1e6);
        uint256 a = 1000e6;
        uint256 shares = _deposit(alice, a);
        assertGe(wrapper.previewRedeem(shares) + EPS, a, "R5: deposit lost more than eps");
    }

    function testFuzz_R5_Bug_fairDepositAfterDonation(uint256 donation, uint256 a) public {
        uint256 t = _mintTTokens(bob, bound(donation, 2e6, 1e13));
        _wrap(bob, 1);
        _donate(bob, t - 1);
        a = bound(a, 1e6, 1e13);
        uint256 shares = _deposit(alice, a);
        assertGe(wrapper.previewRedeem(shares) + EPS, a, "R5: deposit lost more than eps");
    }

    /*//////////////////////////////////////////////////////////////
                    I10 INFLATION (FIRST-DEPOSITOR) GRIEF
    //////////////////////////////////////////////////////////////*/

    /// @dev Attacker front-runs a 1000 USDC deposit into an empty wrapper: wraps 1 tToken, then
    /// donates ~2x the victim's tTokens. The victim's USDC is taken and 0 shares are minted.
    function test_I10_Bug_inflationAttackZeroesVictimShares() public {
        uint256 a = 1000e6;
        uint256 victimTTokens = (a * 1e36 / _rate()) / 1e18;
        uint256 t = _mintTTokens(bob, 2100e6);
        _wrap(bob, 1);
        _donate(bob, 2 * victimTTokens);
        assertGe(t, 2 * victimTTokens + 1);
        uint256 shares = _deposit(alice, a);
        assertEq(usdc.balanceOf(alice), 0, "victim USDC not taken");
        assertGt(shares, 0, "I10: victim received zero shares for 1000 USDC");
    }

    /*//////////////////////////////////////////////////////////////
                     E1 / E2 VIEWS: NO REVERT, NO CALLER
    //////////////////////////////////////////////////////////////*/

    function testFuzz_E1_viewsDoNotRevert(uint256 x, bool paused_) public {
        _deposit(alice, 1000e6);
        if (paused_) wrapper.pause();
        vm.warp(block.timestamp + 7 days);
        x = bound(x, 0, 1e40);
        wrapper.asset();
        wrapper.totalAssets();
        wrapper.convertToShares(x);
        wrapper.convertToAssets(x);
    }

    /// @dev README says the conversions "never revert"; EIP-4626 allows a revert only on overflow
    /// from an unreasonably large input. Documents the overflow bound.
    function test_E1_Bug_convertToSharesRevertsOnLargeInput() public {
        _deposit(alice, 1000e6);
        bool ok = true;
        try wrapper.convertToShares(2e41) returns (uint256) {} catch {
            ok = false;
        }
        assertTrue(ok, "E1: convertToShares reverted");
    }

    function testFuzz_E2_conversionsIndependentOfCaller(address caller, uint256 x) public {
        _deposit(alice, 1000e6);
        _wrap(bob, _mintTTokens(bob, 77e6));
        x = bound(x, 0, 1e30);
        uint256 s = wrapper.convertToShares(x);
        uint256 a = wrapper.convertToAssets(x);
        vm.prank(caller);
        assertEq(wrapper.convertToShares(x), s);
        vm.prank(caller);
        assertEq(wrapper.convertToAssets(x), a);
    }

    /*//////////////////////////////////////////////////////////////
                          E3-E6 LIMITS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_E3_depositUpToMaxDepositSucceeds(uint256 a) public {
        a = bound(a, 0, 1e18);
        assertLe(a, wrapper.maxDeposit(alice));
        _deposit(alice, a);
    }

    /// @dev I9: `maxDeposit` is type(uint256).max but `deposit` overflows above ~1.15e41.
    function test_I9_Bug_maxDepositNotRespected() public {
        uint256 a = 2e41;
        assertLe(a, wrapper.maxDeposit(alice));
        _fundUsdc(alice, a);
        vm.prank(alice);
        usdc.approve(address(wrapper), a);
        bool ok = true;
        vm.prank(alice);
        try wrapper.deposit(a, alice) returns (uint256) {} catch {
            ok = false;
        }
        assertTrue(ok, "I9: deposit <= maxDeposit reverted");
    }

    function testFuzz_E4_redeemUpToMaxRedeemSucceeds(uint256 a, uint256 s) public {
        _deposit(alice, bound(a, 0, 1e13));
        s = bound(s, 0, wrapper.maxRedeem(alice));
        vm.prank(alice);
        wrapper.redeem(s, alice, alice);
    }

    /// @dev I8 (simulated): Takara has lent out all but 1 USDC of its cash. The borrow is
    /// simulated with storage writes (no oracle locally); the exchange rate is unchanged.
    function test_I8_Bug_maxRedeemIgnoresTakaraLiquidity() public {
        _deposit(alice, 1000e6);
        uint256 cash = usdc.balanceOf(address(tToken));
        uint256 rateBefore = _rate();
        stdstore.target(address(tToken)).sig("totalBorrows()").checked_write(cash - 1e6);
        deal(address(usdc), address(tToken), 1e6);
        assertEq(_rate(), rateBefore, "simulation changed the rate");

        uint256 max = wrapper.maxRedeem(alice);
        bool ok = true;
        vm.prank(alice);
        try wrapper.redeem(max, alice, alice) returns (uint256) {} catch {
            ok = false;
        }
        assertTrue(ok, "I8: redeem(maxRedeem) reverted");
    }

    function testFuzz_E5_pausedLimitsAreZero(address who) public {
        _deposit(alice, 1000e6);
        wrapper.pause();
        assertEq(wrapper.maxDeposit(who), 0);
        assertEq(wrapper.maxRedeem(who), 0);
        assertEq(wrapper.maxRedeem(alice), 0);
    }

    function testFuzz_E6_maxMintAndMaxWithdrawAreZero(address who, bool paused_) public {
        _deposit(alice, 1000e6);
        if (paused_) wrapper.pause();
        assertEq(wrapper.maxMint(who), 0);
        assertEq(wrapper.maxWithdraw(who), 0);
        assertEq(wrapper.maxWithdraw(alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                         E7 / E8 EVENTS, ALLOWANCE
    //////////////////////////////////////////////////////////////*/

    function testFuzz_E7_depositAndRedeemEmitEvents(uint256 a) public {
        a = bound(a, 1, 1e13);
        _fundUsdc(alice, a);
        vm.startPrank(alice);
        usdc.approve(address(wrapper), a);
        uint256 expShares = wrapper.previewDeposit(a);
        vm.expectEmit(true, true, false, true, address(wrapper));
        emit Deposit(alice, alice, a, expShares);
        uint256 shares = wrapper.deposit(a, alice);

        uint256 expAssets = wrapper.previewRedeem(shares);
        vm.expectEmit(true, true, true, true, address(wrapper));
        emit Withdraw(alice, bob, alice, expAssets, shares);
        wrapper.redeem(shares, bob, alice);
        vm.stopPrank();
    }

    function testFuzz_E8_redeemByOtherSpendsAllowance(uint256 a, uint256 s, uint256 extra) public {
        uint256 shares = _deposit(alice, bound(a, 1e6, 1e13));
        s = bound(s, 1, shares);
        extra = bound(extra, 0, 1e18);
        vm.prank(bob);
        vm.expectRevert();
        wrapper.redeem(s, bob, alice);

        vm.prank(alice);
        wrapper.approve(bob, s + extra);
        vm.prank(bob);
        wrapper.redeem(s, bob, alice);
        assertEq(wrapper.allowance(alice, bob), extra);
        assertEq(wrapper.balanceOf(alice), shares - s);
    }

    /*//////////////////////////////////////////////////////////////
                        E9-E14 ROUNDING AND PREVIEWS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_E9_conversionsRoundDown(uint256 prior, uint256 wrapped, uint256 x) public {
        _deposit(bob, bound(prior, 0, 1e13));
        _wrap(carol, _mintTTokens(carol, bound(wrapped, 1, 1e13)));
        x = bound(x, 0, 1e15);
        uint256 rate = _rate();
        uint256 s1 = wrapper.totalSupply() + 1;
        uint256 t1 = tToken.balanceOf(address(wrapper)) + 1;
        // shares <= x * 1e18 * S1 / (rate * T1)
        assertLe(wrapper.convertToShares(x) * rate * t1, x * 1e18 * s1, "convertToShares rounds up");
        // assets <= x * T1 * rate / (S1 * 1e18)
        assertLe(wrapper.convertToAssets(x) * s1 * 1e18, x * t1 * rate, "convertToAssets rounds up");
    }

    function testFuzz_E10_E11_depositPreviewAndReturn(uint256 prior, uint256 a, uint256 dt)
        public
    {
        _deposit(bob, bound(prior, 0, 1e13));
        vm.warp(block.timestamp + bound(dt, 0, 365 days));
        a = bound(a, 0, 1e13);
        _fundUsdc(alice, a);
        vm.startPrank(alice);
        usdc.approve(address(wrapper), a);
        uint256 preview = wrapper.previewDeposit(a);
        uint256 before = wrapper.balanceOf(alice);
        uint256 ret = wrapper.deposit(a, alice);
        vm.stopPrank();
        uint256 minted = wrapper.balanceOf(alice) - before;
        assertLe(preview, minted, "E10: previewDeposit > minted");
        assertEq(ret, minted, "E11: deposit return != minted");
    }

    function testFuzz_E12_E13_redeemPreviewAndReturn(uint256 a, uint256 s, uint256 dt) public {
        uint256 shares = _deposit(alice, bound(a, 1, 1e13));
        vm.warp(block.timestamp + bound(dt, 0, 365 days));
        s = bound(s, 0, shares);
        uint256 preview = wrapper.previewRedeem(s);
        uint256 before = usdc.balanceOf(carol);
        vm.prank(alice);
        uint256 ret = wrapper.redeem(s, carol, alice);
        uint256 paid = usdc.balanceOf(carol) - before;
        assertLe(preview, paid, "E12: previewRedeem > paid");
        assertEq(ret, paid, "E13: redeem return != paid");
    }

    function testFuzz_E14_previewEqualsConvert(uint256 prior, uint256 wrapped, uint256 x) public {
        _deposit(bob, bound(prior, 0, 1e13));
        _wrap(carol, _mintTTokens(carol, bound(wrapped, 1, 1e13)));
        x = bound(x, 0, 1e15);
        assertApproxEqAbs(wrapper.previewDeposit(x), wrapper.convertToShares(x), 1);
        assertApproxEqAbs(wrapper.previewRedeem(x), wrapper.convertToAssets(x), 1);
    }

    /*//////////////////////////////////////////////////////////////
                          INFERRED PROPERTIES
    //////////////////////////////////////////////////////////////*/

    function testFuzz_I1_solvency(uint256 a, uint256 t, uint256 donation) public {
        _deposit(alice, bound(a, 0, 1e13));
        _wrap(bob, _mintTTokens(bob, bound(t, 1, 1e13)));
        _donate(carol, _mintTTokens(carol, bound(donation, 1, 1e13)));
        uint256 claimable = _rate() * tToken.balanceOf(address(wrapper)) / 1e18;
        assertLe(wrapper.totalAssets(), claimable);
    }

    function testFuzz_I2_noDepositRedeemRoundTripProfit(uint256 prior, uint256 a) public {
        _deposit(bob, bound(prior, 0, 1e13));
        a = bound(a, 0, 1e13);
        uint256 shares = _deposit(alice, a);
        vm.prank(alice);
        uint256 out = wrapper.redeem(shares, alice, alice);
        assertLe(out, a);
        assertEq(usdc.balanceOf(alice), out);
    }

    function testFuzz_I3_noWrapUnwrapRoundTripProfit(uint256 prior, uint256 t) public {
        _deposit(bob, bound(prior, 0, 1e13));
        uint256 tt = _mintTTokens(alice, bound(t, 1, 1e13));
        uint256 shares = _wrap(alice, tt);
        vm.prank(alice);
        uint256 out = wrapper.unwrap(shares, alice, alice);
        assertLe(out, tt);
    }

    function testFuzz_I4_noStrandedUsdc(uint256 a, uint256 s) public {
        uint256 shares = _deposit(alice, bound(a, 0, 1e13));
        assertEq(usdc.balanceOf(address(wrapper)), 0);
        s = bound(s, 0, shares);
        vm.prank(alice);
        wrapper.redeem(s, alice, alice);
        assertEq(usdc.balanceOf(address(wrapper)), 0);
    }

    function testFuzz_I5_onlyAuthorityIsPrivileged(address caller) public {
        vm.assume(caller != address(this));
        vm.startPrank(caller);
        vm.expectRevert();
        wrapper.pause();
        vm.expectRevert();
        wrapper.setRewardsProxy(caller);
        vm.expectRevert();
        wrapper.claimRewards("");
        vm.stopPrank();

        wrapper.pause();
        vm.prank(caller);
        vm.expectRevert();
        wrapper.unpause();
        wrapper.unpause();
        wrapper.setRewardsProxy(address(0xBEEF));
        assertEq(wrapper.rewardsProxy(), address(0xBEEF));
    }

    function test_I6_cannotReinitialize() public {
        vm.expectRevert();
        wrapper.initialize(address(tToken), manager);
        SpectraWrappedTakara impl = new SpectraWrappedTakara();
        vm.expectRevert();
        impl.initialize(address(tToken), manager);
    }

    /// @dev I7 (simulated borrows): Takara has 25% utilization and a 10% reserve factor, up to
    /// 30 days pass, and the wrapper must still preview the post-accrual result exactly. (Time and
    /// utilization are capped so Takara keeps enough cash to pay the redeem; see I8 otherwise.)
    function testFuzz_I7_previewsExactAfterAccrual(uint256 a, uint256 dt, uint256 s) public {
        uint256 shares = _deposit(alice, 1000e6);
        require(TToken(address(tToken))._setReserveFactor(0.1e18) == 0, "reserve factor");
        uint256 cash = usdc.balanceOf(address(tToken));
        stdstore.target(address(tToken)).sig("totalBorrows()").checked_write(cash / 4);
        deal(address(usdc), address(tToken), cash - cash / 4);
        vm.warp(block.timestamp + bound(dt, 1, 30 days));

        a = bound(a, 0, 1e13);
        _fundUsdc(bob, a);
        vm.startPrank(bob);
        usdc.approve(address(wrapper), a);
        uint256 pDep = wrapper.previewDeposit(a);
        uint256 got = wrapper.deposit(a, bob);
        vm.stopPrank();
        assertEq(got, pDep, "I7: deposit != previewDeposit after accrual");

        s = bound(s, 0, shares);
        uint256 pRed = wrapper.previewRedeem(s);
        vm.prank(alice);
        uint256 paid = wrapper.redeem(s, alice, alice);
        assertEq(paid, pRed, "I7: redeem != previewRedeem after accrual");
        assertEq(usdc.balanceOf(alice), paid);
    }
}
