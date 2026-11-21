# Follow-up report F02: Certora prover runs on SpectraWrappedTakara

| Field | Value |
|-------|-------|
| Cell ID | F2 |
| Input version | F2-pilot-amendment-2026-10-27-v2 |
| Template commit | d492bed455059b8f650cfab30601a8e2207d8ae0 |
| Follows | REPORT_F02.md (original audit, compile-only) |
| Date | 2026-10-28 |
| Model | claude-opus-5-5 (from the session system prompt; not checked with any tool) |
| Certora CLI | certora-cli 8.20.3, solc 0.8.23 |
| Duration | unknown (not measured for the follow-up runs) |

## 1. Why this follow-up exists

The original audit did not submit any prover job, as the first prompt instructed. Its rule outcomes were predictions from manual review
and an integer replay (`poc/donation_inflation.py`). On 2026-10-28 the user explicitly asked for prover runs. This report
records those runs, what each counterexample turned out to mean, the fixes made to the verification model, and the final
conclusions.

## 2. Prover jobs

| # | Scope | Result |
|---|-------|--------|
| 1 | `totalSupplyIsSumOfBalances`, `donationDoesNotMovePrice`, `fairDeposit`, `depositMatchesPreview` | Submitted without `--wait_for_results`, so the results were not collected. [link]([Certora job link removed]) |
| 2 | Same 4 rules, `--wait_for_results all` | All 4 FAIL. **Invalid run** (model problem, see 3.1). [link]([Certora job link removed]) |
| 3 | Full spec (33 rules), call-resolution fix | Read from the live job page because the CLI stopped waiting early. 1 TIMEOUT, 3 parametric sub-rules still running when abandoned. Several counterexamples were model artefacts (see 3.2–3.4). [link]([Certora job link removed]) |
| 4 | 10 key rules on the hardened model | Completed. These are the final verdicts. [link]([Certora job link removed]) |

## 3. Problems found in the verification model, and how each was fixed

### 3.1 Unresolved external calls (invalidated run 2)
The wrapper reads `asset()` and `vaultShare()` from ERC-7201 namespaced storage, so the prover could not statically resolve its
calls to the tToken and USDC. It treated them as `UNRESOLVED AUTO` summaries, which return arbitrary values and havoc storage. Evidence: in
one counterexample, `previewDeposit` and `deposit` read **different** exchange rates in the same transaction, and
`tToken.totalSupply()` returned 0 while the model's supply was 10.
**Fix:** `DISPATCHER(true)` summaries for every tToken and ERC-20 function the wrapper calls. The CLI's `link` option rejects
ERC-7201 storage paths, so links could not be used.

### 3.2 Dispatcher recursion on `decimals()` (run 3)
Dispatching `decimals()` could route back into the wrapper's own `decimals()`. The prover flagged this as recursion, which produced
"violations" of `pauseOnlyByPauseUnpause` and `rewardsProxyOnlyBySetter` on view functions that cannot change state.
**Fix:** `function _.decimals() external => ALWAYS(6);`, because USDC and tUSDC both have 6 decimals.

### 3.3 Inconsistent token states (run 3)
The prover started from token states where individual balances were near 2^256 but `totalSupply` was 0 or a small number.
OpenZeppelin's unchecked balance addition then wraps around. This alone caused the failures of
`priceNeverDecreases` (on `wrap`), `redeemMatchesPreview`, `wrapperUsdcBalanceUnchanged` and `totalAssetsNeverReverts`.
**Fix:** ghost sums of balances for both token models, hooked on their `_balances` storage, plus
`totalSupply == sum of balances` required in `setupLinks()`.

### 3.4 Unrealistic exchange rates (run 3)
Rates as low as 1 or as high as 2^100 produced rounding losses that the real tUSDC market (rate ≈ 1.0435e18) cannot produce.
**Fix:** `1e16 ≤ exchangeRateStored ≤ 1e20` in `setupLinks()`.

### 3.5 Rule bug, not yet fixed
`depositUpToMaxDepositSucceeds` lacks `require !paused()`. Its run-4 counterexample is a paused vault where `maxDeposit = 0` and
`deposit(0)` reverts, which is the intended behaviour.

All fixes are in `certora/specs/SpectraWrappedTakara.spec`. The spec still compiles with `--compilation_steps_only`.

## 4. Final verdict per property

Requirements marked S come from the supplied README; properties marked I were inferred by the auditor (see PROPERTIES_F02.md).

| Property | Rule(s) | Final verdict |
|----------|---------|---------------|
| S1 supply consistency | `totalSupplyIsSumOfBalances` | **Holds** (verified) |
| S2 price never decreases | `priceNeverDecreases`, `priceNeverDecreasesOnAccrual` | Accrual rule verified. The only counterexample was an artefact (3.3). The full parametric proof **did not finish**. |
| S3 paused ⇒ closed | `paused*Reverts` | **Holds** (verified) |
| S4 donations do not move the price | `donationDoesNotMovePrice` | **VIOLATED: real, B1** |
| S5 fair deposit | `fairDeposit` | **VIOLATED: real** (B1 path, plus the dust-deposit path, see 5.2) |
| S6 views never revert | `asset/totalAssets/convertTo*NeverReverts` | `asset` and `totalAssets` verified. **convertToShares/convertToAssets VIOLATED: real, B2** |
| S7 caller-independent conversions | `conversionsIndependentOfCaller` | **Holds** |
| S8–S10 ERC-4626 limits | `depositRespectsMaxDeposit`, `redeemRespectsMaxRedeem`, `maxLimitsZeroWhenPaused`, `mintWithdrawUnsupported` | **Hold** |
| S12 / I2 allowance spending | `redeemSpendsAllowance`, `unwrapSpendsAllowance` | **Hold** |
| S13 rounding down | `conversionRoundTripRoundsDown` | **Inconclusive** (timeout) |
| S14/S15 deposit vs preview | `depositMatchesPreview` | **Holds** (verified in run 4; the run-2 failure was 3.1) |
| S16/S17 redeem vs preview | `redeemMatchesPreview` | **Holds** (verified in run 4; the run-3 failure was 3.3) |
| S18 previews = conversions | `previewsEqualConversions` | **Holds** |
| S19 privileged access | `pauseOnlyByPauseUnpause`, `rewardsProxyOnlyBySetter` | **Holds** (state-changing functions verified; view "violations" were 3.2) |
| I1 no zero-share deposit/wrap | `depositNeverMintsZero`, `wrapNeverMintsZero` | **VIOLATED: real** (B1 + 5.2) |
| I3 backing | `unwrapOwnBalanceNeverRunsShort` | Inconclusive (still running in run 3) |
| I4 no USDC left in wrapper | `wrapperUsdcBalanceUnchanged` | Holds once artefact 3.3 is removed |
| I5 max* not overstated | `depositUpToMaxDepositSucceeds` + manual review | Rule artefact (3.5). **B3 stands on manual review** |
| I8 backing not moved by donations | `donationDoesNotChangeBacking` | **VIOLATED: real, B1** |

## 5. Vulnerabilities: final conclusions

### 5.1 B1: donations move the share price; deposits can mint 0 shares (Medium, confirmed by the prover)
`totalVaultShares()` is the wrapper's live `tToken.balanceOf(this)`, and share pricing is based on it. Anyone can change the price with a direct
tToken transfer.
- Prover (run 4): with 999,999 shares outstanding, a 2-tToken donation raised the value of one whole share from 0 to 1 wei of USDC.
- Prover (runs 3 and 4): `wrap(382)` and `wrap(3972)` minted **0 shares** into wrappers holding donated tTokens. A 5-tToken deposit
  minted 0 shares.
- Integer replay at the live rate: attacker deposits 2 wei, then donates about 1,043 USDC of tTokens. The victim's 500 USDC deposit mints
  **0 shares** and the victim loses everything. The attacker loses about 272 USDC, so this is griefing and front-running rather than theft.
- Impact: depositors on a new or thin wrapper can lose their whole deposit, including the Spectra PT contract depositing for
  users. Anyone can also move the IBT rate Spectra reads, which shifts yield between PT and YT holders.
- Fix: track wrapped tTokens in storage (update it in `wrap`, `unwrap`, `_deposit` and `_withdraw` by the amounts actually moved), use a nonzero
  `_decimalsOffset()`, and revert when `shares == 0` for nonzero input.

### 5.2 Deposits that mint 0 tTokens are accepted (Low, newly found by the prover)
Neither `deposit` nor `wrap` rejects a call that mints 0 tTokens or 0 shares. A deposit worth less than one tToken mints 0 tTokens, and the wrapper
keeps the USDC and mints 0 shares. At today's rate (about 1.04 USDC-wei per tToken-wei) the loss is at most about 1 wei, below ε, so S5 only
breaks this way once a tToken is worth more than 10 USDC-wei. The `shares > 0` check from 5.1 also fixes this.

### 5.3 B2: `convertToShares` / `convertToAssets` can revert (Low, confirmed by the prover)
`1e18 * assets * 1e18` overflows for assets ≥ about 1.16e41 (the prover's counterexample is exactly `2^256 / 1e36`), and
`rate * tTokens` overflows for huge share amounts. The README says these functions never revert, while EIP-4626 allows overflow on
unreasonably large inputs. In production, any revert in the Takara views or the interest-rate model also propagates, but the model does not cover that.
Fix: use `Math.mulDiv`, or saturate instead of reverting.

### 5.4 B3: `maxDeposit` / `maxRedeem` ignore Takara's limits (Low, manual review only)
Unchanged from the original report. The model leaves out Takara's comptroller, which can block deposits and redeems through mint and redeem pause flags, supply
caps and available cash. `maxDeposit` and `maxRedeem` don't account for any of these, so they can overstate what will be accepted.

### 5.5 B4: unreachable payout cap in `_withdraw` (Informational)
Unchanged. The run-3 artefact (3.3) did trigger the cap: `redeem` returned 5866 but paid 2788, which shows the return-value mismatch the original report
predicted. It needed a USDC state that cannot exist, so it stays informational.

### 5.6 Nothing else
No other supplied requirement has a real counterexample. Still open: the full parametric proof of S2, S13 (timeout) and I3.

## 6. Suggested next steps
1. Fix `depositUpToMaxDepositSucceeds` (add `require !paused()`).
2. Rerun `priceNeverDecreases`, `conversionRoundTripRoundsDown` and `unwrapOwnBalanceNeverRunsShort` on the hardened model, with a
   longer timeout or with `mulDiv` summarized, to close S2, S13 and I3.
3. After the B1 fix, rerun `donationDoesNotMovePrice`, `fairDeposit`, `depositNeverMintsZero` and `wrapNeverMintsZero` to
   confirm they pass.

## 7. Changed files
- `certora/specs/SpectraWrappedTakara.spec`: dispatcher summaries, `decimals()` summarized as a constant 6, token-consistency ghosts,
  realistic exchange-rate bounds. It compiles cleanly.
- `REPORT.md`: new "Prover results" section, updated metadata and modelling notes.
- `certora/conf/SpectraWrappedTakara.conf`: unchanged in the end (the ERC-7201 link attempt was rejected by the CLI and reverted).
- Nothing was committed or pushed.
