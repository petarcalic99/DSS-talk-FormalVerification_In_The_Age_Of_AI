/*
 * P8 follow-up CVL rules (excerpt of certora/specs/SpectraWrappedTakara.spec, lines 277-355).
 * Not standalone: they use the methods block, setup(), boundedState(), BOUND() and E18() from that spec.
 * Prover results:
 *   P8a_nonDustZeroShareNeedsInflatedBacking  VERIFIED (not vacuous)
 *   P8b_normalBackingLossIsDust               VERIFIED (not vacuous)
 *   P8c_largeDepositWipedOutWitness            witness FOUND (with assets > 0, rate > 0)
 *   P8d_attackerProfitTwoVictimsWitness        TIMEOUT (see P8_EXPLOIT_REPORT.md, section 3)
 */

/// P8 investigation. Fresh live market, realistic sizes. r = rate the mint uses, V = wrapper tTokens,
/// S = wrapper shares, all read before the deposit.
function p8Setup(env e, uint256 assets) {
    setup(e);
    boundedState(e, assets);
    require e.msg.sender != tToken && e.msg.sender != currentContract;
    require tToken.totalSupply() > 0;
    require tToken.accrualBlockTimestamp() == e.block.timestamp;
}

/// P8a: a zero-share deposit that is more than dust (mints >= 1 tToken) needs inflated backing (V > S).
rule P8a_nonDustZeroShareNeedsInflatedBacking(env e, uint256 assets, address receiver) {
    p8Setup(e, assets);
    mathint r = currentExchangeRate(e);
    mathint V = totalVaultShares();
    mathint S = totalSupply();

    uint256 sh = deposit(e, assets, receiver);

    assert (sh == 0 && assets * E18() >= r) => V > S;
}

/// P8b: with normal backing (< 2 tTokens per share), a zero-share deposit is dust: assets*1e18 < 2*rate.
rule P8b_normalBackingLossIsDust(env e, uint256 assets, address receiver) {
    p8Setup(e, assets);
    mathint r = currentExchangeRate(e);
    mathint V = totalVaultShares();
    mathint S = totalSupply();
    require V + 1 < 2 * (S + 1);

    uint256 sh = deposit(e, assets, receiver);

    assert sh == 0 => assets * E18() < 2 * r;
}

/// P8c (witness): a large deposit (>= 1e6 tTokens worth) can be wiped out entirely when backing is inflated.
rule P8c_largeDepositWipedOutWitness(env e, uint256 assets, address receiver) {
    p8Setup(e, assets);
    mathint r = currentExchangeRate(e);
    require r > 0 && assets > 0;

    uint256 sh = deposit(e, assets, receiver);

    satisfy sh == 0 && assets * E18() >= 10^6 * r;
}

/// P8 follow-up (witness): on an empty wrapper, an attacker who deposits, donates tTokens directly,
/// and holds while two victims each get 0 shares ends with MORE underlying than they started with.
/// All transactions in the same block of a fresh, live market.
rule P8d_attackerProfitTwoVictimsWitness(env eA, env eV1, env eV2,
        uint256 a0, uint256 d, uint256 x1, uint256 x2) {
    address att = eA.msg.sender;
    address v1 = eV1.msg.sender;
    address v2 = eV2.msg.sender;
    p8Setup(eA, d);
    require eV1.block.timestamp == eA.block.timestamp && eV2.block.timestamp == eA.block.timestamp;
    require eV1.msg.value == 0 && eV2.msg.value == 0;
    require att != v1 && att != v2 && v1 != v2;
    require v1 != currentContract && v1 != tToken && v2 != currentContract && v2 != tToken;
    require to_mathint(a0) < BOUND() && to_mathint(x1) < BOUND() && to_mathint(x2) < BOUND();
    require totalSupply() == 0 && totalVaultShares() == 0;          // brand-new wrapper

    mathint attStart = underlying.balanceOf(att) + tToken.balanceOf(att);
    uint256 attTT0 = tToken.balanceOf(att);

    deposit(eA, a0, att);                                           // 1. attacker gets shares
    uint256 err = tToken.mint(eA, d);                               // 2. attacker mints tTokens...
    require err == 0;
    uint256 minted = assert_uint256(tToken.balanceOf(att) - attTT0);
    bool ok = tToken.transfer(eA, currentContract, minted);         //    ...and donates them
    require ok;
    uint256 s1 = deposit(eV1, x1, v1);                              // 3. victim 1
    uint256 s2 = deposit(eV2, x2, v2);                              // 4. victim 2
    redeem(eA, balanceOf(att), att, att);                           // 5. attacker exits

    mathint attEnd = underlying.balanceOf(att) + tToken.balanceOf(att);
    satisfy s1 == 0 && s2 == 0 && attEnd > attStart && to_mathint(tToken.balanceOf(att)) == to_mathint(attTT0);
}

