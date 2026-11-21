# Properties — SpectraWrappedTakara / Spectra4626Wrapper

Scope: `src/utils/Spectra4626Wrapper.sol` and `src/takara/SpectraWrappedTakara.sol`, wrapping a Takara
(Compound v2 fork) tToken whose underlying is a standard ERC-20.

Notation: *assets* = underlying (e.g. USDC), *tTokens* = Takara vault shares, *shares* = wrapper shares.

## Exchange-rate parity with Takara

- **P1** The wrapper's view exchange rate equals the rate the tToken stores after `accrueInterest()` in the same block.
- **P2** `deposit(assets)` causes the wrapper to receive exactly the number of tTokens its preview math predicts for `assets`.
- **P3** `redeem(shares)` sends the receiver exactly `previewRedeem(shares)` assets.

## ERC-4626 accounting

- **P4** `deposit` mints exactly the returned number of shares to the receiver, and only to the receiver.
- **P5** `deposit` leaves the wrapper's own underlying balance unchanged (every pulled asset is supplied to Takara).
- **P6** `redeem` burns exactly `shares` from the owner and reduces total supply by exactly `shares`.
- **P7** The value returned by `redeem` equals the amount of underlying the receiver actually received.
- **P8** A deposit that would mint zero shares reverts instead of taking the depositor's assets.
- **P9** A deposit followed immediately by a redeem of the minted shares never returns more assets than were deposited.
- **P10** No deposit, redeem, wrap or unwrap decreases the tTokens backing each wrapper share (the `(V+1)/(S+1)` ratio).

## ERC-4626 limits

- **P11** Any deposit amount not above `maxDeposit` can be previewed without reverting.
- **P12** Redeeming any amount not above `maxRedeem(owner)` does not fail because Takara lacks cash.
- **P13** `mint`, `withdraw`, `previewMint` and `previewWithdraw` always revert, and `maxMint`/`maxWithdraw` are always zero.

## Wrap / unwrap

- **P14** `wrap(v)` moves exactly `v` tTokens into the wrapper and mints exactly `previewWrap(v)` shares to the receiver.
- **P15** `unwrap(s)` burns exactly `s` shares from the owner and sends exactly `previewUnwrap(s)` tTokens to the receiver.

## Authorization

- **P16** A caller other than the owner can redeem or unwrap only up to their allowance, and that allowance shrinks by the shares spent.
- **P17** `pause`, `unpause`, `setRewardsProxy` and `claimRewards` revert unless the AccessManager authorizes the caller.

## Pause

- **P18** While paused, `deposit`, `redeem`, `wrap`, `unwrap` and share transfers all revert.
- **P19** While paused, `maxDeposit` and `maxRedeem` return zero.
