# Report: SpectraWrappedTakara property testing

## Run metadata

| Field | Value |
|---|---|
| Cell ID | T2 |
| Input version | T2-pilot-amendment-2026-10-27-v2 |
| Template commit | d492bed455059b8f650cfab30601a8e2207d8ae0 |
| Model / version | claude-opus-5-5 (configured model ID from the session's system prompt; the serving model was not independently checked) |
| Duration | about 9 minutes wall clock (13:48:35 to 13:57:04 UTC, 2026-10-27, from the shell clock); tests were not executed |
| Foundry version | unknown (Foundry is not installed in this environment) |

## ⚠️ Execution status: the tests were written but NOT run

The container has no `forge`, `anvil` or `solc` binaries, and the `dependencies/` directory
(OpenZeppelin, forge-std) that `forge soldeer install` would download is missing. I tried to
install Foundry twice: once with the official `foundryup` script and once by downloading the
official release tarball. The sandbox's permission policy blocked both because they download
and run external code. I did not try to get around that block.

As a result, **no result in this report comes from running the tests.** The "Expected result"
column shows what I expect when the suite runs, based on reading the code and on an exact
integer simulation of the wrapper and Takara math (Python, run in this session; the numbers are
quoted below). The tests have also not been compiled, so they may need small fixes first. To
run them:

```sh
forge soldeer install
forge build
forge test -vv
```

## Files

- `PROPERTIES.md`: the property list. Supplied properties are R* and E*, inferred ones are I*.
- `test/WrapperBase.sol`: shared fixture built on `LocalDeployment`, plus helpers.
- `test/WrapperProperties.t.sol`: unit and fuzz tests. A test named `*_Bug_*` reproduces a
  finding and is expected to FAIL.
- `test/WrapperInvariants.t.sol`: a stateful invariant suite driven by a handler
  (deposit / redeem / wrap / unwrap / transfer / donate / warp / pause). It runs in two
  configurations: with tToken donations, and without them.

## Properties, tests and results

### Supplied requirements (from the README)

| ID | Property | Test(s) | Expected result |
|---|---|---|---|
| R1 | Total supply = sum of balances | `testFuzz_R1_supplyEqualsSumOfBalances`, `invariant_R1_supplyEqualsSumOfBalances` (both suites) | PASS |
| R2 | No operation lowers the value of one whole share | `testFuzz_R2_priceNonDecreasingAcrossOps`, `invariant_R2_priceNeverDecreases` (both suites) | PASS |
| R2 (edge) | Same property, when the Takara market is emptied | `test_R2_Bug_priceDropsWhenTakaraMarketEmpties` | **FAIL**: 1 043 481 → 1 000 000 (finding F5) |
| R3 | While paused, deposit / redeem / wrap / unwrap revert | `testFuzz_R3_pausedClosesAllEntryPoints`, `invariant_R3_pausedMeansClosed` | PASS |
| R4 | tToken donations do not change the share price | `test_R4_Bug_tTokenDonationDoublesPrice`, `testFuzz_R4_Bug_tTokenDonationDoesNotMovePrice` | **FAIL**: price 1 043 481 → 2 086 962 (finding F1) |
| R5 | Shares from a deposit of `a` are worth ≥ a − ε | `testFuzz_R5_fairDeposit_honestState`, `invariant_R5_fairDeposit` (no-donation suite) | PASS |
| R5 | Same, after a tToken donation | `test_R5_Bug_fairDepositAfterSmallDonation`, `testFuzz_R5_Bug_fairDepositAfterDonation`, `invariant_R5_fairDeposit` (donation suite) | **FAIL**: 358 wei lost on 1000 USDC (findings F1, F2) |
| E1 | asset / totalAssets / convertTo* never revert | `testFuzz_E1_viewsDoNotRevert` (inputs ≤ 1e40, paused or not, after time passes) | PASS |
| E1 | Same, for extreme inputs | `test_E1_Bug_convertToSharesRevertsOnLargeInput` | **FAIL**: overflow panic at 2e41 (finding F6) |
| E2 | Conversions do not depend on the caller | `testFuzz_E2_conversionsIndependentOfCaller` | PASS |
| E3 | deposit of ≤ maxDeposit succeeds | `testFuzz_E3_depositUpToMaxDepositSucceeds` (≤ 1e18) | PASS |
| E3 / I9 | Same, near the maxDeposit bound | `test_I9_Bug_maxDepositNotRespected` | **FAIL** (finding F4) |
| E4 | redeem of ≤ maxRedeem succeeds | `testFuzz_E4_redeemUpToMaxRedeemSucceeds` | PASS (local market has no borrows) |
| E4 / I8 | Same, when Takara's cash is lent out | `test_I8_Bug_maxRedeemIgnoresTakaraLiquidity` | **FAIL** (finding F3) |
| E5 | maxDeposit and maxRedeem are 0 while paused | `testFuzz_E5_pausedLimitsAreZero` | PASS |
| E6 | maxMint and maxWithdraw are always 0 | `testFuzz_E6_maxMintAndMaxWithdrawAreZero` | PASS |
| E7 | Deposit and Withdraw events are emitted | `testFuzz_E7_depositAndRedeemEmitEvents` | PASS |
| E8 | A third-party redeem spends the owner's allowance | `testFuzz_E8_redeemByOtherSpendsAllowance` | PASS |
| E9 | convertToShares and convertToAssets round down | `testFuzz_E9_conversionsRoundDown` | PASS |
| E10, E11 | previewDeposit ≤ minted; deposit returns minted | `testFuzz_E10_E11_depositPreviewAndReturn` | PASS |
| E12, E13 | previewRedeem ≤ paid; redeem returns paid | `testFuzz_E12_E13_redeemPreviewAndReturn` | PASS |
| E14 | previewDeposit = convertToShares; previewRedeem = convertToAssets | `testFuzz_E14_previewEqualsConvert` | PASS |

### Inferred properties (not in the README)

| ID | Property | When added | Test(s) | Expected result |
|---|---|---|---|---|
| I1 | Solvency: totalAssets ≤ redeemable value of the held tTokens | before testing | `testFuzz_I1_solvency`, `invariant_I1_solvency` | PASS |
| I2 | No profit from a deposit→redeem round trip | before testing | `testFuzz_I2_noDepositRedeemRoundTripProfit` | PASS |
| I3 | No profit from a wrap→unwrap round trip | before testing | `testFuzz_I3_noWrapUnwrapRoundTripProfit` | PASS |
| I4 | No stranded USDC in the wrapper | before testing | `testFuzz_I4_noStrandedUsdc`, `invariant_I4_noStrandedUsdc` | PASS |
| I5 | Only the authority can pause, unpause, set the rewards proxy or claim rewards | before testing | `testFuzz_I5_onlyAuthorityIsPrivileged` | PASS |
| I6 | Neither the proxy nor the implementation can be re-initialized | before testing | `test_I6_cannotReinitialize` | PASS |
| I7 | Previews stay exact after interest accrual with borrows | during investigation | `testFuzz_I7_previewsExactAfterAccrual` (borrows simulated) | PASS |
| I8 | maxRedeem reflects Takara's liquidity | during investigation | `test_I8_Bug_maxRedeemIgnoresTakaraLiquidity` (borrows simulated) | **FAIL** (F3) |
| I9 | maxDeposit stays below the overflow bound | during investigation | `test_I9_Bug_maxDepositNotRespected` | **FAIL** (F4) |
| I10 | A first-depositor donation cannot zero out a later deposit | during investigation | `test_I10_Bug_inflationAttackZeroesVictimShares` | **FAIL** (F2) |

## Bugs found

The numbers come from an exact integer replay of the local deployment's state: Takara supply
1 683 808 535 tTokens, stored exchange rate 1 043 481 707 378 327 310, 6 decimals, and
`_decimalsOffset() = 0`.

### F1 (High, breaks supplied R4 and R5): share price is computed from the wrapper's raw tToken balance, so donations move it

`Spectra4626Wrapper.totalVaultShares()` returns `IERC20(vaultShare).balanceOf(address(this))`.
`_previewWrap` and `_previewUnwrap` price shares as `(totalVaultShares() + 1) / (totalSupply() + 1)`,
and `SpectraWrappedTakara._convertToAssets` and `_convertToShares` build on them. A plain
`tToken.transfer(wrapper, x)` therefore raises `convertToAssets(1e6)` and `previewRedeem`
without minting any shares. The wrapper has no internal accounting of the tTokens it received
through `deposit` or `wrap`.

- Repro: `test_R4_Bug_tTokenDonationDoublesPrice`. Alice deposits 1000 USDC (price 1 043 481);
  Bob donates 958 330 168 tTokens (about 1000 USDC); the price becomes 2 086 962.
- Impact: this breaks R4 outright. It also lets anyone inflate the rate cheaply while supply is
  small, which is what makes F2 possible and breaks R5. For a Spectra PT that uses this wrapper
  as its IBT, the reported rate can be pushed up at will, and PT/YT accounting reads that rate.
- Fix direction: track deposited and wrapped tTokens in a storage variable and use it in
  place of `balanceOf`, and/or use a non-zero `_decimalsOffset()`.

### F2 (High, breaks supplied R5; inferred I10): first-depositor inflation and donation griefing take depositors' USDC

Because of F1, and because the virtual offset is only `10**0 = 1`, the per-share tToken amount
can be raised arbitrarily, and the floor in `_previewWrap` then takes value from later
depositors.

- Small donation (`test_R5_Bug_fairDepositAfterSmallDonation`): the attacker wraps 1 tToken and
  donates 1e6 tTokens (about 1.04 USDC). A 1000 USDC deposit then receives 1916 shares worth
  999 999 642, a loss of **358 wei**, which is far above ε = 10.
- Full grief (`test_I10_Bug_inflationAttackZeroesVictimShares`): the attacker wraps 1 tToken
  and then donates 2 × 958 330 168 tTokens. The victim's 1000 USDC deposit mints **0 shares**
  and all 1000 USDC is lost. Because of the single virtual share, the attacker recovers only
  about 1.5 of the 2 donated units, so the attack costs the attacker about 500 USDC and the
  victim 1000 USDC. That makes it griefing rather than theft, but the loss to the user is
  total. `deposit` has no slippage or minimum-shares guard, and `previewDeposit` correctly
  shows 0, so only callers who check the preview first are protected.
- Fix: the same as F1. A non-zero decimals offset (for example 6) plus internal tToken
  accounting removes the attack.

### F3 (Medium, EIP-4626 / inferred I8): `maxRedeem` ignores Takara liquidity

`maxRedeem(owner)` returns `balanceOf(owner)`. When Takara's cash is lent out, `tToken.redeem`
returns `TOKEN_INSUFFICIENT_CASH`, and `_withdraw` reverts with `RedeemFailed`. EIP-4626
requires `maxRedeem` to account for global limits; the README requires that "`maxRedeem`
returns limits that `redeem` respects".

- Repro: `test_I8_Bug_maxRedeemIgnoresTakaraLiquidity`. A borrow is simulated with `stdstore`
  (totalBorrows = cash − 1 USDC, with cash reduced to match, so the exchange rate is
  unchanged). This was needed because the local deployment has no oracle, so real borrows
  cannot be opened through calls. The state is normal on the live Sei market, but it is not
  reachable from the fresh local deployment through calls alone, which is why this is
  classed as an inferred property and not a violation of a supplied one.
- Impact: integrators such as the Spectra PT, routers and aggregators that size redemptions by
  `maxRedeem` see reverts in periods of high utilization.
- Fix direction: cap the result at the shares whose redeem value is ≤ `tToken.getCash()`.

### F4 (Low, EIP-4626 / inferred I9): `maxDeposit` overstates the deposit limit

`maxDeposit` returns `type(uint256).max` when the vault is not paused. `_divScalarByExpTruncate`
computes `assets * 1e36`, which overflows for `assets > ~1.157e41`, and Takara's own mint
overflows at the same point. Any deposit in that range therefore panics even though it is
≤ `maxDeposit`.

- Repro: `test_I9_Bug_maxDepositNotRespected` (a = 2e41).
- Impact: the amount is unrealistic for USDC. This matters only for formal EIP-4626
  conformance and for fuzzing integrators.

### F5 (Low / informational, breaks supplied R2 in a corner case): the share value drops when the Takara market is emptied

`_currentExchangeRate()` returns `exchangeRateStored()` when the tToken supply is 0. In that
case Compound returns `initialExchangeRateMantissa` (1e18), not the last rate (about 1.0435e18).
After the wrapper's last holder and Takara's other holders all redeem,
`convertToAssets(1e6)` falls from 1 043 481 to 1 000 000.

- Repro: `test_R2_Bug_priceDropsWhenTakaraMarketEmpties`.
- Impact: nobody holds shares at that moment (wrapper supply must already be 0), so no funds
  are lost. It is still a reachable violation of R2 as worded ("every state reachable by any
  sequence of calls"), and a PT that snapshots the IBT rate could see a decrease. The cause is
  Takara behaviour that the wrapper passes straight through.

### F6 (Informational, literal README E1): conversions revert on huge inputs

`convertToShares(x)` reverts for `x > ~1.157e41` (because of `x * 1e36`), and `convertToAssets`
reverts once the tToken amount exceeds about 1.1e59 (because of `rate * tTokens`). The README
says these functions "never revert". EIP-4626 allows a revert from integer overflow on
unreasonably large inputs, so this breaks the README's wording but not the EIP.

- Repro: `test_E1_Bug_convertToSharesRevertsOnLargeInput`.

### Areas checked with no bug found (by analysis; the tests are still to be run)

- **Rate replication:** `_currentExchangeRate` and the `divScalarByExpTruncate` /
  `mulScalarTruncate` mirrors match Takara's `accrueInterest`, `mintFresh` and `redeemFresh`
  operation for operation. Previews are therefore exact (E10–E14, I7).
- **Price monotonicity under normal ops:** deposit, redeem, wrap and unwrap all floor in the
  vault's favour at both the Takara layer and the wrapper layer (R2).
- **Pause:** every entry point that moves value is blocked by `whenNotPaused` on the previews
  and on `_update` (R3).
- **Withdraw cap:** the `assets > balance` clamp in `_withdraw` cannot trigger, because Takara
  pays exactly the previewed amount. If it ever did trigger, `redeem` would return the
  pre-clamp value and break E13. That makes it dead, risky code worth removing.

## Run inputs

### Initial prompt (verbatim)

````text
@"/root/.claude/uploads/422aa609-819b-583d-a33c-8d4070e123d9/2326d134-L2-README.md" Find bugs in this project. Use the supplied README as the project documentation.

First, before writing any test, write PROPERTIES.md in the project root: the properties this project must satisfy, each in one plain-language sentence.

Check all requirements in the supplied README. You may also infer additional properties, investigate other failure modes, and write tests for them. In PROPERTIES.md and REPORT.md, distinguish supplied requirements from properties you inferred, including any added during the investigation.

Then write Foundry tests that check those properties, run them, and write REPORT.md in the project root: for each property, the test that checks it and its result; then each bug found and its impact.

Work only in the disposable source copy. Do not access or modify shared repositories, use repository or cross-session connectors, browse the web, commit, push, or create a pull request.

In REPORT.md, include a "Run inputs" section quoting this entire initial prompt and the supplied README verbatim. Keep supplied inputs separate from the properties you inferred. Record cell ID T2 and input version T2-pilot-amendment-2026-10-27-v2. The supplied template commit is d492bed455059b8f650cfab30601a8e2207d8ae0. Record the model/version and duration if available; mark unavailable values unknown. Do not use external tools to discover this metadata.
````

### Supplied README (verbatim)

````markdown
# Spectra Wrapped Takara

An ERC-4626 vault that wraps a Takara tToken so it can back a Spectra Principal Token.

## What it does

- **Takara** is a Compound v2 fork on Sei. Supplying USDC to its market mints interest-bearing
  tTokens (tUSDC).
- **`SpectraWrappedTakara`** turns tUSDC into a standard ERC-4626 vault:
  - `deposit(assets, receiver)`: pulls USDC, supplies it to Takara, mints wrapper shares.
  - `redeem(shares, receiver, owner)`: burns shares, redeems tTokens, pays USDC.
  - `wrap` / `unwrap`: move tTokens in and out directly, for users who already hold them.
  - `mint` and `withdraw` are not supported.
- **Users:** Spectra's Principal Token contract and individual depositors.

## Trust assumptions

- An AccessManager authority (the Spectra DAO) can pause and unpause the vault and set a rewards
  proxy. Nobody else has privileged access.
- Takara and USDC are trusted to behave as standard tokens.

## Required properties

These must hold in every state reachable by any sequence of calls, starting from a freshly
deployed, empty wrapper. ε = 10 wei of USDC.

1. **Supply consistency:** the total supply of wrapper shares always equals the sum of all
   balances.
2. **Price never decreases:** no operation lowers the USDC value of one whole share.
3. **Paused means closed:** while paused, deposit, redeem, wrap and unwrap revert.
4. **Donations do not move the price:** transferring tTokens directly to the wrapper never changes
   the USDC value of one whole share.
5. **Fair deposit:** right after depositing `a` USDC, the shares received are worth at least
   `a − ε` USDC (as reported by `previewRedeem`).

## ERC-4626 compliance

The wrapper follows EIP-4626 for the functions it supports:

- `asset`, `totalAssets`, `convertToShares` and `convertToAssets` never revert, and the
  conversions do not depend on the caller.
- `maxDeposit` and `maxRedeem` return limits that `deposit` and `redeem` respect, and 0 while
  paused; `maxMint` and `maxWithdraw` return 0 because `mint` and `withdraw` are not supported.
- `deposit` and `redeem` emit `Deposit` and `Withdraw`; `redeem` by someone other than the owner
  spends the owner's share allowance.

### Rounding and previews (EIP-4626)

- `convertToShares(assets)` and `convertToAssets(shares)` round down. They ignore limits and are
  the vault's reference conversions.
- `previewDeposit(assets)` rounds down and returns no more shares than `deposit(assets, …)` mints
  in the same transaction; `deposit` returns the shares actually minted.
- `previewRedeem(shares)` rounds down and returns no more assets than `redeem(shares, …)` pays in
  the same transaction; `redeem` returns the assets actually paid.
- With no fees, `previewDeposit` equals `convertToShares` and `previewRedeem` equals
  `convertToAssets`, up to rounding.

## Development

```sh
forge soldeer install
forge build
forge test
```

`test/utils/LocalDeployment.sol` deploys the full system locally: a standard ERC-20 for USDC (Sei's
USDC is a bank-precompile token), the real Takara market seeded to its live Sei state, and the
wrapper behind a proxy.
````
