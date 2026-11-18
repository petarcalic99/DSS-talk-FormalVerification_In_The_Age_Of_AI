/*
 * Certora specification for SpectraWrappedTakara.
 *
 * Property IDs (S* = supplied by the README, I* = inferred by the auditor) refer to PROPERTIES.md.
 *
 * Model:
 *  - `currentContract` is SpectraWrappedTakaraHarness (the wrapper plus view helpers only).
 *  - `usdc` is a standard OpenZeppelin ERC-20 (as in test/utils/LocalDeployment.sol).
 *  - `ttoken` is TTokenMock: a Compound-v2 tToken whose rate is already accrued for the current
 *    block and only ever rises (Takara is trusted), with mint/redeem rounding copied from
 *    Exponential.sol.
 *  - The AccessManager authority is an unresolved external call, summarized NONDET.
 */

using StandardERC20 as usdc;
using TTokenMock as ttoken;

methods {
    // wrapper: state-only views
    function asset() external returns (address) envfree;
    function vaultShare() external returns (address) envfree;
    function totalSupply() external returns (uint256) envfree;
    function balanceOf(address) external returns (uint256) envfree;
    function allowance(address, address) external returns (uint256) envfree;
    function paused() external returns (bool) envfree;
    function totalVaultShares() external returns (uint256) envfree;
    function decimals() external returns (uint8) envfree;
    function maxMint(address) external returns (uint256) envfree;
    function maxWithdraw(address) external returns (uint256) envfree;
    function maxDeposit(address) external returns (uint256) envfree;
    function maxRedeem(address) external returns (uint256) envfree;
    function decimalsOffsetHarness() external returns (uint8) envfree;

    // dependencies
    function usdc.balanceOf(address) external returns (uint256) envfree;
    function usdc.totalSupply() external returns (uint256) envfree;
    function ttoken.balanceOf(address) external returns (uint256) envfree;
    function ttoken.totalSupply() external returns (uint256) envfree;
    function ttoken.underlying() external returns (address) envfree;
    function ttoken.exchangeRateStored() external returns (uint256) envfree;

    // AccessManager authority (Spectra DAO): any answer is possible.
    function _.canCall(address, address, bytes4) external => NONDET;
    function _.consumeScheduledOp(address, bytes) external => NONDET;
}

/*//////////////////////////////////////////////////////////////
                        DEFINITIONS / HELPERS
//////////////////////////////////////////////////////////////*/

definition EPSILON() returns uint256 = 10;

// Functions excluded from parametric rules: the reward claim delegatecalls arbitrary DAO-chosen code
// (trusted per the README), and initialize only runs once on a fresh proxy.
definition excluded(method f) returns bool =
    f.selector == sig:claimRewards(bytes).selector
    || f.selector == sig:initialize(address, address).selector;

/// Wires the wrapper to the modelled USDC and tToken, as `initialize` does.
function setupLinks() {
    require asset() == usdc;
    require vaultShare() == ttoken;
    require ttoken.underlying() == usdc;
    require ttoken.exchangeRateStored() > 0;
    // Bounds that keep the model in realistic ranges (USDC supply < 2^128 wei).
    require usdc.totalSupply() < 2^128;
    require ttoken.totalSupply() < 2^128;
    require ttoken.exchangeRateStored() < 2^100;
    require totalSupply() < 2^128;
}

/// A normal external user (not one of the system contracts).
function isUser(address a) returns bool {
    return a != currentContract && a != usdc && a != ttoken && a != 0;
}

/*//////////////////////////////////////////////////////////////
               S1 — SUPPLY CONSISTENCY (ghost sum of balances)
//////////////////////////////////////////////////////////////*/

ghost mathint sumOfBalances {
    init_state axiom sumOfBalances == 0;
}

// OpenZeppelin ERC20Upgradeable keeps balances in ERC-7201 namespace "openzeppelin.storage.ERC20";
// the conf enables `storage_extension_annotation`, which exposes it as `ext_openzeppelin_storage_ERC20`.
hook Sstore currentContract.ext_openzeppelin_storage_ERC20._balances[KEY address a] uint256 newBal (uint256 oldBal) {
    sumOfBalances = sumOfBalances + newBal - oldBal;
}

hook Sload uint256 bal currentContract.ext_openzeppelin_storage_ERC20._balances[KEY address a] {
    require sumOfBalances >= to_mathint(bal);
}

/// S1: totalSupply == sum of all balances.
invariant totalSupplyIsSumOfBalances()
    to_mathint(totalSupply()) == sumOfBalances
    filtered { f -> !excluded(f) }

/*//////////////////////////////////////////////////////////////
                    S2 — PRICE NEVER DECREASES
//////////////////////////////////////////////////////////////*/

/// S2: no wrapper operation lowers the USDC value of one whole share.
rule priceNeverDecreases(env e, method f, calldataarg args) filtered { f -> !excluded(f) && !f.isView } {
    setupLinks();
    require isUser(e.msg.sender);
    requireInvariant totalSupplyIsSumOfBalances();

    uint256 priceBefore = sharePrice(e);
    f(e, args);
    uint256 priceAfter = sharePrice(e);

    assert priceAfter >= priceBefore, "an operation lowered the value of one whole share";
}

/// S2 (interest): Takara interest accrual (rate rises) does not lower the price either.
rule priceNeverDecreasesOnAccrual(env e, uint256 newRate) {
    setupLinks();
    uint256 priceBefore = sharePrice(e);
    ttoken.accrue(e, newRate);
    uint256 priceAfter = sharePrice(e);
    assert priceAfter >= priceBefore;
}

/*//////////////////////////////////////////////////////////////
                    S3 — PAUSED MEANS CLOSED
//////////////////////////////////////////////////////////////*/

/// S3: deposit reverts while paused.
rule pausedDepositReverts(env e, uint256 assets, address receiver) {
    require paused();
    deposit@withrevert(e, assets, receiver);
    assert lastReverted;
}

/// S3: redeem reverts while paused.
rule pausedRedeemReverts(env e, uint256 shares, address receiver, address owner) {
    require paused();
    redeem@withrevert(e, shares, receiver, owner);
    assert lastReverted;
}

/// S3: both wrap overloads revert while paused.
rule pausedWrapReverts(env e, uint256 vaultShares, address receiver, uint256 minShares, bool withMin) {
    require paused();
    if (withMin) {
        wrap@withrevert(e, vaultShares, receiver, minShares);
    } else {
        wrap@withrevert(e, vaultShares, receiver);
    }
    assert lastReverted;
}

/// S3: both unwrap overloads revert while paused.
rule pausedUnwrapReverts(env e, uint256 shares, address receiver, address owner, uint256 minOut, bool withMin) {
    require paused();
    if (withMin) {
        unwrap@withrevert(e, shares, receiver, owner, minOut);
    } else {
        unwrap@withrevert(e, shares, receiver, owner);
    }
    assert lastReverted;
}

/// I6: share transfers revert while paused.
rule pausedTransfersRevert(env e, method f, calldataarg args) filtered {
    f -> f.selector == sig:transfer(address, uint256).selector
      || f.selector == sig:transferFrom(address, address, uint256).selector
} {
    require paused();
    f@withrevert(e, args);
    assert lastReverted;
}

/*//////////////////////////////////////////////////////////////
              S4 / I8 — DONATIONS DO NOT MOVE THE PRICE
//////////////////////////////////////////////////////////////*/

/// S4: a direct tToken transfer to the wrapper leaves the price of one whole share unchanged.
rule donationDoesNotMovePrice(env e, uint256 amount) {
    setupLinks();
    require isUser(e.msg.sender);

    uint256 priceBefore = sharePrice(e);
    ttoken.transfer(e, currentContract, amount);
    uint256 priceAfter = sharePrice(e);

    assert priceAfter == priceBefore, "a tToken donation changed the share price";
}

/// I8: a direct tToken transfer does not change how many tTokens a holder can unwrap.
rule donationDoesNotChangeBacking(env e, uint256 amount, uint256 shares) {
    setupLinks();
    require isUser(e.msg.sender);
    require !paused();

    uint256 backingBefore = previewUnwrap(e, shares);
    ttoken.transfer(e, currentContract, amount);
    uint256 backingAfter = previewUnwrap(e, shares);

    assert backingAfter == backingBefore;
}

/*//////////////////////////////////////////////////////////////
                         S5 — FAIR DEPOSIT
//////////////////////////////////////////////////////////////*/

/// S5: right after depositing `a` USDC, the shares received are worth at least a − ε USDC.
rule fairDeposit(env e, uint256 assets, address receiver) {
    setupLinks();
    require isUser(e.msg.sender) && isUser(receiver);
    requireInvariant totalSupplyIsSumOfBalances();

    uint256 shares = deposit(e, assets, receiver);
    uint256 worth = previewRedeem(e, shares);

    assert to_mathint(worth) >= assets - EPSILON(), "deposit lost more than epsilon";
}

/// I1: a nonzero deposit never mints zero shares.
rule depositNeverMintsZero(env e, uint256 assets, address receiver) {
    setupLinks();
    require isUser(e.msg.sender) && isUser(receiver);
    require assets > EPSILON();

    uint256 shares = deposit(e, assets, receiver);
    assert shares > 0, "user paid USDC and received no shares";
}

/// I1: a nonzero wrap never mints zero shares.
rule wrapNeverMintsZero(env e, uint256 vaultShares, address receiver) {
    setupLinks();
    require isUser(e.msg.sender) && isUser(receiver);
    require vaultShares > 0;

    uint256 shares = wrap(e, vaultShares, receiver);
    assert shares > 0, "user paid tTokens and received no shares";
}

/*//////////////////////////////////////////////////////////////
                   S6 / S7 — CONVERSIONS (ERC-4626)
//////////////////////////////////////////////////////////////*/

/// S6: asset() never reverts.
rule assetNeverReverts() {
    asset@withrevert();
    assert !lastReverted;
}

/// S6: totalAssets() never reverts.
rule totalAssetsNeverReverts(env e) {
    setupLinks();
    require e.msg.value == 0;
    totalAssets@withrevert(e);
    assert !lastReverted;
}

/// S6: convertToShares never reverts (for any input).
rule convertToSharesNeverReverts(env e, uint256 assets) {
    setupLinks();
    require e.msg.value == 0;
    convertToShares@withrevert(e, assets);
    assert !lastReverted;
}

/// S6: convertToAssets never reverts (for any input).
rule convertToAssetsNeverReverts(env e, uint256 shares) {
    setupLinks();
    require e.msg.value == 0;
    convertToAssets@withrevert(e, shares);
    assert !lastReverted;
}

/// S7: conversions do not depend on the caller.
rule conversionsIndependentOfCaller(env e1, env e2, uint256 x) {
    setupLinks();
    require e1.block.timestamp == e2.block.timestamp && e1.block.number == e2.block.number;

    assert convertToShares(e1, x) == convertToShares(e2, x);
    assert convertToAssets(e1, x) == convertToAssets(e2, x);
}

/*//////////////////////////////////////////////////////////////
                 S8 – S10 — LIMITS (ERC-4626)
//////////////////////////////////////////////////////////////*/

/// S8: deposit respects maxDeposit.
rule depositRespectsMaxDeposit(env e, uint256 assets, address receiver) {
    uint256 limit = maxDeposit(receiver);
    deposit@withrevert(e, assets, receiver);
    assert assets > limit => lastReverted;
}

/// S8: redeem respects maxRedeem.
rule redeemRespectsMaxRedeem(env e, uint256 shares, address receiver, address owner) {
    uint256 limit = maxRedeem(owner);
    redeem@withrevert(e, shares, receiver, owner);
    assert shares > limit => lastReverted;
}

/// S9: maxDeposit and maxRedeem are 0 while paused.
rule maxLimitsZeroWhenPaused(address a) {
    require paused();
    assert maxDeposit(a) == 0;
    assert maxRedeem(a) == 0;
}

/// S10: maxMint and maxWithdraw are always 0; mint and withdraw always revert.
rule mintWithdrawUnsupported(env e, address a, uint256 x, address r, address o, bool doMint) {
    assert maxMint(a) == 0;
    assert maxWithdraw(a) == 0;
    if (doMint) {
        mint@withrevert(e, x, r);
    } else {
        withdraw@withrevert(e, x, r, o);
    }
    assert lastReverted;
}

/// I5: a deposit up to maxDeposit is accepted when the caller has the funds and approval.
rule depositUpToMaxDepositSucceeds(env e, uint256 assets, address receiver) {
    setupLinks();
    require isUser(e.msg.sender) && isUser(receiver);
    require e.msg.value == 0;
    require assets <= maxDeposit(receiver);
    require usdc.balanceOf(e.msg.sender) >= assets;
    require usdc.allowance(e, e.msg.sender, currentContract) >= assets;

    deposit@withrevert(e, assets, receiver);
    assert !lastReverted, "maxDeposit advertised an amount that deposit rejects";
}

/*//////////////////////////////////////////////////////////////
              S12 / I2 — ALLOWANCE SPENT BY THIRD PARTIES
//////////////////////////////////////////////////////////////*/

/// S12: redeem by a non-owner spends the owner's allowance.
rule redeemSpendsAllowance(env e, uint256 shares, address receiver, address owner) {
    setupLinks();
    require e.msg.sender != owner;
    uint256 allowanceBefore = allowance(owner, e.msg.sender);

    redeem(e, shares, receiver, owner);

    uint256 allowanceAfter = allowance(owner, e.msg.sender);
    assert allowanceBefore == max_uint256
        || to_mathint(allowanceAfter) == allowanceBefore - shares;
}

/// I2: unwrap by a non-owner spends the owner's allowance.
rule unwrapSpendsAllowance(env e, uint256 shares, address receiver, address owner) {
    setupLinks();
    require e.msg.sender != owner;
    uint256 allowanceBefore = allowance(owner, e.msg.sender);

    unwrap(e, shares, receiver, owner);

    uint256 allowanceAfter = allowance(owner, e.msg.sender);
    assert allowanceBefore == max_uint256
        || to_mathint(allowanceAfter) == allowanceBefore - shares;
}

/*//////////////////////////////////////////////////////////////
                S13 – S18 — ROUNDING AND PREVIEWS
//////////////////////////////////////////////////////////////*/

/// S13: conversions round down — assets -> shares -> assets never creates assets.
rule conversionRoundTripRoundsDown(env e, uint256 assets) {
    setupLinks();
    uint256 shares = convertToShares(e, assets);
    assert convertToAssets(e, shares) <= assets;
}

/// S14 + S15: previewDeposit <= shares minted, and deposit returns the shares minted.
rule depositMatchesPreview(env e, uint256 assets, address receiver) {
    setupLinks();
    require isUser(e.msg.sender) && isUser(receiver);
    requireInvariant totalSupplyIsSumOfBalances();

    uint256 preview = previewDeposit(e, assets);
    uint256 balBefore = balanceOf(receiver);
    uint256 returned = deposit(e, assets, receiver);
    uint256 balAfter = balanceOf(receiver);

    assert to_mathint(balAfter) - balBefore == to_mathint(returned), "deposit return != shares minted";
    assert preview <= returned, "previewDeposit exceeds shares minted";
}

/// S16 + S17: previewRedeem <= assets paid, and redeem returns the assets paid.
rule redeemMatchesPreview(env e, uint256 shares, address receiver, address owner) {
    setupLinks();
    require isUser(receiver);
    requireInvariant totalSupplyIsSumOfBalances();

    uint256 preview = previewRedeem(e, shares);
    uint256 usdcBefore = usdc.balanceOf(receiver);
    uint256 returned = redeem(e, shares, receiver, owner);
    uint256 usdcAfter = usdc.balanceOf(receiver);

    assert to_mathint(usdcAfter) - usdcBefore == to_mathint(returned), "redeem return != assets paid";
    assert preview <= returned, "previewRedeem exceeds assets paid";
}

/// S18: with no fees the previews equal the reference conversions (when not paused).
rule previewsEqualConversions(env e, uint256 x) {
    setupLinks();
    require !paused();
    assert previewDeposit(e, x) == convertToShares(e, x);
    assert previewRedeem(e, x) == convertToAssets(e, x);
}

/*//////////////////////////////////////////////////////////////
                         S11 — EVENTS
//////////////////////////////////////////////////////////////*/
// S11 (Deposit / Withdraw events) is not expressible with storage-level CVL; it is checked by
// manual review in REPORT.md.

/*//////////////////////////////////////////////////////////////
                   S19 — PRIVILEGED ACCESS
//////////////////////////////////////////////////////////////*/

/// S19: the paused flag only changes through pause() / unpause().
rule pauseOnlyByPauseUnpause(env e, method f, calldataarg args) filtered { f -> !excluded(f) } {
    bool before = paused();
    f(e, args);
    bool after = paused();
    assert before != after =>
        (f.selector == sig:pause().selector || f.selector == sig:unpause().selector);
}

/// S19: the rewards proxy only changes through setRewardsProxy.
rule rewardsProxyOnlyBySetter(env e, method f, calldataarg args) filtered { f -> !excluded(f) } {
    address before = rewardsProxy(e);
    f(e, args);
    address after = rewardsProxy(e);
    assert before != after => f.selector == sig:setRewardsProxy(address).selector;
}

/*//////////////////////////////////////////////////////////////
                I3 / I4 — BACKING AND STRAY USDC
//////////////////////////////////////////////////////////////*/

/// I3: every share is backed — an owner can always unwrap their own balance (the wrapper never
/// runs short of tTokens), as long as the vault is not paused.
rule unwrapOwnBalanceNeverRunsShort(env e, uint256 shares, address receiver) {
    setupLinks();
    requireInvariant totalSupplyIsSumOfBalances();
    require isUser(e.msg.sender) && isUser(receiver);
    require e.msg.value == 0;
    require !paused();
    require shares <= balanceOf(e.msg.sender);
    require ttoken.balanceOf(receiver) + totalVaultShares() < max_uint256;

    unwrap@withrevert(e, shares, receiver, e.msg.sender);
    assert !lastReverted, "wrapper could not pay out the tTokens owed for owned shares";
}

/// I4: deposit and redeem leave the wrapper's own USDC balance unchanged.
rule wrapperUsdcBalanceUnchanged(env e, method f, calldataarg args) filtered {
    f -> f.selector == sig:deposit(uint256, address).selector
      || f.selector == sig:redeem(uint256, address, address).selector
} {
    setupLinks();
    require isUser(e.msg.sender);
    uint256 before = usdc.balanceOf(currentContract);
    f(e, args);
    assert usdc.balanceOf(currentContract) == before;
}
