/*
 * Certora specification for SpectraWrappedTakara (+ Spectra4626Wrapper).
 * Each rule is tagged with the property id from PROPERTIES.md.
 *
 * Model:
 *  - currentContract : SpectraWrappedTakaraHarness (munged only to expose private rate math)
 *  - tToken          : the real Takara TErc20Delegate code (used directly as the market)
 *  - underlying      : StandardERC20 (OpenZeppelin ERC20)
 *  - Interest rate model: deterministic ghost function (it is a pure view of cash/borrows/reserves)
 *  - Comptroller hooks: NONDET (may allow or reject)
 *  - AccessManager.canCall: ghost permission table with zero delay
 */

using TErc20Delegate as tToken;
using StandardERC20 as underlying;

methods {
    // ---- wrapper (envfree views) ----
    function vaultShare() external returns (address) envfree;
    function asset() external returns (address) envfree;
    function totalSupply() external returns (uint256) envfree;
    function balanceOf(address) external returns (uint256) envfree;
    function allowance(address, address) external returns (uint256) envfree;
    function paused() external returns (bool) envfree;
    function totalVaultShares() external returns (uint256) envfree;
    function authority() external returns (address) envfree;
    function maxMint(address) external returns (uint256) envfree;
    function maxWithdraw(address) external returns (uint256) envfree;
    function divScalarByExpTruncate(uint256, uint256) external returns (uint256) envfree;
    function mulScalarTruncate(uint256, uint256) external returns (uint256) envfree;

    // ---- tToken / underlying ----
    function tToken.balanceOf(address) external returns (uint256) envfree;
    function tToken.totalSupply() external returns (uint256) envfree;
    function tToken.underlying() external returns (address) envfree;
    function tToken.accrualBlockTimestamp() external returns (uint256) envfree;
    function underlying.balanceOf(address) external returns (uint256) envfree;

    // ---- external calls made through interfaces ----
    function _.mint(uint256) external => DISPATCHER(true);
    function _.redeem(uint256) external => DISPATCHER(true);
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);
    function _.totalSupply() external => DISPATCHER(true);
    function _.decimals() external => DISPATCHER(true);
    function _.exchangeRateStored() external => DISPATCHER(true);
    function _.accrualBlockTimestamp() external => DISPATCHER(true);
    function _.getCash() external => DISPATCHER(true);
    function _.totalBorrows() external => DISPATCHER(true);
    function _.totalReserves() external => DISPATCHER(true);
    function _.reserveFactorMantissa() external => DISPATCHER(true);
    function _.interestRateModel() external => DISPATCHER(true);
    function _.underlying() external => DISPATCHER(true);

    // Interest rate model: deterministic function of market state
    function _.getBorrowRate(uint256 c, uint256 b, uint256 r) external => borrowRateGhost(c, b, r) expect uint256;

    // Comptroller policy hooks: arbitrary answers
    function _.mintAllowed(address, address, uint256) external => NONDET;
    function _.redeemAllowed(address, address, uint256) external => NONDET;
    function _.redeemVerify(address, address, uint256, uint256) external => NONDET;
    function _.transferAllowed(address, address, address, uint256) external => NONDET;

    // AccessManager
    function _.canCall(address caller, address target, bytes4 selector) external
        => canCallCVL(caller, target, selector) expect (bool, uint32);
    function _.consumeScheduledOp(address, bytes) external => NONDET;

    // Rewards proxy is an arbitrary delegatecall target; keep it opaque
    function _.claimRewards(bytes) external => NONDET;
}

/* ------------------------------------------------------------------ */
/* Ghosts and helpers                                                 */
/* ------------------------------------------------------------------ */

ghost borrowRateGhost(uint256, uint256, uint256) returns uint256;

ghost mapping(address => mapping(bytes4 => bool)) authorized;

function canCallCVL(address caller, address target, bytes4 selector) returns (bool, uint32) {
    return (authorized[caller][selector], 0);
}

definition RATE_SCALE() returns uint256 = 10^18;

/// Wiring of the system as deployed by `initialize`.
function setup(env e) {
    require vaultShare() == tToken;
    require asset() == underlying;
    require tToken.underlying() == underlying;
    require e.msg.sender != currentContract;
    require e.msg.sender != tToken;
    require e.msg.value == 0;
}

/* ------------------------------------------------------------------ */
/* Exchange-rate parity                                               */
/* ------------------------------------------------------------------ */

/// P1: view rate == rate stored by the tToken after accrueInterest() in the same block.
rule P1_exchangeRateMatchesAccrual(env e) {
    setup(e);
    uint256 viewRate = currentExchangeRate(e);

    uint256 err = tToken.accrueInterest(e);
    require err == 0;

    assert tToken.exchangeRateStored(e) == viewRate;
}

/// P2: deposit delivers exactly the predicted tTokens to the wrapper.
rule P2_depositTTokenParity(env e, uint256 assets, address receiver) {
    setup(e);
    uint256 predicted = divScalarByExpTruncate(assets, currentExchangeRate(e));
    uint256 before = tToken.balanceOf(currentContract);

    deposit(e, assets, receiver);

    assert to_mathint(tToken.balanceOf(currentContract)) == before + predicted;
}

/// P3: redeem sends exactly previewRedeem(shares) underlying to the receiver.
rule P3_redeemAssetParity(env e, uint256 shares, address receiver, address owner) {
    setup(e);
    require receiver != currentContract && receiver != tToken;
    uint256 preview = previewRedeem(e, shares);
    uint256 before = underlying.balanceOf(receiver);

    redeem(e, shares, receiver, owner);

    assert to_mathint(underlying.balanceOf(receiver)) == before + preview;
}

/* ------------------------------------------------------------------ */
/* ERC-4626 accounting                                                */
/* ------------------------------------------------------------------ */

/// P4: deposit mints exactly the returned shares, to the receiver only.
rule P4_depositMintsReturnedShares(env e, uint256 assets, address receiver, address other) {
    setup(e);
    require other != receiver;
    uint256 balR = balanceOf(receiver);
    uint256 balO = balanceOf(other);
    uint256 supply = totalSupply();

    uint256 shares = deposit(e, assets, receiver);

    assert to_mathint(balanceOf(receiver)) == balR + shares;
    assert to_mathint(totalSupply()) == supply + shares;
    assert balanceOf(other) == balO;
}

/// P5: deposit leaves the wrapper's own underlying balance unchanged.
rule P5_depositKeepsNoUnderlying(env e, uint256 assets, address receiver) {
    setup(e);
    uint256 before = underlying.balanceOf(currentContract);

    deposit(e, assets, receiver);

    assert underlying.balanceOf(currentContract) == before;
}

/// P6: redeem burns exactly `shares` from owner and from total supply.
rule P6_redeemBurnsShares(env e, uint256 shares, address receiver, address owner) {
    setup(e);
    uint256 balOwner = balanceOf(owner);
    uint256 supply = totalSupply();

    redeem(e, shares, receiver, owner);

    assert to_mathint(balanceOf(owner)) == balOwner - shares;
    assert to_mathint(totalSupply()) == supply - shares;
}

/// P7: the value returned by redeem equals what the receiver actually got.
rule P7_redeemReturnValueIsHonest(env e, uint256 shares, address receiver, address owner) {
    setup(e);
    require receiver != currentContract && receiver != tToken;
    uint256 before = underlying.balanceOf(receiver);

    uint256 assets = redeem(e, shares, receiver, owner);

    assert to_mathint(underlying.balanceOf(receiver)) == before + assets;
}

/// P8: a non-zero deposit that mints zero shares must revert. (Expected to be VIOLATED.)
rule P8_noZeroShareDeposit(env e, uint256 assets, address receiver) {
    setup(e);
    uint256 shares = deposit(e, assets, receiver);
    assert assets > 0 => shares > 0;
}

/// P9: deposit-then-redeem never returns more than was deposited.
rule P9_roundTripNoProfit(env e, uint256 assets) {
    setup(e);
    address user = e.msg.sender;
    require user != tToken && user != currentContract;

    uint256 shares = deposit(e, assets, user);
    uint256 out = redeem(e, shares, user, user);

    assert out <= assets;
}

/// P10: (V+1)/(S+1) never decreases across deposit / redeem / wrap / unwrap.
rule P10_backingPerShareNonDecreasing(env e, method f, calldataarg args) filtered {
    f -> f.selector == sig:deposit(uint256, address).selector
      || f.selector == sig:redeem(uint256, address, address).selector
      || f.selector == sig:wrap(uint256, address).selector
      || f.selector == sig:wrap(uint256, address, uint256).selector
      || f.selector == sig:unwrap(uint256, address, address).selector
      || f.selector == sig:unwrap(uint256, address, address, uint256).selector
} {
    setup(e);
    mathint v0 = totalVaultShares();
    mathint s0 = totalSupply();

    f(e, args);

    mathint v1 = totalVaultShares();
    mathint s1 = totalSupply();
    assert (v1 + 1) * (s0 + 1) >= (v0 + 1) * (s1 + 1);
}

/* ------------------------------------------------------------------ */
/* ERC-4626 limits                                                    */
/* ------------------------------------------------------------------ */

/// P11: amounts within maxDeposit can be previewed. (Expected to be VIOLATED: scalar*1e36 overflow.)
rule P11_maxDepositIsPreviewable(env e, uint256 assets, address receiver) {
    setup(e);
    require !paused();
    require assets <= maxDeposit(e, receiver);

    previewDeposit@withrevert(e, assets);

    assert !lastReverted;
}

/// P12: redeeming within maxRedeem never needs more cash than Takara holds. (Expected to be VIOLATED.)
rule P12_maxRedeemRespectsLiquidity(env e, uint256 shares, address owner) {
    setup(e);
    require shares <= maxRedeem(e, owner);

    assert previewRedeem(e, shares) <= tToken.getCash(e);
}

/// P13: mint / withdraw / previewMint / previewWithdraw always revert.
rule P13_unimplementedAlwaysRevert(env e, method f, calldataarg args) filtered {
    f -> f.selector == sig:mint(uint256, address).selector
      || f.selector == sig:withdraw(uint256, address, address).selector
      || f.selector == sig:previewMint(uint256).selector
      || f.selector == sig:previewWithdraw(uint256).selector
} {
    f@withrevert(e, args);
    assert lastReverted;
}

/// P13: maxMint and maxWithdraw are always zero.
rule P13_maxMintMaxWithdrawZero(address a) {
    assert maxMint(a) == 0 && maxWithdraw(a) == 0;
}

/* ------------------------------------------------------------------ */
/* Wrap / unwrap                                                      */
/* ------------------------------------------------------------------ */

/// P14: wrap moves exactly v tTokens in and mints previewWrap(v) to the receiver.
rule P14_wrapExact(env e, uint256 v, address receiver) {
    setup(e);
    uint256 preview = previewWrap(e, v);
    uint256 vault0 = totalVaultShares();
    uint256 bal0 = balanceOf(receiver);

    uint256 minted = wrap(e, v, receiver);

    assert minted == preview;
    assert to_mathint(totalVaultShares()) == vault0 + v;
    assert to_mathint(balanceOf(receiver)) == bal0 + minted;
}

/// P15: unwrap burns s shares from owner and sends previewUnwrap(s) tTokens to the receiver.
rule P15_unwrapExact(env e, uint256 s, address receiver, address owner) {
    setup(e);
    require receiver != currentContract;
    uint256 preview = previewUnwrap(e, s);
    uint256 owner0 = balanceOf(owner);
    uint256 recv0 = tToken.balanceOf(receiver);

    uint256 out = unwrap(e, s, receiver, owner);

    assert out == preview;
    assert to_mathint(balanceOf(owner)) == owner0 - s;
    assert to_mathint(tToken.balanceOf(receiver)) == recv0 + out;
}

/* ------------------------------------------------------------------ */
/* Authorization                                                      */
/* ------------------------------------------------------------------ */

/// P16: third-party redeem/unwrap consumes allowance (and cannot exceed it).
rule P16_thirdPartySpendsAllowance(env e, method f, uint256 shares, address receiver, address owner) filtered {
    f -> f.selector == sig:redeem(uint256, address, address).selector
      || f.selector == sig:unwrap(uint256, address, address).selector
} {
    setup(e);
    require e.msg.sender != owner;
    uint256 allow0 = allowance(owner, e.msg.sender);

    if (f.selector == sig:redeem(uint256, address, address).selector) {
        redeem(e, shares, receiver, owner);
    } else {
        unwrap(e, shares, receiver, owner);
    }

    assert shares <= allow0;
    assert allow0 != max_uint256 => to_mathint(allowance(owner, e.msg.sender)) == allow0 - shares;
}

/// P17: restricted functions revert unless the AccessManager authorizes the caller.
rule P17_restrictedFunctions(env e, method f, calldataarg args) filtered {
    f -> f.selector == sig:pause().selector
      || f.selector == sig:unpause().selector
      || f.selector == sig:setRewardsProxy(address).selector
      || f.selector == sig:claimRewards(bytes).selector
} {
    setup(e);
    bool allowed = authorized[e.msg.sender][to_bytes4(f.selector)];

    f@withrevert(e, args);

    assert !lastReverted => allowed;
}

/* ------------------------------------------------------------------ */
/* Pause                                                              */
/* ------------------------------------------------------------------ */

/// P18: user-facing state changes revert while paused.
rule P18_pausedBlocksUserActions(env e, method f, calldataarg args) filtered {
    f -> f.selector == sig:deposit(uint256, address).selector
      || f.selector == sig:redeem(uint256, address, address).selector
      || f.selector == sig:wrap(uint256, address).selector
      || f.selector == sig:wrap(uint256, address, uint256).selector
      || f.selector == sig:unwrap(uint256, address, address).selector
      || f.selector == sig:unwrap(uint256, address, address, uint256).selector
      || f.selector == sig:transfer(address, uint256).selector
      || f.selector == sig:transferFrom(address, address, uint256).selector
} {
    setup(e);
    require paused();

    f@withrevert(e, args);

    assert lastReverted;
}

/// P19: limits are zero while paused.
rule P19_pausedLimitsZero(env e, address a) {
    require paused();
    assert maxDeposit(e, a) == 0 && maxRedeem(e, a) == 0;
}
