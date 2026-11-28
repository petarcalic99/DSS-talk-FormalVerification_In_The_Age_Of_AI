/-
Experiment 1 in Verity/Lean: property 4, "a round trip never gains".

Two theorems, both fully proved (`#print axioms` at the end lists only Lean's standard
axioms, no `sorryAx`):
  - wrap_unwrap_no_gain:    wrap then unwrap never returns more tTokens than wrapped;
  - deposit_redeem_no_gain: deposit then redeem never returns more assets than deposited
                            (F0's P9, which timed out 4 x 2 h in Certora).
Both hold for ANY state, ANY decimals offset and ANY market rate.

They are stated over the share-pricing formulas of `takara/src/WrappedTakaraModel.sol`,
copied by hand. Not yet done: the bridge theorem proving that the imported contract
(`Model.lean`) computes these formulas when it does not revert.

These properties hold even in the vulnerable code: they bound what a depositor can GAIN,
while the donation bug makes victims get LESS. They do not detect the bug.

Run inside the Verity checkout with `lake env lean TakaraImport/RoundTrip.lean`.
-/
import Mathlib.Tactic

namespace Takara.Spec

/-- Wrapper state at the tToken level. -/
structure State where
  S : Nat  -- share supply (`totalSupply`)
  V : Nat  -- wrapper's tToken balance (`totalVaultShares()`)

/-- shares = floor(t * (S + 10^k) / (V + 1)), as `previewWrap` in WrappedTakaraModel.sol -/
def previewWrap (k : Nat) (st : State) (t : Nat) : Nat :=
  t * (st.S + 10 ^ k) / (st.V + 1)

/-- tTokens = floor(s * (V + 1) / (S + 10^k)), as `previewUnwrap` -/
def previewUnwrap (k : Nat) (st : State) (s : Nat) : Nat :=
  s * (st.V + 1) / (st.S + 10 ^ k)

/-- `wrap(t)`: new state, and the shares minted. -/
def wrap (k : Nat) (st : State) (t : Nat) : State × Nat :=
  let s := previewWrap k st t
  (⟨st.S + s, st.V + t⟩, s)

/-- `unwrap(s)`: new state, and the tTokens paid out. -/
def unwrap (k : Nat) (st : State) (s : Nat) : State × Nat :=
  let t := previewUnwrap k st s
  (⟨st.S - s, st.V - t⟩, t)

/-- Property 4: wrap `t` tTokens, unwrap the shares you got: you never get more than `t` back.
For ANY starting state and ANY offset `k`. -/
theorem wrap_unwrap_no_gain (k : Nat) (st : State) (t : Nat) :
    (unwrap k (wrap k st t).1 (wrap k st t).2).2 ≤ t := by
  -- Step 1: unfold the definitions, leaving plain arithmetic.
  simp only [unwrap, wrap, previewUnwrap, previewWrap]
  -- Step 2: name the shares the wrap minted.
  set s := t * (st.S + 10 ^ k) / (st.V + 1) with hs
  -- Step 3: the wrap rounds down, so s * (V + 1) ≤ t * (S + 10^k).
  have hwrap : s * (st.V + 1) ≤ t * (st.S + 10 ^ k) := Nat.div_mul_le_self _ _
  -- Step 4: x / y ≤ t follows from x ≤ y * t. The goal loses its division.
  apply Nat.div_le_of_le_mul
  -- Step 5: the goal is hwrap with s * t added to both sides.
  nlinarith [hwrap]

/-- Deposit `a` assets then redeem the shares, at market rate `r` (1e18-scaled), as in
`deposit` / `redeem` of WrappedTakaraModel.sol:
  the market mints m = floor(a * 1e18 / r) tTokens, and shares are priced on m (`previewDeposit`);
  redeem pays tt = previewUnwrap(shares) tTokens, which the market turns into floor(tt * r / 1e18). -/
def depositRedeem (k r : Nat) (st : State) (a : Nat) : Nat :=
  let m := a * 10 ^ 18 / r
  let w := wrap k st m
  let tt := (unwrap k w.1 w.2).2
  tt * r / 10 ^ 18

/-- Property 4, deposit level (F0's P9, which timed out 4 x 2 h in Certora):
deposit then redeem never returns more assets than deposited.
For ANY state, ANY offset `k` and ANY rate `r`. -/
theorem deposit_redeem_no_gain (k r : Nat) (st : State) (a : Nat) :
    depositRedeem k r st a ≤ a := by
  -- Step 1: unfold depositRedeem only. wrap/unwrap stay folded so the first theorem still applies.
  simp only [depositRedeem]
  -- Step 2: name the tTokens the market mints.
  set m := a * 10 ^ 18 / r with hm
  -- Step 3: the wrapper's round trip returns at most m tTokens (the theorem proved above).
  have htt : (unwrap k (wrap k st m).1 (wrap k st m).2).2 ≤ m := wrap_unwrap_no_gain k st m
  -- Step 4: the market's mint rounds down: m * r ≤ a * 1e18.
  have hmint : m * r ≤ a * 10 ^ 18 := Nat.div_mul_le_self _ _
  -- Step 5: chain the two roundings.
  calc _ ≤ m * r / 10 ^ 18 := by gcongr          -- fewer tTokens, fewer assets
    _ ≤ a := by
      apply Nat.div_le_of_le_mul                 -- remove the division
      linarith [hmint]

end Takara.Spec
#print axioms Takara.Spec.wrap_unwrap_no_gain
#print axioms Takara.Spec.deposit_redeem_no_gain
