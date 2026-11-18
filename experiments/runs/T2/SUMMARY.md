# Summary: SpectraWrappedTakara property testing (T02)

Cell ID T2 · Input version T2-pilot-amendment-2026-10-27-v2 · Template commit d492bed455059b8f650cfab30601a8e2207d8ae0
Model: claude-opus-5-5 (configured ID) · Toolchain: forge 1.7.1, solc 0.8.23

## Result

`forge test`: **44 tests, 34 passed, 10 failed.** Each failure reproduces a bug (tests named `*_Bug_*`, plus one stateful invariant).
Fuzz tests ran 256 times each; the invariant suites ran 256 sequences × 500 calls, with and without tToken donations.

## Findings

| # | Severity | Property broken | Bug | Evidence |
|---|---|---|---|---|
| F1 | High | README #4 (donations don't move price) | The share price uses the wrapper's raw tToken `balanceOf`, so direct transfers change it | One share's value 1 043 481 → 2 086 962 after a ~1000 USDC donation |
| F2 | High | README #5 (fair deposit); inferred I10 | Inflation and donation griefing (offset = 0, no internal accounting) | Depositor lost 349 wei after a ~1 USDC donation (ε = 10); a 1000 USDC deposit got 0 shares; the fuzzer found "donate into empty wrapper → deposit" |
| F3 | Medium | README ERC-4626 (maxRedeem respected); inferred I8 | `maxRedeem` ignores Takara's available cash | `redeem(maxRedeem)` reverts `RedeemFailed` when cash is lent out (borrows simulated) |
| F4 | Low | Inferred I9 (maxDeposit respected) | `maxDeposit` = uint max, but deposits > ~1.16e41 overflow | A 2e41 deposit reverts |
| F5 | Low / info | README #2 (price never decreases), corner case | Takara resets its rate to 1e18 when its tToken supply reaches 0 | Value 1 043 481 → 1 000 000; no holders affected |
| F6 | Info | README ERC-4626 ("conversions never revert") | `x * 1e36` overflows on huge inputs (EIP-4626 allows this) | `convertToShares(2e41)` reverts |

## Passing properties

Supply consistency, price never decreasing in normal operation, pause closes every entry point, caller-independent conversions,
maxDeposit/maxRedeem = 0 while paused, maxMint/maxWithdraw = 0, events, allowance spending, round-down conversions,
previews exact (including after interest accrual with borrows), solvency, no round-trip profit, no stranded USDC,
access control, initialization lock.

## Recommended fix

Track the wrapper's tTokens in an internal storage variable instead of using `balanceOf`, and set a non-zero
`_decimalsOffset()` (for example 6). Together these fix F1 and F2. Cap `maxRedeem` by `tToken.getCash()` (F3)
and `maxDeposit` below the overflow bound (F4).

## Test-harness notes

Two flaws in my own tests were found and fixed before the final run. First, the invariant handler's pause action was
reverting on every call, so the pause invariant passed without testing anything. Second, the I7 interest test hit
Takara's cash limit rather than checking preview exactness. Full details are in `REPORT_T02.md`.
