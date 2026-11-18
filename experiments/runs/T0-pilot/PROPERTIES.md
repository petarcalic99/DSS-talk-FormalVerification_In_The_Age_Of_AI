# Properties — SpectraWrappedTakara

`SpectraWrappedTakara` is an ERC-4626 wrapper. Its asset is the Takara market's underlying (USDC) and its shares are backed by Takara tTokens. Users can enter and leave through ERC-4626 `deposit`/`redeem` (in underlying) or through `wrap`/`unwrap` (in tTokens). The properties below are what this project must satisfy.

## Accounting and pricing

- **P1 — Exact deposit preview:** `previewDeposit(assets)` equals the number of shares that `deposit(assets)` mints in the same block, including when interest has built up in the Takara market since its last update.
- **P2 — Exact redeem preview:** `previewRedeem(shares)` equals the underlying amount that `redeem(shares)` sends to the receiver in the same block, including when interest has built up since the market's last update.
- **P3 — No profit from a deposit round trip:** depositing underlying and then immediately redeeming all the shares received never returns more underlying than was deposited.
- **P4 — No profit from a wrap round trip:** wrapping tTokens and then immediately unwrapping all the shares received never returns more tTokens than were wrapped.
- **P5 — Solvency:** the tTokens owed to all outstanding shares never exceed the tTokens the wrapper holds.
- **P6 — Honest totalAssets:** `totalAssets()` never exceeds the underlying value of the tTokens the wrapper holds.
- **P7 — Isolation between holders:** one user's deposit, redeem, wrap or unwrap never lowers the underlying value that another holder's shares can be redeemed for.
- **P8 — No stuck or stolen underlying:** deposits and redeems leave the wrapper's own underlying balance unchanged. Nothing is stranded in the wrapper, and a redeem never pays out underlying that the wrapper held for some other reason.
- **P9 — Donation (inflation) attack:** a first depositor cannot profit by donating tTokens to the wrapper at the expense of a later depositor.

## ERC-4626 limits

- **P10 — Unsupported entry points:** `mint` and `withdraw` always revert, and `maxMint` and `maxWithdraw` always return 0.
- **P11 — Honest maxDeposit:** any amount up to `maxDeposit(receiver)` can be deposited, provided the caller holds and has approved it. In particular, `maxDeposit` is 0 whenever the deposit would revert.
- **P12 — Honest maxRedeem:** redeeming `maxRedeem(owner)` shares does not revert.

## Pause, access control and allowances

- **P13 — Pause:** while paused, `deposit`, `redeem`, `wrap`, `unwrap` and share transfers revert, and `maxDeposit`/`maxRedeem` return 0. After unpausing, all of them work again.
- **P14 — Access control:** only accounts the AccessManager authorizes can call `pause`, `unpause`, `setRewardsProxy` and `claimRewards`.
- **P15 — Allowances:** a third party can `redeem` or `unwrap` someone else's shares only within the allowance it was granted, and doing so uses up that allowance.

## Setup

- **P16 — One-time initialization:** the proxy cannot be initialized a second time, and the implementation contract cannot be initialized at all.
- **P17 — Metadata:** `asset()` is the tToken's underlying, `vaultShare()` is the tToken, and `decimals()` equals the tToken's decimals.
