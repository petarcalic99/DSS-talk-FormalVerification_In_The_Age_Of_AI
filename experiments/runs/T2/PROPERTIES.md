# Properties — SpectraWrappedTakara

Cell ID: T2 · Input version: T2-pilot-amendment-2026-10-27-v2 · Template commit: d492bed455059b8f650cfab30601a8e2207d8ae0

Notation: "one whole share" = `10 ** wrapper.decimals()` wrapper shares; its "USDC value" is
`convertToAssets(10 ** decimals())`. ε = 10 wei of USDC.

## A. Supplied requirements (from the README)

### Required properties

- **R1 Supply consistency:** The total supply of wrapper shares always equals the sum of all holders' balances.
- **R2 Price never decreases:** No operation lowers the USDC value of one whole share.
- **R3 Paused means closed:** While the vault is paused, `deposit`, `redeem`, `wrap` and `unwrap` all revert.
- **R4 Donations do not move the price:** Transferring tTokens directly to the wrapper never changes the USDC value of one whole share.
- **R5 Fair deposit:** Right after depositing `a` USDC, the shares received are worth at least `a − ε` USDC according to `previewRedeem`.

### ERC-4626 compliance

- **E1 Non-reverting views:** `asset`, `totalAssets`, `convertToShares` and `convertToAssets` never revert.
- **E2 Caller independence:** `convertToShares` and `convertToAssets` return the same value whoever calls them.
- **E3 maxDeposit respected:** Any `deposit` of at most `maxDeposit(receiver)` assets (by a funded, approving caller) succeeds.
- **E4 maxRedeem respected:** Any `redeem` of at most `maxRedeem(owner)` shares succeeds.
- **E5 Paused limits:** While paused, `maxDeposit` and `maxRedeem` return 0.
- **E6 Unsupported limits:** `maxMint` and `maxWithdraw` always return 0.
- **E7 Events:** `deposit` emits `Deposit` and `redeem` emits `Withdraw` with the actual amounts.
- **E8 Delegated redeem:** A `redeem` by someone other than the owner spends the owner's share allowance (and reverts without one).

### Rounding and previews

- **E9 Conversions round down:** `convertToShares(a)` and `convertToAssets(s)` never exceed the exact (unrounded) conversion at the vault's current rate.
- **E10 previewDeposit is a lower bound:** `previewDeposit(a)` is no more than the shares `deposit(a, …)` mints in the same transaction.
- **E11 deposit returns the truth:** `deposit` returns exactly the number of shares it minted.
- **E12 previewRedeem is a lower bound:** `previewRedeem(s)` is no more than the assets `redeem(s, …)` pays in the same transaction.
- **E13 redeem returns the truth:** `redeem` returns exactly the amount of USDC the receiver got.
- **E14 Preview equals conversion:** With no fees, `previewDeposit` equals `convertToShares` and `previewRedeem` equals `convertToAssets`, up to rounding.

## B. Inferred properties (not stated in the README)

Added before testing:

- **I1 Solvency:** The USDC the wrapper's shares claim (`totalAssets`) never exceeds what its tToken balance can be redeemed for.
- **I2 No round-trip profit (deposit/redeem):** Depositing `a` USDC and redeeming all received shares at once returns at most `a`.
- **I3 No round-trip profit (wrap/unwrap):** Wrapping `t` tTokens and unwrapping all received shares at once returns at most `t` tTokens.
- **I4 No stranded USDC:** After any deposit or redeem the wrapper holds no loose USDC (everything is either in Takara or paid out).
- **I5 Access control:** Only the AccessManager authority can pause, unpause, set the rewards proxy or claim rewards.
- **I6 Initialization lock:** The implementation and the proxy cannot be (re-)initialized by anyone.

Added during the investigation:

- **I7 Previews track interest accrual:** When time has passed and Takara has outstanding borrows, `previewDeposit`/`previewRedeem` still match what `deposit`/`redeem` actually mint/pay in that block (the wrapper's replicated `accrueInterest` math is exact).
- **I8 maxRedeem reflects Takara liquidity:** `maxRedeem` does not promise a redemption that Takara cannot pay because its cash is lent out (EIP-4626 says max functions must account for global limits).
- **I9 Bounded deposit limit:** `maxDeposit` does not exceed the largest amount that `deposit` can process without overflowing (EIP-4626 says it must return an amount that would not revert).
- **I10 Inflation resistance:** A first depositor who donates tTokens cannot cause a later depositor's deposit to round to (almost) zero shares.
