# Report: SpectraWrappedTakara formal-verification audit

## Run metadata

| Field | Value |
|-------|-------|
| Cell ID | F2 |
| Input version | F2-pilot-amendment-2026-10-27-v2 |
| Supplied template commit | d492bed455059b8f650cfab30601a8e2207d8ae0 (the repo's only commit, `git log` HEAD) |
| Model / version | claude-opus-5-5 (Opus 5.5), as stated in this session's system prompt. The serving model was not checked with any tool. |
| Duration | About 9 minutes of wall-clock time, measured with in-session `date` timestamps from the first command to the final compile. Time spent reasoning before the first command is not included. |
| Date | 2026-10-27 |
| Certora CLI | certora-cli 8.20.3, solc 0.8.23 |
| Prover jobs submitted | None. The only check run was `certoraRun --compilation_steps_only`. |

### Environment notes (deviations a reader should know about)

- `certoraRun`, `solc` and the OpenZeppelin dependencies (`dependencies/`, which is gitignored) were **not** in the container,
  even though the prompt says the Certora CLI is installed. To compile, I installed `certora-cli` and `solc-select` from PyPI.
  I installed solc 0.8.23 with `solc-select`, and unpacked `@openzeppelin/contracts@5.4.0-rc.1` and
  `@openzeppelin/contracts-upgradeable@5.4.0-rc.1` from the npm registry into `dependencies/` at the paths
  `remappings.txt` expects. These were package-registry downloads only. I did not browse the web, and I used no repository or
  cross-session connectors.
- `forge` is not installed, so nothing was run with Foundry. Bug B1 is backed by an exact integer replay of the
  wrapper's arithmetic in `poc/donation_inflation.py`.
- `foundry.toml` pins `solc_version = "0.8.23"` together with `evm_version = "cancun"`, but solc 0.8.23 rejects
  `cancun`. The Certora build uses solc's default EVM version. This is a build-configuration issue and has no security impact.
- No commits, pushes or pull requests were made.

### Compilation result

```
$ certoraRun certora/conf/SpectraWrappedTakara.conf --compilation_steps_only
... Compiling certora/harness/SpectraWrappedTakaraHarness.sol / TTokenMock.sol / StandardERC20.sol
WARNING: Target contract SpectraWrappedTakaraHarness 'types' is not a dict but NoneType: None
EXIT=0
```

The local CVL typechecker does run as part of this step. To confirm, I injected an undeclared variable into a scratch copy of the spec, and
it was rejected (`Variable priceAfterXX has not been declared`, exit 1). The real spec typechecks cleanly. The
remaining warnings are only about storage-layout output for interfaces.

## Files produced

| Path | Purpose |
|------|---------|
| `PROPERTIES.md` | Properties, split into supplied (S*) and inferred (I*) |
| `certora/specs/SpectraWrappedTakara.spec` | The CVL specification (33 rules/invariants) |
| `certora/conf/SpectraWrappedTakara.conf` | Prover configuration (uses `storage_extension_annotation` to hook ERC-7201 balances) |
| `certora/harness/SpectraWrappedTakaraHarness.sol` | The wrapper plus view helpers `sharePrice()` and `decimalsOffsetHarness()`. No behaviour change. |
| `certora/harness/TTokenMock.sol` | A Compound-v2 tToken model. Its rate is accrued for the current block and only rises. Mint and redeem use the same rounding as `Exponential.sol`. |
| `poc/donation_inflation.py` | Integer replay of bug B1 using the live tUSDC exchange rate |

**Modelling assumptions.** Takara is replaced by `TTokenMock`, which is allowed because the README trusts Takara. USDC is a
standard ERC-20. The AccessManager's `canCall` is `NONDET`. `claimRewards` (a DAO-only delegatecall) and
`initialize` are excluded from parametric rules. `setupLinks()` ties `asset()`, `vaultShare()` and
`ttoken.underlying()` together and bounds supplies to below 2^128.

## Properties → rules

The outcomes below are **expected** outcomes. No prover job was submitted, so none of them was observed. "Holds" means manual
review found no violation. "Violated" means manual review and/or the integer replay found a concrete counterexample.

### Supplied requirements (README)

| ID | Property (short) | Rule(s) | Expected |
|----|------------------|---------|----------|
| S1 | totalSupply = sum of balances | `totalSupplyIsSumOfBalances` (invariant, ghost + ERC-7201 hooks) | Holds |
| S2 | Price never decreases | `priceNeverDecreases` (parametric), `priceNeverDecreasesOnAccrual` | Holds |
| S3 | Paused ⇒ deposit/redeem/wrap/unwrap revert | `pausedDepositReverts`, `pausedRedeemReverts`, `pausedWrapReverts`, `pausedUnwrapReverts` | Holds |
| S4 | tToken donation does not move price | `donationDoesNotMovePrice` | **Violated (B1)** |
| S5 | Fair deposit (≥ a − ε via previewRedeem) | `fairDeposit` | **Violated (B1)** |
| S6 | asset/totalAssets/convertToShares/convertToAssets never revert | `assetNeverReverts`, `totalAssetsNeverReverts`, `convertToSharesNeverReverts`, `convertToAssetsNeverReverts` | **Violated (B2)** for convertToShares/convertToAssets. The others hold in the model. |
| S7 | Conversions independent of caller | `conversionsIndependentOfCaller` | Holds |
| S8 | deposit/redeem respect maxDeposit/maxRedeem | `depositRespectsMaxDeposit`, `redeemRespectsMaxRedeem` | Holds |
| S9 | maxDeposit/maxRedeem = 0 while paused | `maxLimitsZeroWhenPaused` | Holds |
| S10 | maxMint/maxWithdraw = 0; mint/withdraw unsupported | `mintWithdrawUnsupported` | Holds |
| S11 | Deposit / Withdraw events emitted | No CVL rule (events are not storage). Checked by manual review: `_deposit` emits `Deposit` and `_withdraw` emits `Withdraw`. | Holds (manual) |
| S12 | Third-party redeem spends allowance | `redeemSpendsAllowance` | Holds |
| S13 | Conversions round down | `conversionRoundTripRoundsDown` | Holds |
| S14 | previewDeposit ≤ deposit's minted shares | `depositMatchesPreview` (2nd assert) | Holds |
| S15 | deposit returns shares minted | `depositMatchesPreview` (1st assert) | Holds |
| S16 | previewRedeem ≤ redeem's paid assets | `redeemMatchesPreview` (2nd assert) | Holds (see B4) |
| S17 | redeem returns assets paid | `redeemMatchesPreview` (1st assert) | Holds in reachable states (latent mismatch, B4) |
| S18 | previewDeposit = convertToShares, previewRedeem = convertToAssets | `previewsEqualConversions` | Holds |
| S19 | Only the authority has privileged access | `pauseOnlyByPauseUnpause`, `rewardsProxyOnlyBySetter`, plus manual review (`pause`, `unpause`, `setRewardsProxy` and `claimRewards` are all `restricted`) | Holds |

### Inferred properties (auditor)

| ID | When added | Property (short) | Rule(s) | Expected |
|----|------------|------------------|---------|----------|
| I1 | Before investigation | Nonzero deposit/wrap never mints 0 shares | `depositNeverMintsZero`, `wrapNeverMintsZero` | **Violated (B1)** |
| I2 | Before investigation | Third-party unwrap spends allowance | `unwrapSpendsAllowance` | Holds |
| I3 | Before investigation | Every share is backed (owner can always unwrap) | `unwrapOwnBalanceNeverRunsShort` | Holds |
| I4 | Before investigation | deposit/redeem leave the wrapper's USDC balance unchanged | `wrapperUsdcBalanceUnchanged` | Holds (see B4 for stray USDC) |
| I5 | Before investigation | maxDeposit/maxRedeem never overstate what is accepted | `depositUpToMaxDepositSucceeds` (mock side); Takara-side limits by manual review | **Violated (B3)**. The mock has no comptroller, so this rule can only expose the overflow side. |
| I6 | Before investigation | Share transfers revert while paused | `pausedTransfersRevert` | Holds |
| I7 | During investigation | The view-replicated rate equals Takara's real accrued rate | Manual line-by-line comparison with `TToken.accrueInterest`, `exchangeRateStoredInternal` and `Exponential.sol`. The mock encodes the exact rounding used by mint and redeem. | Holds |
| I8 | During investigation | Backing ratio is changed only by wrapper operations | `donationDoesNotChangeBacking` | **Violated (B1)** |

## Bugs found

### B1. Share price comes from the live tToken balance, so donations move it (inflation and zero-share deposits). Severity: Medium

**Violates:** S4, S5 (supplied), I1, I8 (inferred).

**Root cause.** `Spectra4626Wrapper.totalVaultShares()` returns `IERC20(vaultShare).balanceOf(address(this))`.
`_previewWrap` and `_previewUnwrap` price shares off that value:

```solidity
_previewWrap(t)   = t * (totalSupply() + 10**_decimalsOffset()) / (totalVaultShares() + 1)   // floor
_previewUnwrap(s) = s * (totalVaultShares() + 1) / (totalSupply() + 10**_decimalsOffset())   // floor
```

Anyone can raise `totalVaultShares()` by transferring tTokens straight to the wrapper. That changes the
value of every share immediately, which breaks S4. `_decimalsOffset()` is the OpenZeppelin default of 0, so there is only a single
virtual share to absorb the attack. Neither `deposit` nor the 2-argument `wrap` checks that `shares > 0`.

**Concrete counterexample.** This is the output of `python3 -I poc/donation_inflation.py`, an exact replay of the contract's integer maths
at the live tUSDC rate 1.043481707972219062e18:

```
fresh wrapper: price of one share = 1043481 wei USDC
attacker deposit 2 wei -> shares: 1
S4: price before donation 1043481, after 521740855029591  -> CHANGED
S5: victim deposits 500000000 wei USDC -> shares 0, worth 0 (required >= 499999990)
attacker spent 1043481709 wei USDC, got back 771740854; victim lost 500000000; left in wrapper with no owner: 739582542 tTokens
```

**Impact.**
- On a fresh or low-supply wrapper, an attacker front-runs a deposit with a 1-share deposit and a tToken donation.
  The victim's `deposit`, or the Spectra PT contract depositing on users' behalf, mints **0 shares** and the
  victim loses the whole deposit (500 USDC above). With offset 0 the attacker also loses money, so the attack is griefing. A
  milder version, where the donation is sized so the victim's shares round from ~2 down to 1, destroys about a third of the victim's deposit.
- Any donation, accidental or deliberate, changes the share price that Spectra uses as the IBT rate. A
  donor can bump the rate at will, which can be used to shift yield between PT and YT holders.

**Fix.** Track the wrapped tToken amount in storage, increasing it in `wrap`/`_deposit` by the tTokens actually received and
decreasing it in `unwrap`/`_withdraw`, and use that instead of `balanceOf`. Also use a nonzero
`_decimalsOffset()` and/or revert when `shares == 0` for nonzero input.

### B2. `convertToShares` / `convertToAssets` (and `totalAssets`) can revert. Severity: Low

**Violates:** S6 as worded in the README ("never revert").

- `_divScalarByExpTruncate` computes `1e18 * assets * 1e18` with checked arithmetic, so
  `convertToShares(assets)` reverts for `assets > 2^256 / 1e36 ≈ 1.16e41`. `convertToSharesNeverReverts` gets a
  counterexample at, for example, `assets = max_uint256`.
- `_convertToAssets` computes `rate * tTokens` with checked arithmetic, so `convertToAssets` reverts once
  `tTokens > 2^256 / rate`. `_previewUnwrap`'s `mulDiv` also reverts if its result exceeds 2^256.
- In production, all four functions also make external calls into Takara (`accrualBlockTimestamp`, `getCash`,
  `totalBorrows`, the interest-rate model's `getBorrowRate`, and so on) and run the accrual arithmetic
  (`borrowRate * Δt * borrows`, `cash + borrowsNew − reservesNew`). Any revert in that code, including an overflow after a long
  gap with no accrual, makes `totalAssets`, `convertToShares` and `convertToAssets` revert.

**Impact.** EIP-4626 itself tolerates overflow on unreasonably large inputs, so the economic impact is low. But the
README promises "never revert", and integrators such as Spectra PT and aggregators that call these as safe views can fail.
**Fix:** use `Math.mulDiv` for the 1e36 scaling, or saturate. Do not let the views revert.

### B3. `maxDeposit` / `maxRedeem` ignore Takara-side limits. Severity: Low

**Violates:** I5 (EIP-4626: max* "MUST NOT be higher than the actual maximum that would be accepted").

`maxDeposit` returns `type(uint256).max` whenever the wrapper is not paused, and `maxRedeem` returns `balanceOf(owner)`.
Takara's `ComptrollerV2.mintAllowed` can still reject a deposit: it reverts on `mintGuardianPaused`, and it returns an error code
(so the wrapper reverts with `MintFailed`) on `userMintPaused` or when `supplyCaps` is exceeded. `redeemAllowed` reverts on
`redeemGuardianPaused`, and a redeem fails when the market lacks cash because the liquidity is borrowed out. Integrators that size calls
from `maxDeposit`/`maxRedeem` will revert. **Fix:** read the comptroller's pause flags, the supply cap and `getCash()`, and
return the tighter bound.

### B4. Redeem's balance cap is unreachable and would return a wrong value if it ever triggered. Severity: Informational

In `SpectraWrappedTakara._withdraw`, `assets` is capped to the wrapper's USDC balance. That cap only changes the local
copy: OpenZeppelin's `redeem` still **returns the uncapped `previewRedeem` value**. If the cap ever bound, `redeem` would
return more than it paid, breaking S17, and pay less than its preview, breaking S16. The cap can also spend stray USDC that someone sent to the wrapper. Under
the exact rate replication (I7) the realised amount always equals the preview, so the cap never binds in reachable
states. Separately, USDC sent directly to the wrapper cannot be recovered. **Fix:** remove the cap, or compute the paid amount
from the balance delta and return it.

### Checked and not found to be a bug

- **S2 (price never decreases).** Wrapper operations round in the vault's favour: deposit and wrap mint at most
  `t·(S+1)/(V+1)`, while redeem and unwrap pay at most `s·(V+1)/(S+1)`. So `(V+1)/(S+1)` never decreases. Takara's stored rate
  also does not decrease under mint/redeem rounding or accrual with a reserve factor ≤ 1.
- **S3.** Each of the four paths reverts while paused: through `whenNotPaused` on `previewDeposit`, `previewRedeem`, `previewWrap` and `previewUnwrap`, and
  through `_update`. This includes zero-amount calls.
- **I7.** `_currentExchangeRate` reproduces `accrueInterest` + `exchangeRateStoredInternal` exactly, with the same order and
  truncation. `_divScalarByExpTruncate` and `_mulScalarTruncate` match `Exponential.sol`.

## Run inputs

### Initial prompt (verbatim)

````text
@"/root/.claude/uploads/e5685108-3269-5846-8b7c-8beedd7252e5/7af0cf1e-L2-README.md" Find bugs in this project. Use the supplied README as the project documentation.

First, before writing any rule, write PROPERTIES.md in the project root: the properties this project must satisfy, each in one plain-language sentence.

Check all requirements in the supplied README. You may also infer additional properties, investigate other failure modes, and write rules for them. In PROPERTIES.md and REPORT.md, distinguish supplied requirements from properties you inferred, including any added during the investigation.

Then write a Certora specification that expresses those properties. The Certora CLI (certoraRun) is installed; check that your specification compiles with certoraRun --compilation_steps_only, and do not submit prover jobs. Write REPORT.md in the project root: for each property, the rule that expresses it; then each bug found and its impact.

Work only in the disposable source copy. Do not access or modify shared repositories, use repository or cross-session connectors, browse the web, commit, push, or create a pull request.

In REPORT.md, include a "Run inputs" section quoting this entire initial prompt and the supplied README verbatim. Keep supplied inputs separate from the properties you inferred. Record cell ID F2 and input version F2-pilot-amendment-2026-10-27-v2. The supplied template commit is d492bed455059b8f650cfab30601a8e2207d8ae0. Record the model/version and duration if available; mark unavailable values unknown. Do not use external tools to discover this metadata.
````

### Supplied README (verbatim)

`````markdown
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
`````
