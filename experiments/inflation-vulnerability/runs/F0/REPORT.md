# Formal-verification report: SpectraWrappedTakara

## Prompt (verbatim)

```
Find bugs in the current project.

Before writing any specification, write PROPERTIES.md: the properties this project must satisfy, each in one plain-language sentence.

Then write Certora specifications checking those properties. Compile locally using --compilation_steps_only. Do not submit prover jobs.

Write REPORT.md describing each property, its corresponding rule, compilation result, and any suspected bugs. Include this exact prompt.

Work only in the disposable copy. Do not commit, push, or create a PR.
```

## Scope and setup

- **Disposable copy:** all work is in this directory, a copy of the repository with `.git` removed. The original checkout was not modified. Nothing was committed or pushed, and no PR was opened.
- **Contracts in scope:** `src/utils/Spectra4626Wrapper.sol` and `src/takara/SpectraWrappedTakara.sol`. The wrapper sits on a Takara tToken (`lib/takara`, a Compound v2 fork).
- **Dependencies:** OpenZeppelin 5.4.0-rc.1 and OpenZeppelin-upgradeable 5.4.0-rc.1, downloaded into `dependencies/` from the URLs in `soldeer.lock`.
- **Tooling:** `certora-cli 8.20.2` and `solc 0.8.23`, installed in a scratch virtualenv.

| File | Purpose |
|---|---|
| `PROPERTIES.md` | The properties, one sentence each (written before any spec) |
| `certora/munged/SpectraWrappedTakara.sol` | Copy of the wrapper with only two changes: import paths, and `private` changed to `internal` on the three rate helpers (`munge.diff`) |
| `certora/harness/SpectraWrappedTakaraHarness.sol` | Exposes `currentExchangeRate`, `divScalarByExpTruncate` and `mulScalarTruncate` to CVL |
| `certora/specs/SpectraWrappedTakara.spec` | All the rules |
| `certora/conf/SpectraWrappedTakara.conf` | Prover configuration |

**Verification model:**
- The market is the **real Takara `TErc20Delegate` code**, used directly as the tToken.
- The underlying is `StandardERC20`.
- The interest rate model is a deterministic ghost function. This is sound because it is a pure view of (cash, borrows, reserves).
- The comptroller hooks are `NONDET`, so they may allow or reject.
- `AccessManager.canCall` is a ghost permission table with zero delay.
- Calls through interfaces are resolved with `DISPATCHER`.

## Compilation result

```
certoraRun certora/conf/SpectraWrappedTakara.conf --compilation_steps_only
Compiling certora/harness/SpectraWrappedTakaraHarness.sol...            (+ internal-info pass)
Compiling lib/takara/src/TErc20Delegate.sol...                          (+ internal-info pass)
Compiling src/tokens/StandardERC20.sol...                               (+ internal-info pass)
exit=0
```

- **Solidity:** all three files compile cleanly.
- **CVL typecheck:** passes. The typechecker runs locally as part of `--compilation_steps_only`. To confirm it really runs, I appended an undefined call to a copy of the spec, and it was rejected with "No function-like entry for nonexistent".
- **Prover:** no jobs were submitted, so **no rule has a verification result**. "Expected outcome" below is my analysis, not prover output.
- **EVM target:** the conf uses `shanghai`. The project's `cancun` fails with solc 0.8.23 (see B5).

## Properties → rules

| ID | Property (from PROPERTIES.md) | Rule | Expected outcome |
|---|---|---|---|
| P1 | The view exchange rate equals the rate the tToken stores after `accrueInterest()` in the same block | `P1_exchangeRateMatchesAccrual` | Hold. Manual review found the replay matches `TToken.accrueInterest` and `exchangeRateStoredInternal` step for step |
| P2 | `deposit` gives the wrapper exactly the predicted tTokens | `P2_depositTTokenParity` | Hold. `mintFresh` reads the rate before `doTransferIn`, and the wrapper's cash is unchanged before the mint |
| P3 | `redeem` sends exactly `previewRedeem(shares)` | `P3_redeemAssetParity` | Hold |
| P4 | `deposit` mints exactly the returned shares, to the receiver only | `P4_depositMintsReturnedShares` | Hold |
| P5 | `deposit` leaves the wrapper's underlying balance unchanged | `P5_depositKeepsNoUnderlying` | Hold |
| P6 | `redeem` burns exactly `shares` | `P6_redeemBurnsShares` | Hold |
| P7 | `redeem`'s return value equals what the receiver got | `P7_redeemReturnValueIsHonest` | Hold while P3 holds. Fragile, see B4 |
| P8 | A non-zero deposit that mints 0 shares reverts | `P8_noZeroShareDeposit` | **Violated (B1)** |
| P9 | A deposit followed by a redeem returns no more than was deposited | `P9_roundTripNoProfit` | Hold. Every step rounds down |
| P10 | Backing per share `(V+1)/(S+1)` never decreases | `P10_backingPerShareNonDecreasing` (parametric over deposit, redeem, wrap×2, unwrap×2) | Hold |
| P11 | Amounts ≤ `maxDeposit` can be previewed | `P11_maxDepositIsPreviewable` | **Violated (B2)** |
| P12 | Redeems ≤ `maxRedeem` don't need more cash than Takara has | `P12_maxRedeemRespectsLiquidity` | **Violated (B3)** |
| P13 | `mint`, `withdraw`, `previewMint` and `previewWithdraw` revert, and `maxMint`/`maxWithdraw` are 0 | `P13_unimplementedAlwaysRevert`, `P13_maxMintMaxWithdrawZero` | Hold |
| P14 | `wrap(v)` moves `v` tTokens in and mints `previewWrap(v)` | `P14_wrapExact` | Hold |
| P15 | `unwrap(s)` burns `s` and sends `previewUnwrap(s)` tTokens | `P15_unwrapExact` | Hold |
| P16 | A third party can spend only its allowance, and the allowance shrinks by the shares spent | `P16_thirdPartySpendsAllowance` | Hold |
| P17 | `pause`, `unpause`, `setRewardsProxy` and `claimRewards` need AccessManager authorization | `P17_restrictedFunctions` | Hold. Caveat: OZ `AuthorityUtils` calls `canCall` with a low-level `staticcall`, so check that the `canCall` summary actually applies when you first run the prover |
| P18 | `deposit`, `redeem`, `wrap`, `unwrap` and transfers revert while paused | `P18_pausedBlocksUserActions` | Hold. Previews and `_update` are `whenNotPaused` |
| P19 | `maxDeposit` and `maxRedeem` are 0 while paused | `P19_pausedLimitsZero` | Hold |

## Suspected bugs

### B1 — A deposit that mints zero shares takes the depositor's assets (P8) — Low/Medium

`SpectraWrappedTakara._deposit` never checks for `shares == 0`. Takara's `mintFresh` also allows minting 0 tTokens.

**Example:** with the live tUSDC rate in `LocalDeployment` (≈ 1.0435e18), `deposit(1, user)` gives `tTokens = floor(1e18 / 1.0435e18) = 0` and `shares = 0`.
- The 1 wei of USDC is still pulled and supplied to Takara.
- That wei goes to the other tToken holders, and the depositor receives nothing.

The amount grows when the wrapper's `totalSupply`/`totalVaultShares` ratio is skewed. For example, a first depositor can donate tTokens directly, so `_previewWrap` floors a whole deposit to 0.

**Fix:** revert when `previewDeposit(assets) == 0`, or when the tTokens actually minted are 0.

### B2 — `maxDeposit` claims an unlimited amount, but large deposits always revert (P11) — Low (ERC-4626 compliance)

- `maxDeposit` returns `type(uint256).max` when the wrapper is not paused.
- `_divScalarByExpTruncate` computes `1e18 * scalar * 1e18`, which overflows (checked arithmetic, so it reverts) once `assets > 2^256 / 1e36 ≈ 1.16e41`.
- Takara's comptroller can also reject mints (mint pause, supply caps) while `maxDeposit` still advertises max.

ERC-4626 requires `maxDeposit` to return an amount that would not revert. Integrators such as the Spectra PT router may rely on it.

### B3 — `maxRedeem` ignores Takara's liquidity (P12) — Low/Medium (ERC-4626 compliance)

`maxRedeem(owner)` returns `balanceOf(owner)`. When the market's cash is lent out, `tToken.redeem` returns `TOKEN_INSUFFICIENT_CASH` and the wrapper reverts with `RedeemFailed`.

ERC-4626 says `maxRedeem` must account for such limits. A suitable cap is: shares whose `previewRedeem` is no more than `tToken.getCash()`.

### B4 — The `_withdraw` "cap" silently underpays and misreports (P7) — Low

```solidity
uint256 balance = IERC20(asset()).balanceOf(address(this));
if (assets > balance) assets = balance;
```

If the amount actually redeemed is ever below `previewRedeem`, three things happen:
- The user silently receives less.
- The `Withdraw` event logs the reduced amount.
- OZ's `redeem` still **returns the uncapped `previewRedeem` value**, so the return value and the transfer disagree.

The cap also draws on any stray underlying the wrapper holds, which belongs to nobody in particular. Given P1–P3 the branch should be unreachable. If so it is dead code that hides a broken invariant, and reverting (or asserting equality) would be safer. P7 turns into a violation the moment P3 fails.

### B5 — Build configuration: `evm_version = "cancun"` with `solc_version = "0.8.23"` — Low (tooling)

Cancun support in solc starts at 0.8.24. Compiling with 0.8.23 and `--evm-version cancun` fails with "Invalid EVM version requested", which I reproduced through certoraRun. The spec therefore targets `shanghai`. The project should pin solc ≥ 0.8.24 or set `evm_version = "shanghai"`.

### Notes (not counted as bugs)

- **First-depositor inflation:** the wrapper uses a virtual offset of 0 (`10**_decimalsOffset() = 1`). The standard OZ mitigation bounds the attacker's profit, but rounding grief is still possible, and it is what makes B1 large.
- **Rate cap not mirrored:** the view rate does not mirror Takara's `borrowRateMaxMantissa` `require`. When that cap trips, the real operation reverts while previews still return a value. This is only a preview inconsistency, with no loss of funds.
- **Exchange-rate replay checked by hand:** `_currentExchangeRate` matches Takara's `accrueInterest` step for step (operation order, truncation and overflow points). I found no mismatch, and P1 is the rule that checks it.

## Next steps

Run `certoraRun certora/conf/SpectraWrappedTakara.conf` without `--compilation_steps_only` to get real results. Expect P8, P11 and P12 to produce counterexamples, and check `rule_sanity` on P17.
