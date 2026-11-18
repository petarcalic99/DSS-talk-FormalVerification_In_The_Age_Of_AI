# Properties — Spectra Wrapped Takara

Properties this project must satisfy, one plain-language sentence each. They were written before any
test. **Source** says where each comes from: a section of the supplied README, or **Inferred** when
it is a property I inferred that the README does not state.

"Takara" means the tToken market and its comptroller. "Shares" means wrapper shares. "Same
transaction" means nothing else happens between the preview and the operation.

## Core operations

| ID | Property | Source |
|----|----------|--------|
| P1 | `deposit(assets, receiver)` takes exactly `assets` USDC from the caller, supplies all of it to Takara (the wrapper's tToken balance goes up by the tTokens minted, and no USDC stays in the wrapper), and mints the returned number of shares to `receiver`. | README "What it does" |
| P2 | `redeem(shares, receiver, owner)` burns exactly `shares` from `owner`, redeems the matching tTokens, and sends `receiver` exactly the USDC amount it returns. | README "What it does", "Rounding and previews" |
| P3 | `wrap(vaultShares, receiver)` takes exactly `vaultShares` tTokens from the caller and mints the returned shares to `receiver`; `unwrap(shares, receiver, owner)` burns exactly `shares` from `owner` and sends `receiver` exactly the returned number of tTokens. | README "What it does" |
| P4 | `mint`, `withdraw`, `previewMint` and `previewWithdraw` always revert. | README "What it does" |

## Access control and pausing

| ID | Property | Source |
|----|----------|--------|
| P5 | Only the AccessManager authority can pause, unpause or set the rewards proxy; any other account is rejected. | README "Trust assumptions" |
| P6 | While paused, `deposit`, `redeem`, `wrap` and `unwrap` all revert, whatever the amount. | README "Intended behaviour" |

## Previews

| ID | Property | Source |
|----|----------|--------|
| P7 | `previewDeposit(assets)` returns exactly the shares `deposit(assets, …)` mints in the same transaction, including when Takara has interest to accrue. | README "Intended behaviour", "Rounding and previews" |
| P8 | `previewRedeem(shares)` returns exactly the USDC `redeem(shares, …)` pays in the same transaction, including when Takara has interest to accrue. | README "Intended behaviour", "Rounding and previews" |
| P9 | `previewWrap` and `previewUnwrap` return exactly what `wrap` and `unwrap` return in the same transaction. | README "Intended behaviour" |

## ERC-4626 compliance

| ID | Property | Source |
|----|----------|--------|
| P10 | `asset`, `totalAssets`, `convertToShares` and `convertToAssets` never revert, including while paused. | README "ERC-4626 compliance" |
| P11 | `convertToShares` and `convertToAssets` return the same value whoever calls them. | README "ERC-4626 compliance" |
| P12 | Any `deposit` of an amount up to `maxDeposit(receiver)` succeeds (for a caller holding and approving the USDC), and `maxDeposit` is 0 while paused. | README "ERC-4626 compliance" |
| P13 | Any `redeem` of up to `maxRedeem(owner)` shares succeeds, and `maxRedeem` is 0 while paused. | README "ERC-4626 compliance" |
| P14 | `maxMint` and `maxWithdraw` always return 0. | README "ERC-4626 compliance" |
| P15 | `deposit` emits `Deposit(caller, receiver, assets, shares)` and `redeem` emits `Withdraw(caller, receiver, owner, assets, shares)`, with the amounts actually moved. | README "ERC-4626 compliance" |
| P16 | A `redeem` by someone other than the owner spends exactly `shares` of the owner's allowance, and reverts without enough allowance. | README "ERC-4626 compliance" |
| P17 | `convertToShares` and `convertToAssets` round down: they never return more than the exact value at the current exchange rates. | README "Rounding and previews" |
| P18 | `previewDeposit` equals `convertToShares` and `previewRedeem` equals `convertToAssets`. | README "Rounding and previews" |

## Inferred safety properties (not stated in the README)

| ID | Property | Source |
|----|----------|--------|
| P19 | The wrapper always holds enough tTokens to unwrap every outstanding share at the `previewUnwrap` rate. | Inferred |
| P20 | A user can't make a profit by depositing then redeeming straight away, or by wrapping then unwrapping. | Inferred |
| P21 | Another user's direct tToken donation to the wrapper can't make a non-dust deposit mint zero shares (no first-depositor inflation loss). | Inferred |
| P22 | `deposit` never takes a positive amount of USDC while minting zero shares, and `redeem` never burns a positive number of shares while paying zero USDC. | Inferred |
| P23 | The proxy can't be initialised a second time, and the implementation can't be initialised at all. | Inferred |
