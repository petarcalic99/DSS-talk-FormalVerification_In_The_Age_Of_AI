// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ComptrollerV2} from "../lib/takara/src/ComptrollerV2.sol";
import {TToken} from "../lib/takara/src/TToken.sol";
import {SpectraWrappedTakara} from "../src/takara/SpectraWrappedTakara.sol";
import {StandardERC20} from "../src/tokens/StandardERC20.sol";
import {LocalDeployment} from "./utils/LocalDeployment.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

interface ITTokenLike is IERC20 {
    function mint(uint256) external returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function exchangeRateCurrent() external returns (uint256);
    function comptroller() external view returns (address);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function getCash() external view returns (uint256);
    function _setReserveFactor(uint256) external returns (uint256);
}

/// @dev Shared fixture: wrapper over the local Takara tUSDC market.
abstract contract WrapperFixture is LocalDeployment {
    using stdStorage for StdStorage;

    StandardERC20 internal usdc;
    ITTokenLike internal tToken;
    SpectraWrappedTakara internal wrapper;
    address internal accessManager;
    ComptrollerV2 internal comptroller;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant MIN_DEP = 1e6; // 1 USDC
    uint256 internal constant MAX_DEP = 1e15; // 1bn USDC

    function setUp() public virtual {
        (address u, address t, address w, address am) = _deployLocal();
        usdc = StandardERC20(u);
        tToken = ITTokenLike(t);
        wrapper = SpectraWrappedTakara(w);
        accessManager = am;
        comptroller = ComptrollerV2(tToken.comptroller());
        vm.label(u, "USDC");
        vm.label(t, "tUSDC");
        vm.label(w, "wrapper");
    }

    function _fundUsdc(address who, uint256 amount) internal {
        deal(address(usdc), who, usdc.balanceOf(who) + amount);
        vm.prank(who);
        usdc.approve(address(wrapper), type(uint256).max);
    }

    function _deposit(address who, uint256 assets) internal returns (uint256 shares) {
        _fundUsdc(who, assets);
        vm.prank(who);
        shares = wrapper.deposit(assets, who);
    }

    /// @dev Gives `who` tTokens by minting them on Takara directly.
    function _fundTTokens(address who, uint256 underlying) internal returns (uint256 got) {
        deal(address(usdc), who, usdc.balanceOf(who) + underlying);
        uint256 before = tToken.balanceOf(who);
        vm.startPrank(who);
        usdc.approve(address(tToken), underlying);
        require(tToken.mint(underlying) == 0, "tToken mint failed");
        tToken.approve(address(wrapper), type(uint256).max);
        vm.stopPrank();
        got = tToken.balanceOf(who) - before;
    }

    /// @dev Puts the market in a borrowing state so interest accrues: outstanding borrows of
    /// `borrows`, a 10% reserve factor (live value is 100%, which makes the rate never move).
    function _activateInterest(uint256 borrows) internal {
        require(tToken._setReserveFactor(0.1e18) == 0, "reserve factor");
        _setBorrows(borrows);
    }

    function _setBorrows(uint256 borrows) internal {
        stdstore.target(address(tToken)).sig("totalBorrows()").checked_write(borrows);
    }
}

/// @dev One or more tests per property in PROPERTIES.md (test names carry the property ID).
contract SpectraWrappedTakaraTest is WrapperFixture {
    // ---------------------------------------------------------------- P1
    function testFuzz_P1_depositMovesFunds(uint256 assets) public {
        assets = bound(assets, MIN_DEP, MAX_DEP);
        _fundUsdc(alice, assets);
        uint256 tBefore = tToken.balanceOf(address(wrapper));
        uint256 tSupplyBefore = tToken.totalSupply();
        vm.prank(alice);
        uint256 shares = wrapper.deposit(assets, bob);
        assertEq(usdc.balanceOf(alice), 0, "caller paid exactly assets");
        assertEq(usdc.balanceOf(address(wrapper)), 0, "no USDC left in wrapper");
        assertEq(
            tToken.balanceOf(address(wrapper)) - tBefore,
            tToken.totalSupply() - tSupplyBefore,
            "all minted tTokens held by wrapper"
        );
        assertEq(wrapper.balanceOf(bob), shares, "receiver got returned shares");
        assertEq(wrapper.balanceOf(alice), 0);
    }

    // ---------------------------------------------------------------- P2
    function testFuzz_P2_redeemPaysReturned(uint256 assets, uint256 frac) public {
        assets = bound(assets, MIN_DEP, MAX_DEP);
        uint256 shares = _deposit(alice, assets);
        uint256 toRedeem = bound(frac, 1, shares);
        uint256 tBefore = tToken.balanceOf(address(wrapper));
        uint256 expectedT = wrapper.previewUnwrap(toRedeem);
        vm.prank(alice);
        uint256 paid = wrapper.redeem(toRedeem, bob, alice);
        assertEq(wrapper.balanceOf(alice), shares - toRedeem, "burned exactly shares");
        assertEq(usdc.balanceOf(bob), paid, "receiver got returned assets");
        assertEq(tBefore - tToken.balanceOf(address(wrapper)), expectedT, "matching tTokens redeemed");
    }

    // ---------------------------------------------------------------- P3
    function testFuzz_P3_wrapUnwrapMoveExactAmounts(uint256 underlying, uint256 frac) public {
        underlying = bound(underlying, MIN_DEP, MAX_DEP);
        uint256 t = _fundTTokens(alice, underlying);
        uint256 tWrapperBefore = tToken.balanceOf(address(wrapper));
        vm.prank(alice);
        uint256 shares = wrapper.wrap(t, alice);
        assertEq(tToken.balanceOf(alice), 0, "took exactly vaultShares");
        assertEq(tToken.balanceOf(address(wrapper)) - tWrapperBefore, t);
        assertEq(wrapper.balanceOf(alice), shares);

        uint256 burn = bound(frac, 1, shares);
        vm.prank(alice);
        uint256 out = wrapper.unwrap(burn, bob, alice);
        assertEq(wrapper.balanceOf(alice), shares - burn, "burned exactly shares");
        assertEq(tToken.balanceOf(bob), out, "receiver got returned tTokens");
    }

    // ---------------------------------------------------------------- P4
    function test_P4_unsupportedFunctionsRevert() public {
        _deposit(alice, 1e9);
        vm.startPrank(alice);
        vm.expectRevert(SpectraWrappedTakara.NotImplemented.selector);
        wrapper.mint(1, alice);
        vm.expectRevert(SpectraWrappedTakara.NotImplemented.selector);
        wrapper.withdraw(1, alice, alice);
        vm.stopPrank();
        vm.expectRevert(SpectraWrappedTakara.NotImplemented.selector);
        wrapper.previewMint(1);
        vm.expectRevert(SpectraWrappedTakara.NotImplemented.selector);
        wrapper.previewWithdraw(1);
    }

    // ---------------------------------------------------------------- P5
    function testFuzz_P5_onlyAuthorityPrivileged(address stranger) public {
        vm.assume(stranger != address(this) && stranger != accessManager);
        vm.startPrank(stranger);
        vm.expectRevert();
        wrapper.pause();
        vm.expectRevert();
        wrapper.setRewardsProxy(stranger);
        vm.stopPrank();

        wrapper.pause(); // authority admin
        assertTrue(wrapper.paused());
        vm.prank(stranger);
        vm.expectRevert();
        wrapper.unpause();
        wrapper.unpause();
        assertFalse(wrapper.paused());
        wrapper.setRewardsProxy(address(0xBEEF));
        assertEq(wrapper.rewardsProxy(), address(0xBEEF));
    }

    // ---------------------------------------------------------------- P6
    function testFuzz_P6_pausedDisablesOperations(uint256 amount) public {
        uint256 shares = _deposit(alice, 1e9);
        uint256 t = _fundTTokens(alice, 1e9);
        amount = bound(amount, 0, shares);
        wrapper.pause();
        _fundUsdc(alice, 1e9);
        vm.startPrank(alice);
        vm.expectRevert();
        wrapper.deposit(amount, alice);
        vm.expectRevert();
        wrapper.redeem(amount, alice, alice);
        vm.expectRevert();
        wrapper.wrap(amount > t ? t : amount, alice);
        vm.expectRevert();
        wrapper.unwrap(amount, alice, alice);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- P7
    function testFuzz_P7_previewDepositExact_noAccrual(uint256 seed, uint256 assets) public {
        _deposit(carol, bound(seed, MIN_DEP, MAX_DEP));
        assets = bound(assets, 1, MAX_DEP);
        uint256 preview = wrapper.previewDeposit(assets);
        _fundUsdc(alice, assets);
        vm.prank(alice);
        uint256 shares = wrapper.deposit(assets, alice);
        assertEq(shares, preview);
        assertEq(wrapper.balanceOf(alice), preview);
    }

    function testFuzz_P7_previewDepositExact_withAccrual(
        uint256 borrows,
        uint256 dt,
        uint256 assets
    ) public {
        _deposit(carol, 1e12);
        _activateInterest(bound(borrows, 1e6, 1e12));
        vm.warp(block.timestamp + bound(dt, 1, 365 days));
        assets = bound(assets, 1, MAX_DEP);
        uint256 stored = tToken.exchangeRateStored();
        uint256 preview = wrapper.previewDeposit(assets);
        _fundUsdc(alice, assets);
        vm.prank(alice);
        uint256 shares = wrapper.deposit(assets, alice);
        assertEq(shares, preview, "preview == deposit");
        assertGt(tToken.exchangeRateStored(), stored, "rate actually accrued");
    }

    // ---------------------------------------------------------------- P8
    function testFuzz_P8_previewRedeemExact_withAccrual(uint256 borrows, uint256 dt, uint256 frac)
        public
    {
        uint256 shares = _deposit(alice, 1e12);
        _activateInterest(bound(borrows, 1e6, 1e12));
        vm.warp(block.timestamp + bound(dt, 1, 365 days));
        uint256 toRedeem = bound(frac, 1, shares);
        uint256 preview = wrapper.previewRedeem(toRedeem);
        // Interest owed by borrowers is not cash; out-of-cash redeems are P13's subject.
        vm.assume(preview <= tToken.getCash());
        vm.prank(alice);
        uint256 paid = wrapper.redeem(toRedeem, alice, alice);
        assertEq(paid, preview, "preview == returned");
        assertEq(usdc.balanceOf(alice), preview, "preview == paid");
    }

    // ---------------------------------------------------------------- P9
    function testFuzz_P9_previewWrapUnwrapExact(uint256 underlying, uint256 frac) public {
        _deposit(carol, 1e12);
        uint256 t = _fundTTokens(alice, bound(underlying, MIN_DEP, MAX_DEP));
        uint256 pw = wrapper.previewWrap(t);
        vm.prank(alice);
        uint256 shares = wrapper.wrap(t, alice);
        assertEq(shares, pw);
        uint256 burn = bound(frac, 1, shares);
        uint256 pu = wrapper.previewUnwrap(burn);
        vm.prank(alice);
        assertEq(wrapper.unwrap(burn, alice, alice), pu);
    }

    // ---------------------------------------------------------------- P10
    function testFuzz_P10_viewsNeverRevert(uint256 x, bool paused_) public {
        _deposit(carol, 1e12);
        if (paused_) wrapper.pause();
        wrapper.asset();
        wrapper.totalAssets();
        try wrapper.convertToShares(x) {}
        catch {
            assertTrue(false, "convertToShares reverted");
        }
        try wrapper.convertToAssets(x) {}
        catch {
            assertTrue(false, "convertToAssets reverted");
        }
    }

    function test_P10_viewsNeverRevert_whilePaused_realisticInputs() public {
        _deposit(carol, 1e12);
        wrapper.pause();
        wrapper.asset();
        wrapper.totalAssets();
        wrapper.convertToShares(1e12);
        wrapper.convertToAssets(1e12);
    }

    function test_P10_convertToSharesMaxInput() public {
        _deposit(carol, 1e12);
        try wrapper.convertToShares(type(uint256).max) {}
        catch {
            assertTrue(false, "convertToShares(max) reverted");
        }
    }

    // ---------------------------------------------------------------- P11
    function testFuzz_P11_conversionsCallerIndependent(address a, address b, uint256 x) public {
        _deposit(carol, 1e12);
        x = bound(x, 0, MAX_DEP);
        vm.prank(a);
        uint256 s1 = wrapper.convertToShares(x);
        uint256 a1 = wrapper.convertToAssets(x);
        vm.prank(b);
        uint256 s2 = wrapper.convertToShares(x);
        vm.prank(b);
        uint256 a2 = wrapper.convertToAssets(x);
        assertEq(s1, s2);
        assertEq(a1, a2);
    }

    // ---------------------------------------------------------------- P12
    function test_P12_maxDepositZeroWhilePaused() public {
        wrapper.pause();
        assertEq(wrapper.maxDeposit(alice), 0);
    }

    function test_P12_maxDepositRespected_takaraMintPaused() public {
        comptroller._setMintPaused(TToken(address(tToken)), true);
        uint256 max = wrapper.maxDeposit(alice);
        uint256 assets = 1e9;
        _fundUsdc(alice, assets);
        vm.prank(alice);
        try wrapper.deposit(assets, alice) {}
        catch {
            assertLe(assets, max, "amount within maxDeposit");
            assertTrue(false, "deposit within maxDeposit reverted (Takara mint paused)");
        }
    }

    function test_P12_maxDepositRespected_supplyCap() public {
        TToken[] memory ts = new TToken[](1);
        ts[0] = TToken(address(tToken));
        uint256[] memory caps = new uint256[](1);
        caps[0] = tToken.getCash() + 1e9; // room for < 1,000 USDC
        comptroller._setMarketSupplyCaps(ts, caps);
        uint256 max = wrapper.maxDeposit(alice);
        uint256 assets = 2e9;
        assertLe(assets, max, "2,000 USDC within maxDeposit");
        _fundUsdc(alice, assets);
        vm.prank(alice);
        try wrapper.deposit(assets, alice) {}
        catch {
            assertTrue(false, "deposit within maxDeposit reverted (supply cap)");
        }
    }

    function test_P12_maxDepositRespected_maxAmount() public {
        uint256 max = wrapper.maxDeposit(alice);
        // Even ignoring funds, the amount itself breaks the share computation.
        try wrapper.previewDeposit(max) {}
        catch {
            assertTrue(false, "previewDeposit(maxDeposit) reverts: deposit(maxDeposit) cannot succeed");
        }
    }

    // ---------------------------------------------------------------- P13
    function test_P13_maxRedeemZeroWhilePaused() public {
        _deposit(alice, 1e9);
        wrapper.pause();
        assertEq(wrapper.maxRedeem(alice), 0);
    }

    function test_P13_maxRedeemRespected_lowTakaraCash() public {
        uint256 shares = _deposit(alice, 1e12);
        // Market lent out almost all of its cash (high utilization): borrows replace the cash.
        uint256 cash = tToken.getCash();
        _setBorrows(cash - 1e6);
        deal(address(usdc), address(tToken), 1e6);
        uint256 max = wrapper.maxRedeem(alice);
        assertEq(max, shares, "maxRedeem reports the full balance");
        vm.prank(alice);
        try wrapper.redeem(max, alice, alice) {}
        catch {
            assertTrue(false, "redeem(maxRedeem) reverted (Takara out of cash)");
        }
    }

    function test_P13_maxRedeemRespected_takaraRedeemPaused() public {
        uint256 shares = _deposit(alice, 1e9);
        comptroller._setRedeemPaused(TToken(address(tToken)), true);
        uint256 max = wrapper.maxRedeem(alice);
        assertEq(max, shares);
        vm.prank(alice);
        try wrapper.redeem(max, alice, alice) {}
        catch {
            assertTrue(false, "redeem(maxRedeem) reverted (Takara redeem paused)");
        }
    }

    // ---------------------------------------------------------------- P14
    function testFuzz_P14_maxMintWithdrawZero(bool paused_, address who) public {
        _deposit(alice, 1e9);
        if (paused_) wrapper.pause();
        assertEq(wrapper.maxMint(who), 0);
        assertEq(wrapper.maxWithdraw(who), 0);
        assertEq(wrapper.maxWithdraw(alice), 0);
    }

    // ---------------------------------------------------------------- P15
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    function testFuzz_P15_events(uint256 assets) public {
        assets = bound(assets, MIN_DEP, MAX_DEP);
        _fundUsdc(alice, assets);
        uint256 expShares = wrapper.previewDeposit(assets);
        vm.expectEmit(true, true, false, true, address(wrapper));
        emit Deposit(alice, bob, assets, expShares);
        vm.prank(alice);
        wrapper.deposit(assets, bob);

        uint256 expAssets = wrapper.previewRedeem(expShares);
        vm.expectEmit(true, true, true, true, address(wrapper));
        emit Withdraw(bob, carol, bob, expAssets, expShares);
        vm.prank(bob);
        wrapper.redeem(expShares, carol, bob);
        assertEq(usdc.balanceOf(carol), expAssets);
    }

    // ---------------------------------------------------------------- P16
    function testFuzz_P16_redeemSpendsAllowance(uint256 allowance_, uint256 frac) public {
        uint256 shares = _deposit(alice, 1e12);
        uint256 toRedeem = bound(frac, 1, shares);
        allowance_ = bound(allowance_, toRedeem, type(uint256).max - 1);
        vm.prank(alice);
        wrapper.approve(bob, allowance_);
        vm.prank(bob);
        wrapper.redeem(toRedeem, bob, alice);
        assertEq(wrapper.allowance(alice, bob), allowance_ - toRedeem);
    }

    function testFuzz_P16_redeemWithoutAllowanceReverts(uint256 allowance_, uint256 frac) public {
        uint256 shares = _deposit(alice, 1e12);
        uint256 toRedeem = bound(frac, 1, shares);
        allowance_ = bound(allowance_, 0, toRedeem - 1);
        vm.prank(alice);
        wrapper.approve(bob, allowance_);
        vm.prank(bob);
        vm.expectRevert();
        wrapper.redeem(toRedeem, bob, alice);
    }

    // ---------------------------------------------------------------- P17
    function testFuzz_P17_conversionsRoundDown(uint256 seed, uint256 x, uint256 dt) public {
        _deposit(carol, bound(seed, MIN_DEP, MAX_DEP));
        _activateInterest(1e11);
        vm.warp(block.timestamp + bound(dt, 0, 30 days));
        x = bound(x, 0, MAX_DEP);
        uint256 rate = tToken.exchangeRateCurrent(); // accrue so the stored rate is exact
        uint256 S = wrapper.totalSupply() + 1;
        uint256 T = tToken.balanceOf(address(wrapper)) + 1;
        // shares <= assets * 1e18 / rate * S / T  <=>  shares * rate * T <= assets * 1e18 * S
        uint256 sh = wrapper.convertToShares(x);
        assertLe(sh * rate * T, x * 1e18 * S, "convertToShares rounds down");
        // assets <= shares * T / S * rate / 1e18  <=>  assets * S * 1e18 <= shares * T * rate
        uint256 as_ = wrapper.convertToAssets(x);
        assertLe(as_ * S * 1e18, x * T * rate, "convertToAssets rounds down");
    }

    // ---------------------------------------------------------------- P18
    function testFuzz_P18_previewsEqualConversions(uint256 x, uint256 dt) public {
        _deposit(carol, 1e12);
        _activateInterest(1e11);
        vm.warp(block.timestamp + bound(dt, 0, 365 days));
        x = bound(x, 0, MAX_DEP);
        assertEq(wrapper.previewDeposit(x), wrapper.convertToShares(x));
        assertEq(wrapper.previewRedeem(x), wrapper.convertToAssets(x));
    }

    // ---------------------------------------------------------------- P20
    function testFuzz_P20_noRoundTripProfit(uint256 seed, uint256 assets, uint256 donation)
        public
    {
        _deposit(carol, bound(seed, MIN_DEP, MAX_DEP));
        // Optional tToken donation to move the wrapper's share price off 1:1.
        uint256 d = bound(donation, 0, 1e12);
        if (d > 0) {
            uint256 t = _fundTTokens(carol, d);
            vm.prank(carol);
            tToken.transfer(address(wrapper), t);
        }
        assets = bound(assets, 1, MAX_DEP);
        uint256 shares = _deposit(alice, assets);
        if (shares > 0) {
            vm.prank(alice);
            uint256 back = wrapper.redeem(shares, alice, alice);
            assertLe(back, assets, "deposit->redeem profit");
        }
        uint256 tIn = _fundTTokens(bob, assets < MIN_DEP ? MIN_DEP : assets);
        vm.prank(bob);
        uint256 s2 = wrapper.wrap(tIn, bob);
        if (s2 > 0) {
            vm.prank(bob);
            assertLe(wrapper.unwrap(s2, bob, bob), tIn, "wrap->unwrap profit");
        }
    }

    // ---------------------------------------------------------------- P21
    function test_P21_donationCannotZeroOutDeposit() public {
        // Attacker is first in an empty wrapper with 1 wei of tToken, then donates tTokens.
        address attacker = makeAddr("attacker");
        uint256 t = _fundTTokens(attacker, 20_001e6); // ~19,168 tTokens
        vm.startPrank(attacker);
        wrapper.wrap(1, attacker);
        tToken.transfer(address(wrapper), t - 1);
        vm.stopPrank();

        // Victim deposits 10,000 USDC (non-dust) right after.
        uint256 victimAssets = 10_000e6;
        uint256 shares = _deposit(alice, victimAssets);
        emit log_named_uint("victim shares", shares);
        emit log_named_uint("victim redeemable USDC", wrapper.previewRedeem(wrapper.balanceOf(alice)));
        emit log_named_uint("attacker spent USDC", 20_001e6);
        emit log_named_uint("attacker redeemable USDC", wrapper.previewRedeem(wrapper.balanceOf(attacker)));
        assertGt(shares, 0, "victim's 10,000 USDC deposit minted zero shares");
    }

    // ---------------------------------------------------------------- P22
    function testFuzz_P22_noValueForNothing_deposit(uint256 assets) public {
        _deposit(carol, 1e12);
        assets = bound(assets, 1, 10);
        uint256 shares = _deposit(alice, assets);
        assertGt(shares, 0, "deposit took USDC but minted zero shares");
    }

    function testFuzz_P22_noValueForNothing_redeem(uint256 seed, uint256 shares) public {
        _deposit(carol, bound(seed, MIN_DEP, MAX_DEP));
        _deposit(alice, 1e9);
        shares = bound(shares, 1, 10);
        vm.prank(alice);
        uint256 paid = wrapper.redeem(shares, alice, alice);
        assertGt(paid, 0, "redeem burned shares but paid zero USDC");
    }

    // ---------------------------------------------------------------- P23
    function test_P23_noReinitialisation() public {
        vm.expectRevert();
        wrapper.initialize(address(tToken), address(this));
        SpectraWrappedTakara impl = new SpectraWrappedTakara();
        vm.expectRevert();
        impl.initialize(address(tToken), address(this));
    }
}

/// @dev Stateful handler for P7/P8/P9 (previews exact under random sequences and interest
/// accrual) and P19 (solvency).
contract Handler is WrapperFixture {
    address[] internal actors;
    bool public previewMismatch;
    string public mismatchWhat;

    constructor(
        StandardERC20 usdc_,
        ITTokenLike tToken_,
        SpectraWrappedTakara wrapper_,
        address[] memory actors_
    ) {
        usdc = usdc_;
        tToken = tToken_;
        wrapper = wrapper_;
        actors = actors_;
    }

    function setUp() public override {}

    function actorList() external view returns (address[] memory) {
        return actors;
    }

    function _actor(uint256 i) internal view returns (address) {
        return actors[i % actors.length];
    }

    function deposit(uint256 i, uint256 assets) external {
        address a = _actor(i);
        assets = bound(assets, 1, MAX_DEP);
        _fundUsdc(a, assets);
        uint256 p = wrapper.previewDeposit(assets);
        vm.prank(a);
        uint256 s = wrapper.deposit(assets, a);
        if (s != p) _flag("deposit");
    }

    function redeem(uint256 i, uint256 shares) external {
        address a = _actor(i);
        uint256 bal = wrapper.balanceOf(a);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);
        uint256 p = wrapper.previewRedeem(shares);
        uint256 before = usdc.balanceOf(a);
        vm.prank(a);
        uint256 r = wrapper.redeem(shares, a, a);
        if (r != p || usdc.balanceOf(a) - before != p) _flag("redeem");
    }

    function wrap(uint256 i, uint256 underlying) external {
        address a = _actor(i);
        uint256 t = _fundTTokens(a, bound(underlying, MIN_DEP, MAX_DEP));
        uint256 p = wrapper.previewWrap(t);
        vm.prank(a);
        if (wrapper.wrap(t, a) != p) _flag("wrap");
    }

    function unwrap(uint256 i, uint256 shares) external {
        address a = _actor(i);
        uint256 bal = wrapper.balanceOf(a);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);
        uint256 p = wrapper.previewUnwrap(shares);
        vm.prank(a);
        if (wrapper.unwrap(shares, a, a) != p) _flag("unwrap");
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 1, 30 days));
    }

    function _flag(string memory what) internal {
        previewMismatch = true;
        mismatchWhat = what;
    }
}

contract SpectraWrappedTakaraInvariantTest is WrapperFixture {
    Handler internal handler;

    function setUp() public override {
        super.setUp();
        _activateInterest(1e11);
        address[] memory as_ = new address[](3);
        as_[0] = alice;
        as_[1] = bob;
        as_[2] = carol;
        handler = new Handler(usdc, tToken, wrapper, as_);
        targetContract(address(handler));
        bytes4[] memory sels = new bytes4[](5);
        sels[0] = Handler.deposit.selector;
        sels[1] = Handler.redeem.selector;
        sels[2] = Handler.wrap.selector;
        sels[3] = Handler.unwrap.selector;
        sels[4] = Handler.warp.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: sels}));
    }

    /// P7/P8/P9 over random sequences with interest accrual.
    function invariant_P7_P8_P9_previewsExact() public view {
        assertFalse(handler.previewMismatch(), handler.mismatchWhat());
    }

    /// P19: the wrapper's tTokens cover every holder's unwrap claim.
    function invariant_P19_solvency() public view {
        address[] memory as_ = handler.actorList();
        uint256 claims;
        for (uint256 k; k < as_.length; k++) {
            claims += Math.mulDiv(
                wrapper.balanceOf(as_[k]),
                tToken.balanceOf(address(wrapper)) + 1,
                wrapper.totalSupply() + 1
            );
        }
        assertLe(claims, tToken.balanceOf(address(wrapper)));
    }
}
