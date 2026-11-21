# Experiment 01: F1 CVL translation review

> **Reviewer notes, not agent output.** Written by the orchestrator during the research, from the run artifacts in [`../runs`](../runs). Copied from the private research repository; links to private material (evaluation project, template, prover jobs, sessions) were removed and file links point to this folder. See [the index](README.md).

Static review of the eight supplied artifacts identified in [F1 findings](F1.md). Line references below refer to the unchanged submitted `SpectraWrappedTakara.spec`, not an evaluator rewrite. No independent typecheck or prover result is claimed.

## Overall verdict

Most assertions express their stated informal claims on the selected calls and modeled states. The principal economic omission is already present in `PROPERTIES.md`; correct translation of those properties would still not establish depositor protection. Some rules cover narrower domains than the informal wording, one property has no CVL rule, and the environment assumptions require separate review.

For CVL calls without `@withrevert`, reverting paths are excluded. This is appropriate for conditional promises about successful operations, but cannot establish availability. The limit and no-revert rules correctly use `@withrevert`. [Certora statements](https://docs.certora.com/en/latest/docs/cvl/statements.html).

## Informal-to-formal map

| Informal property | Rule / lines | Assessment |
|---|---|---|
| P-01/P-02: preview lower bound and minted balance delta | `depositMatchesPreview`, 133-146 | Faithful for successful deposits, excluding receiver = wrapper. No fair-value guarantee. |
| P-03/P-04: preview lower bound and actual underlying received | `redeemMatchesPreview`, 152-168 | Faithful on successful calls, excluding wrapper/tToken receivers. Measures a token balance delta, not only the return value. |
| P-05/P-06: exact wrap/unwrap previews | `wrapMatchesPreview`, 174-185; `unwrapMatchesPreview`, 187-198 | Faithful for the basic overloads and selected receivers. Does not cover the slippage overloads. |
| P-07: paused operations revert | `pausedBlocksOperations`, 204-213 | Faithful for deposit/redeem and all four wrap/unwrap overloads; uses `@withrevert`. |
| P-08: paused maximums are zero | `maxLimitsZeroWhenPaused`, 215-219 | Direct translation. No shared `setup()`; interpret as a storage-level check, not proof of deployment wiring. |
| P-09: only authorized callers use restricted operations | `onlyAuthorizedCanCallRestricted`, 225-234 | Correct implication shape, conditional on faithful resolution of low-level authority calls and the zero-delay mock. |
| P-10: privileged state changes only through restricted operations | `privilegedStateOnlyChangedByRestricted`, 236-250 | Covers successful selected methods, excludes initialization and rewards delegatecall. Does not validate initialization safety or arbitrary rewards execution. |
| P-11: mint/withdraw disabled, maximums zero | `mintAndWithdrawDisabled`, 256-265 | Direct translation. Does not claim or check disabled previewMint/previewWithdraw as F0 did. |
| P-12: funded/approved deposits within maximum succeed | `depositWithinMaxDepositDoesNotRevert`, 271-284 | Correct operation and revert assertion, but bounded positive amounts and nonzero receivers only. Does not exclude a zero caller; a failure may be a token input-domain artefact. |
| P-13: owner or approved caller can redeem within maximum | `redeemWithinMaxRedeemDoesNotRevert`, 286-298 | **Incomplete coverage:** requires caller = owner, omitting approved callers. Adds a preview-based precondition and shared market bounds. |
| P-14: views never revert on non-overflow inputs | `conversionsNeverRevert`, 304-322 | Captures each revert flag correctly. Numeric bounds select a smaller domain than all non-overflow inputs and do not themselves exclude every overflow or inconsistent state. |
| P-15: caller-independent conversions | `conversionsIndependentOfCaller`, 324-332 | Fixes block number/time and compares calls in the same storage state. No shared setup; scope needs acknowledgment. |
| P-16: conversions cannot create assets | `roundTripDoesNotCreateAssets`, 334-339 | **Faithful to the informal conversion-only statement.** Does not execute deposit/redeem or check any depositor loss. |
| P-17: previews equal conversions while unpaused | `previewsEqualConversionsWhenUnpaused`, 341-346 | Direct translation on non-reverting paths. Does not establish view availability. |
| P-18: allowance consumed; insufficient allowance rejected | `thirdPartyRedeemSpendsAllowance`, 352-370 | Captures the revert flag before later calls and preserves the unlimited-allowance exception. Basic unwrap only; slippage overload omitted. |
| P-19: Deposit/Withdraw events | No CVL rule | Explicitly review-only in the submission. Do not include it in a count of proved properties. |
| P-20: only owner's shares burned, other balances unchanged | `exitOnlyBurnsOwnerShares`, 372-388 | Faithful to that precise share-balance claim for successful redeem/basic unwrap. The broader phrase about other holders' value must not be read as economic isolation. |

P-13 also permits zero shares/zero owner and evaluates `previewUnwrap(totalSupply())` without `@withrevert` before the target call. A reverting preview removes that state from consideration. This does not assume donations away, but it narrows the availability claim and may affect vacuity.

## Similar F0 properties, different formal obligations

Compare with the [original F0 specification](../runs/F0/SpectraWrappedTakara.spec) and its [informal properties](../runs/F0/PROPERTIES.md). Property IDs are local to each run.

| Topic | F0 CVL | F1 CVL | Implication |
|---|---|---|---|
| Round trip | P9 executes `deposit`, then `redeem`, asserts output <= input | P-16 calls `convertToShares`, then `convertToAssets`, asserts output <= input | Not equivalent. F1 cannot expose state-transition effects such as the empty-market windfall seen in F0 P9. A F1 pass would not contradict that F0 failure. |
| Deposit maximum | P11 calls `previewDeposit@withrevert` | P-12 calls `deposit@withrevert` with funding/allowance assumptions | F1 addresses actual acceptance. F0's informal requirement was already wrong; this is improved property selection, not just a syntax fix. |
| Redemption maximum | P12 asserts `previewRedeem(shares) <= getCash()` | P-13 calls `redeem@withrevert` | F1 can expose pause/policy failures, not only liquidity. Its owner-only scope remains incomplete. |
| Redeem preview | P3 checks exact paid amount against preview | P-03 checks paid amount >= preview; P-04 separately matches returned amount | F1 is weaker on preview equality but faithful to its own lower-bound requirement. |
| Allowance | P16 executes successful exits and asserts allowance sufficed and decreased | P-18 explicitly captures reverts and checks both rejection and successful consumption | Both can rule out successful overspending. F1 makes rejection explicit; default revert pruning alone does not make F0's safety assertion wrong. Both omit the slippage unwrap overload. |
| Pausing | P18 includes operations and share transfers | P-07 includes operations, not share transfers | F1 matches its narrower informal statement; it does not prove transfer freezing. |
| Zero shares | P8 asserts positive deposit implies positive shares on successful calls | No counterpart | F1 has lost a bug-catching requirement before translation begins. |

## Shared assumptions and model limits

1. `setup()` wires addresses and constrains time/rate parameters; it does not prove all initialization postconditions or reachability. `boundedMarket()` does not pin the live seeded Takara state or establish all ERC-20 balance/supply invariants. In particular, total supply bounds alone do not bound the underlying balance returned by `getCash()`; the initial exchange rate is unbounded above.
2. F1 executes a custom tToken model with a stored borrow rate; F0 used real delegate source with a rate ghost and nondeterministic policy hooks. Outcomes and runtimes cannot be compared as a pure effect of the README. F1's mock omits real policy and accrual behavior, while retaining direct token transfers and inflated wrapper backing.
3. The authority mock only models immediate permissions. Inspect call resolution before relying on P-09; no low-level-call result has been observed here.
4. `DISPATCHER(true)` uses optimistic dispatch, and the configuration enables optimistic loops with three iterations. A pass must be qualified by those choices; inspect the call-resolution report and whether loop approximations are actually reached. [Methods documentation](https://docs.certora.com/en/latest/docs/cvl/methods.html), [loop documentation](https://docs.certora.com/en/latest/docs/prover/approx/loops.html).
5. Ordinary preview, conversion, and accounting rules can be faithful yet pass on an economically vulnerable wrapper. No existing F1 assertion supplies the missing lower bound on the value a depositor receives.
6. F0 explicitly sets `parametric_contracts` to its wrapper harness; F1 does not. Inspect the instantiated method/contract subrules rather than assuming identical parametric coverage.

Keep all original artifacts unchanged. Any input-domain restriction, extra invariant, mock repair, added overload, or new fair-deposit rule is an evaluator revision with its own recorded outcome, not a corrected original F1 result.
