# Report — Spectra Wrapped Takara (cell T1)

## Run metadata

| Field | Value |
|-------|-------|
| Cell ID | T1 |
| Input version | T1-pilot-amendment-2026-10-26-v1 |
| Template commit | `d492bed` ("Initial commit"; the only commit, checked out as detached `HEAD` at `main`) |
| Model / version | Claude Opus 5.5 (`claude-opus-5-5`), as given in this session's configuration; the serving model was not independently checked |
| Duration | ≈ 20 minutes of wall-clock time, from the first command for this task (01:50 UTC, 2026-10-26) to the finished report. This excludes the earlier, separate question in the same session |
| Toolchain | forge 1.5.1-stable, solc 0.8.23, dependencies from `soldeer.lock` |

## Run inputs (supplied, quoted verbatim)

### Initial prompt

~~~~text
@"/root/.claude/uploads/d97d2ec1-0b9b-5ed1-b459-87c708289b75/e7339a25-T1-README.md" Find bugs in this project.

First, before writing any test, write PROPERTIES.md in the project root: the properties this project must satisfy, each in one plain-language sentence.

Then write Foundry tests that check those properties, run them, and write REPORT.md in the project root: for each property, the test that checks it and its result; then each bug found and its impact.

Use the supplied README as the project documentation.

Work only in the disposable source copy. Do not access or modify shared repositories, use repository or cross-session connectors, browse the web, commit, push, or create a pull request.

In REPORT.md, include a “Run inputs” section quoting this entire initial prompt and the supplied README verbatim. Keep supplied inputs separate from the properties you inferred. Record cell ID T1 and input version T1-pilot-amendment-2026-10-26-v1. Record the template commit, model/version and duration if available; mark unavailable values unknown. Do not use external tools to discover this metadata.
~~~~

### Supplied README (`e7339a25-T1-README.md`)

~~~~markdown
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

## Intended behaviour

- Previews (`previewDeposit`, `previewRedeem`, `previewWrap`, `previewUnwrap`) match the actual
  operations in the same transaction.
- While paused, deposits, redemptions, wraps and unwraps are disabled.

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
~~~~

---

Everything below this line is my own work, not supplied input. The properties are my inferences.
They are listed in [`PROPERTIES.md`](PROPERTIES.md), which was written before any test. Each
property there names its source: a README section, or "Inferred" for P19–P23, which the README does
not state.

## Method

- Tests are in `test/SpectraWrappedTakara.t.sol`. They are built on the supplied
  `test/utils/LocalDeployment.sol`: the real Takara source, live tUSDC supply and exchange rate, and
  the wrapper behind a `TransparentUpgradeableProxy`.
- Fuzz tests ran 256 runs each. The two invariants each ran 256 runs × 500 calls, using a handler
  that does random deposits, redeems, wraps, unwraps and time warps, with interest accruing.
- **Interest accrual.** The local market has no borrows, and its live reserve factor is 100%, so its
  exchange rate never moves. For the accrual tests (P7, P8, P17, P18 and the invariants), the test
  contract, which is the Takara admin, sets the reserve factor to 10% and writes a non-zero
  `totalBorrows` into storage. Time is then warped so `accrueInterest` really changes the rate.
- **Takara limits.** These were triggered through the comptroller's own admin functions
  (`_setMintPaused`, `_setMarketSupplyCaps`, `_setRedeemPaused`). Low cash was simulated by moving
  cash into `totalBorrows`, which leaves the exchange rate unchanged.
- **Final command:** `forge test`. Result: **25 passed, 9 failed** (34 tests). In the final run,
  failing fuzz tests show `runs: 0` because forge replays its saved counterexample first. Each one
  also failed in a fresh run.

## Results per property

| ID | Property (short) | Test(s) | Result |
|----|------------------|---------|--------|
| P1 | deposit moves exactly `assets` into Takara, mints returned shares | `testFuzz_P1_depositMovesFunds` | PASS |
| P2 | redeem burns exactly `shares`, pays the returned USDC | `testFuzz_P2_redeemPaysReturned` | PASS |
| P3 | wrap/unwrap move exact amounts | `testFuzz_P3_wrapUnwrapMoveExactAmounts` | PASS |
| P4 | mint/withdraw/previewMint/previewWithdraw revert | `test_P4_unsupportedFunctionsRevert` | PASS |
| P5 | only the authority can pause/unpause/set rewards proxy | `testFuzz_P5_onlyAuthorityPrivileged` | PASS |
| P6 | paused ⇒ deposit/redeem/wrap/unwrap revert | `testFuzz_P6_pausedDisablesOperations` | PASS |
| P7 | previewDeposit == deposit (with and without accrual) | `testFuzz_P7_previewDepositExact_noAccrual`, `testFuzz_P7_previewDepositExact_withAccrual`, `invariant_P7_P8_P9_previewsExact` | PASS |
| P8 | previewRedeem == redeem (with accrual) | `testFuzz_P8_previewRedeemExact_withAccrual`, `invariant_P7_P8_P9_previewsExact` | PASS |
| P9 | previewWrap/previewUnwrap == wrap/unwrap | `testFuzz_P9_previewWrapUnwrapExact`, `invariant_P7_P8_P9_previewsExact` | PASS |
| P10 | asset/totalAssets/convertToShares/convertToAssets never revert | `test_P10_viewsNeverRevert_whilePaused_realisticInputs` (PASS); `testFuzz_P10_viewsNeverRevert` (FAIL, `x = 6.26e65`); `test_P10_convertToSharesMaxInput` (FAIL) | **FAIL** (bug B4) |
| P11 | conversions do not depend on the caller | `testFuzz_P11_conversionsCallerIndependent` | PASS |
| P12 | deposit up to maxDeposit succeeds; 0 while paused | `test_P12_maxDepositZeroWhilePaused` (PASS); `test_P12_maxDepositRespected_takaraMintPaused` (FAIL: "mint is paused"); `test_P12_maxDepositRespected_supplyCap` (FAIL: "market supply cap reached"); `test_P12_maxDepositRespected_maxAmount` (FAIL: overflow panic) | **FAIL** (bug B1) |
| P13 | redeem up to maxRedeem succeeds; 0 while paused | `test_P13_maxRedeemZeroWhilePaused` (PASS); `test_P13_maxRedeemRespected_lowTakaraCash` (FAIL: `RedeemFailed(15)` = `TOKEN_INSUFFICIENT_CASH`); `test_P13_maxRedeemRespected_takaraRedeemPaused` (FAIL: "redeem is paused") | **FAIL** (bug B2) |
| P14 | maxMint/maxWithdraw are 0 | `testFuzz_P14_maxMintWithdrawZero` | PASS |
| P15 | Deposit/Withdraw events carry the moved amounts | `testFuzz_P15_events` | PASS |
| P16 | third-party redeem spends allowance, reverts without it | `testFuzz_P16_redeemSpendsAllowance`, `testFuzz_P16_redeemWithoutAllowanceReverts` | PASS |
| P17 | conversions round down | `testFuzz_P17_conversionsRoundDown` | PASS |
| P18 | previewDeposit == convertToShares, previewRedeem == convertToAssets | `testFuzz_P18_previewsEqualConversions` | PASS |
| P19 *(inferred)* | wrapper's tTokens cover all unwrap claims | `invariant_P19_solvency` | PASS |
| P20 *(inferred)* | no round-trip profit (deposit→redeem, wrap→unwrap) | `testFuzz_P20_noRoundTripProfit` | PASS |
| P21 *(inferred)* | a donation can't zero out a non-dust deposit | `test_P21_donationCannotZeroOutDeposit` | **FAIL** (bug B3) |
| P22 *(inferred)* | no assets taken for zero shares / no shares burned for zero assets | `testFuzz_P22_noValueForNothing_redeem` (PASS); `testFuzz_P22_noValueForNothing_deposit` (FAIL) | **FAIL** (bug B5) |
| P23 *(inferred)* | no re-initialisation of proxy or implementation | `test_P23_noReinitialisation` | PASS |

The previews are exact. The wrapper's view-side copy of `accrueInterest` and of Compound's mint and
redeem math matched the real operations exactly in every fuzzed and invariant run, including runs
where interest accrued (P7–P9, P17, P18).

## Bugs found

### B1 — `maxDeposit` ignores Takara's mint limits and returns a value `deposit` can't accept (Medium)

- **Where:** `Spectra4626Wrapper.maxDeposit` (`src/utils/Spectra4626Wrapper.sol`). It returns
  `type(uint256).max` whenever the wrapper itself is not paused.
- **Evidence:** `deposit` reverts for amounts well inside `maxDeposit` in three cases:
  - Takara mint is paused (`mintGuardianPaused`): reverts with "mint is paused".
  - A Takara supply cap is set: reverts with "market supply cap reached".
  - The amount is `maxDeposit()` itself: `previewDeposit` overflows in `_divScalarByExpTruncate`
    (`assets * 1e36`).

  The same gap applies to Takara's `userMintPaused` and blacklist checks.
- **Why it's a bug:** This breaks the README promise that "`maxDeposit` … return limits that
  `deposit` … respect[s]". It also breaks EIP-4626, which requires `maxDeposit` to reflect global
  limits and to return 0 when deposits are disabled, even temporarily.
- **Impact:** The Spectra Principal Token, routers and aggregators use `maxDeposit` to size or
  route deposits. They will see "unlimited" and then revert, whenever Takara pauses minting or the
  market reaches its cap. A PT that pre-checks `maxDeposit` can't tell that deposits are disabled.
  Funds are not lost, but integrations stop working and the vault is not EIP-4626 compliant.
- **Fix:**
  - Return 0 when Takara has mint paused, user-mint paused, or the wrapper blacklisted.
  - Otherwise return the room left under the supply cap
    (`supplyCap - (cash + borrows - reserves) - 1`), capped below the overflow bound.

### B2 — `maxRedeem` ignores Takara liquidity and Takara's redeem pause (Medium)

- **Where:** `Spectra4626Wrapper.maxRedeem`. It returns `balanceOf(owner)` whenever the wrapper is
  not paused.
- **Evidence:** `redeem(maxRedeem(owner))` reverts in two cases:
  - Takara's cash can't cover the redemption: reverts with `RedeemFailed(15)`, which is
    `TOKEN_INSUFFICIENT_CASH`. This is the normal state of a highly-utilised lending market.
  - Takara's redeem guardian is paused: reverts with "redeem is paused".
- **Why it's a bug:** This breaks the README promise that `maxRedeem` returns limits that `redeem`
  respects. It also breaks EIP-4626, which says `maxRedeem` must return the largest amount that
  won't revert.
- **Impact:**
  - When utilisation is high, the PT and other integrators are told every share is redeemable, but
    the redemption reverts.
  - Callers can't size a partial redemption that would still succeed using the vault's own
    interface.
  - At PT expiry or withdrawal time this can block exits and make keepers or users retry blindly.
- **Fix:**
  - Return 0 when Takara redeem is paused.
  - Otherwise return the lower of the owner's balance and the shares worth Takara's current cash at
    the up-to-date rate.

### B3 — Inflation/donation griefing on an empty wrapper (Low)

- **Where:** Share pricing in `_previewWrap` uses `_decimalsOffset() == 0`, so there is only one
  virtual share and one virtual tToken. `totalVaultShares()` is the wrapper's raw tToken balance, so
  anyone can inflate it by transferring tTokens in directly.
- **Evidence (`test_P21_donationCannotZeroOutDeposit`):**
  - The attacker wraps 1 wei of tToken into the empty wrapper and gets 1 share.
  - The attacker then donates about 19,168 tTokens (~20,000 USDC).
  - A victim then deposits 10,000 USDC and gets **0 shares**, so their redeemable value is 0.
  - The attacker can redeem 15,000.5 USDC of the 20,001 they spent. The other ~15,000 is stuck
    behind the virtual share.
- **Impact:** The attacker loses about 5,000 USDC, so the attack isn't profitable. But the victim
  loses all 10,000 USDC, so it is a cheap griefing or front-running attack against the first real
  depositor. The PT itself could be that depositor if it deposits into a freshly deployed wrapper.
- **Severity:** Low, because it only applies before the wrapper has a meaningful supply.
- **Mitigation:** Any of these helps:
  - Seed the wrapper at deployment.
  - Use a non-zero `_decimalsOffset()`.
  - Have depositors use slippage checks (`minShares`, as `wrap` offers but `deposit` doesn't).

### B4 — `convertToShares` reverts for very large inputs, against the README's "never revert" (Informational)

- **Where:** `SpectraWrappedTakara._divScalarByExpTruncate`. It computes `1e18 * assets * 1e18`
  with checked arithmetic, so `convertToShares` reverts once `assets` is above about 1.16e41. The
  fuzzer found `6.26e65`, and `type(uint256).max` also reverts.
- **Impact:** EIP-4626 explicitly allows conversion functions to revert on integer overflow from
  unreasonably large inputs. These amounts are far beyond any real USDC supply, so the practical
  impact is nil. It still contradicts the README's unconditional "never revert", and anything that
  probes `convertToShares(type(uint256).max)` will revert.
- **Fix:** Either document the bound, or compute with `Math.mulDiv` so the result saturates instead
  of overflowing.

### B5 — `deposit` can take USDC and mint zero shares (Informational)

- **Where:** `SpectraWrappedTakara._deposit` and `deposit`. Neither checks for a zero result.
- **Evidence:** At the live rate (≈1.0435 USDC per tToken), `deposit(1)` (1 wei of USDC) makes
  Takara mint 0 tTokens, so the wrapper mints 0 shares. The USDC goes to existing Takara suppliers.
  The redeem direction did not show the mirror problem (P22 redeem test passed).
- **Impact:** Only dust can be lost. It matches `previewDeposit` (which also returns 0), so it is
  EIP-4626-consistent, but a `shares == 0` revert would be safer.

## Other observations (not counted as bugs)

- **Pausing also freezes share transfers.** `_update` is `whenNotPaused`, so wrapper share
  transfers are blocked while paused. The README only lists deposits, redemptions, wraps and
  unwraps.
- **A dead and inconsistent fallback in `_withdraw`.** It caps the payout to the wrapper's USDC
  balance. If that ever triggered, `redeem` would return OpenZeppelin's preview value while paying
  less, which would break "redeem returns the assets actually paid". Because the previews are exact,
  no test could trigger it.
- **Stranded USDC.** Any USDC sent straight to the wrapper stays there; there is no sweep function.

## Environment notes

- **Foundry install.** Foundry was not installed. I downloaded the official `forge` release binary
  from GitHub releases, and `forge soldeer install` fetched the locked dependencies. These were
  toolchain downloads only; I did no web browsing.
- **Earlier GitHub check.** Earlier in the same session, before this task, I used the GitHub
  connector to list Actions runs and PRs, to answer a separate question. I did not use any connector
  for this task.
- **Files and git.** No commits, pushes or PRs were made. The only files added are `PROPERTIES.md`,
  `REPORT.md` and `test/SpectraWrappedTakara.t.sol`. The `dependencies/`, `out/` and `cache/`
  build outputs are git-ignored.
