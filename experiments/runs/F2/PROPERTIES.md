# Properties — SpectraWrappedTakara

Properties the wrapper must satisfy. Each is one plain-language sentence.
"Price" means the USDC value of one whole wrapper share, i.e. `convertToAssets(10 ** decimals())`.
ε = 10 wei of USDC.

## A. Supplied requirements (from the supplied README)

### A.1 Required properties (README "Required properties")

These must hold in every state reachable from a freshly deployed, empty wrapper.

| ID | Property |
|----|----------|
| S1 | The total supply of wrapper shares always equals the sum of all share balances. |
| S2 | No operation lowers the USDC value of one whole share. |
| S3 | While the vault is paused, `deposit`, `redeem`, `wrap` and `unwrap` revert. |
| S4 | Transferring tTokens directly to the wrapper never changes the USDC value of one whole share. |
| S5 | Right after depositing `a` USDC, the shares received are worth at least `a − ε` USDC as reported by `previewRedeem`. |

### A.2 ERC-4626 compliance (README "ERC-4626 compliance")

| ID | Property |
|----|----------|
| S6 | `asset`, `totalAssets`, `convertToShares` and `convertToAssets` never revert. |
| S7 | `convertToShares` and `convertToAssets` return the same result whoever the caller is. |
| S8 | `deposit` reverts when asked for more than `maxDeposit`, and `redeem` reverts when asked for more than `maxRedeem`. |
| S9 | `maxDeposit` and `maxRedeem` return 0 while the vault is paused. |
| S10 | `maxMint` and `maxWithdraw` always return 0, and `mint` and `withdraw` always revert. |
| S11 | `deposit` emits `Deposit` and `redeem` emits `Withdraw`. |
| S12 | A `redeem` called by someone other than the owner lowers the owner's allowance to the caller by the number of shares redeemed. |

### A.3 Rounding and previews (README "Rounding and previews (EIP-4626)")

| ID | Property |
|----|----------|
| S13 | `convertToShares` and `convertToAssets` round down, so converting assets to shares and back never yields more assets than were put in. |
| S14 | `previewDeposit(a)` never returns more shares than `deposit(a, …)` mints in the same transaction. |
| S15 | `deposit` returns exactly the number of shares it mints to the receiver. |
| S16 | `previewRedeem(s)` never returns more assets than `redeem(s, …)` pays in the same transaction. |
| S17 | `redeem` returns exactly the amount of USDC it pays to the receiver. |
| S18 | With no fees, `previewDeposit` equals `convertToShares` and `previewRedeem` equals `convertToAssets` (up to rounding). |

### A.4 Trust assumptions (README "Trust assumptions"; treated as properties to check)

| ID | Property |
|----|----------|
| S19 | Only the AccessManager authority can pause, unpause, set the rewards proxy or trigger reward claims; nobody else has privileged access. |

## B. Inferred properties (not stated in the README; added by the auditor)

Added before the investigation:

| ID | Property |
|----|----------|
| I1 | A `deposit` or `wrap` of a nonzero amount never takes the user's funds while minting zero shares. |
| I2 | `unwrap` by someone other than the owner lowers the owner's allowance to the caller by the number of shares unwrapped (same rule as S12). |
| I3 | Every outstanding share is backed: the wrapper holds at least as many tTokens as `previewUnwrap(totalSupply())` would hand out. |
| I4 | `deposit` and `redeem` leave the wrapper's own USDC balance unchanged; USDC never accumulates in the wrapper. |
| I5 | `maxDeposit` and `maxRedeem` never return more than `deposit` and `redeem` would actually accept (EIP-4626 "MUST NOT be higher than the actual maximum"). |
| I6 | While paused, share transfers revert as well (the documented behaviour of `_update`). |

Added during the investigation:

| ID | Property |
|----|----------|
| I7 | The view-replicated exchange rate (`_currentExchangeRate`) equals the rate Takara actually uses in the same block, so `previewDeposit`/`previewRedeem` match the real `mint`/`redeem`. |
| I8 | A share's tToken backing ratio `(totalVaultShares + 1) / (totalSupply + 1)` can only change through wrapper operations, never through an outside transfer. |
