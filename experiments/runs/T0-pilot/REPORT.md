# Report — SpectraWrappedTakara

**Scope:** `src/takara/SpectraWrappedTakara.sol` and its base `src/utils/Spectra4626Wrapper.sol`. Tests run against the local Takara tUSDC market built by `test/utils/LocalDeployment.sol`.

**Tests:** `test/SpectraWrappedTakara.t.sol`. Run them with `forge test`. Fuzz tests ran 2,000 runs each. Invariant tests ran 256 runs × 500 calls with 0 reverts.

**Interest simulation:** the local market has no price oracle, so nobody can actually borrow. The tests simulate borrowing instead: they move a share of the market's cash into `totalBorrows` (this leaves the exchange rate unchanged), set a reserve factor below 100%, and let time pass without accruing. This leaves the tToken's stored rate out of date, which exercises the wrapper's accrual-replay code (`_currentExchangeRate`).

**Totals:** 19 tests. 16 pass and 3 fail, and the 3 failures come from 2 bugs.

## Results by property

| Property | Test | Result |
|---|---|---|
| P1 Exact deposit preview | `testFuzz_P1_previewDepositExact` | PASS |
| P2 Exact redeem preview | `testFuzz_P2_previewRedeemExact` ¹ | PASS |
| P3 No profit from a deposit round trip | `testFuzz_P3_depositRoundTripNoProfit` | PASS |
| P4 No profit from a wrap round trip | `testFuzz_P4_wrapRoundTripNoProfit` | PASS |
| P5 Solvency | `invariant_P5_solvency` | PASS |
| P6 Honest totalAssets | `invariant_P6_totalAssetsBacked` | PASS |
| P7 Isolation between holders | `testFuzz_P7_isolation` | PASS |
| P8 No stuck or stolen underlying | `testFuzz_P8_noStuckOrStolenUnderlying` ¹, `invariant_P8_noUnderlyingInWrapper` | PASS |
| P9 Donation attack not profitable | `testFuzz_P9_donationAttackNotProfitable` | PASS |
| P10 Unsupported entry points | `test_P10_unsupportedEntryPoints` | PASS |
| P11 Honest maxDeposit | `test_P11_maxDepositHonestWhenTakaraMintPaused` | **FAIL** (Bug 1) |
| P11 Honest maxDeposit | `test_P11_maxDepositHonestWhenSupplyCapReached` | **FAIL** (Bug 1) |
| P12 Honest maxRedeem | `test_P12_maxRedeemHonestUnderHighUtilization` | **FAIL** (Bug 2) |
| P13 Pause | `test_P13_pause` | PASS |
| P14 Access control | `test_P14_accessControl` | PASS |
| P15 Allowances | `testFuzz_P15_allowances` | PASS |
| P16 One-time initialization | `test_P16_initializeOnce` | PASS |
| P17 Metadata | `test_P17_metadata` | PASS |

¹ P2 and P8 skip any redeem that is larger than the market's available cash (`vm.assume`). Without that filter, these tests fail with `RedeemFailed(15)` (`TOKEN_INSUFFICIENT_CASH`). That failure is the liquidity problem P12 tests (Bug 2), not a preview mismatch.

## Bugs

### Bug 1 — `maxDeposit` ignores Takara's mint restrictions (ERC-4626 non-compliance)

`Spectra4626Wrapper.maxDeposit` returns `type(uint256).max` whenever the wrapper itself is not paused. A deposit, however, also calls `tToken.mint`, and that call fails in several cases that `maxDeposit` does not check:

- The comptroller has paused minting on the market (`mintGuardianPaused`). The deposit reverts with `"mint is paused"`.
- The market's supply cap has been reached. The deposit reverts with `"market supply cap reached"`.
- The same gap also covers the other `mintAllowed` rejections: blacklisting, `userMintPaused`, and the market not being listed.

**Reproduction:** both P11 tests set `maxDeposit(alice)` to 2²⁵⁶−1, and then `deposit(1e9, alice)` reverts.

**Impact:** ERC-4626 requires that `maxDeposit` return an amount that would not cause a revert, and that it return 0 when deposits are disabled. Integrators rely on this. That includes the Spectra Principal Token and routers that size or route deposits by calling `maxDeposit`. When Takara pauses minting or hits its cap, these integrators will try deposits that revert, which causes unexpected transaction failures and can break the routing logic. No funds are lost. **Severity: Low/Medium** (standard non-compliance that affects integrations).

**Fix:** in `SpectraWrappedTakara`, override `maxDeposit`. Return 0 when the comptroller reports minting as paused for the market. When a supply cap is set, return the remaining capacity, which is `cap − (cash + borrows − reserves)`, or 0 if the cap is already reached.

### Bug 2 — `maxRedeem` ignores Takara liquidity (ERC-4626 non-compliance)

`maxRedeem(owner)` returns the owner's full share balance, but `redeem` calls `tToken.redeem`. That call fails with `TOKEN_INSUFFICIENT_CASH` (error 15, which the wrapper surfaces as `RedeemFailed(15)`) whenever the market's available cash is less than the amount being redeemed. Comptroller restrictions that block redeems (`redeemGuardianPaused`, blacklisting) are likewise not reflected in `maxRedeem`.

**Reproduction:** `test_P12_maxRedeemHonestUnderHighUtilization`.

1. Alice deposits 1,000 USDC.
2. 90% of the market's cash is borrowed.
3. `maxRedeem(alice)` returns all of her shares.
4. `redeem(maxRedeem(alice), …)` reverts with `RedeemFailed(15)`.

**Impact:** ERC-4626 requires that `maxRedeem` not overstate what can be redeemed. In a lending market with high utilization, which is common, the Spectra PT and other integrators receive an overstated limit and their redeems revert. Users can still exit by unwrapping to tTokens or by waiting for liquidity, so funds are not lost. **Severity: Low/Medium** (standard non-compliance; withdrawals can be temporarily blocked through the ERC-4626 path).

**Fix:** cap `maxRedeem` at the shares that the market's `getCash()` can cover, using the up-to-date exchange rate. Return 0 when the comptroller has paused redeems on the market.

## Observations (not bugs)

- **Accrual replay is exact.** Across 2,000 fuzz runs (delays up to one year, reserve factor from 0 to 100%, up to 95% utilization), the wrapper's replay of `accrueInterest` and Takara's rounding gave previews identical to the actual results (P1, P2).
- **The `_withdraw` cap never triggers.** Because the previews are exact, the line `if (assets > balance) assets = balance;` is never reached in these tests. If the replay ever drifted, though, this line would let a redeemer be paid from underlying sitting in the wrapper for unrelated reasons. A more defensive version would measure the balance before and after the call and pay exactly what `tToken.redeem` delivered.
- **Donation attack:** with `_decimalsOffset() == 0`, a tToken donation can still round a small victim deposit down to 0 shares. This is griefing only: P9 shows the attacker never comes out ahead. A non-zero decimals offset would make even the griefing expensive.
- **Accepted trust assumption:** `claimRewards` `delegatecall`s an admin-set proxy, so the AccessManager admin can run arbitrary code in the wrapper's context. This is outside the scope of the properties above.
