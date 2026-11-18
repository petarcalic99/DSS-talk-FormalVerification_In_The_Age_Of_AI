# P8 follow-up: does the attacker always lose money?

This document re-examines one claim in `P8_FINDING.md` (left unchanged):

> "The attacker loses money doing it, so this is griefing, not theft." / "The victim always loses about twice what the attacker spends."

## Verdict

**The claim is false as stated.** The earlier evidence covered one sequence only: one donation, one victim, then the attacker exits immediately. That sequence does always lose for the attacker. But it does not justify "always":

- **Two or more victims:** if the attacker keeps their share while two or more victims each mint 0 shares, the attacker **profits**. The attack is then theft, not just griefing.
- **Break-even with 1 share:** the attacker profits once the victims' zero-share deposits add up to more than the donation.
- **Break-even with `s` shares:** roughly when they add up to more than `donation / s`.

Prover confirmation on the real contracts: _see "Prover check" below._

A second earlier claim is also wrong: "revert on `shares == 0`" does **not** by itself stop a profitable attack. Rounding on deposits that get 1–2 shares still transfers value to the attacker (see "Mitigations tested").

**Corrected statement:**
- With a single zero-share victim, the attacker cannot profit beyond rounding dust.
- With two or more zero-share victims before the attacker exits, the attacker can profit, taking up to `s/(s+1)` of every victim's deposit.

## Why the original evidence did not justify "always"

The original test (`p8_scenarios.py`, case B) checked exactly one order of transactions:

1. attacker deposits;
2. attacker donates;
3. **one** victim deposits;
4. attacker redeems.

It never:
- let several victims deposit before the attacker exits;
- varied the attacker's share count;
- let the attacker re-enter after exiting.

Its reasoning — "the attacker owns half the pool, so they recover half the donation plus half the victim's deposit" — holds per victim. It misses that each zero-share victim **raises the zero-share threshold** for the next one, because the wrapper's tTokens grow while its shares don't. So losses pile up for later victims, and the attacker's half-claim grows without limit.

## Method

**The model:** `scratchpad/tools/p8_followup.py`. It is an exact integer model of `SpectraWrappedTakara` + the Takara tToken, covering:
- deposit, redeem, wrap, unwrap;
- direct tToken donation;
- Takara mint and redeem.

All of it runs at the live tUSDC values from `test/utils/LocalDeployment.sol`, in the same block with no interest.

**Accounting:** every participant's position is valued in USDC as:

```
USDC held + tTokens held × rate + wrapper shares × (V+1)/(S+1) × rate
```

Each participant's net is that final value minus the USDC they brought in. Two more participants are tracked:
- **Takara LPs:** the existing tToken holders;
- **"stranded":** tTokens in the wrapper that no share holder can claim.

**Checks on the model:**
- **Conservation:** across 3,000 random sequences, the sum of all nets is 0 to within 12 micro-USDC (`p8_trace.py`).
- **Matches the contracts:** the prover rules C1 and C2 (verified earlier) show the contracts' `deposit` and `redeem` compute exactly the formulas the model uses.

## Counterexample: two victims (step-by-step trace)

D = 1,000 USDC. All values are in USDC. Net = value now − USDC brought in.

| Step | Action | Attacker net | Victim 0 net | Victim 1 net | Wrapper S | Wrapper V (tTokens) |
|---|---|---|---|---|---|---|
| 0 | Start: attacker holds 1,000.000002 USDC | 0 | 0 | 0 | 0 | 0 |
| 1 | Attacker `deposit(2 wei)` → 1 share | −0.000001 | 0 | 0 | 1 | 1 |
| 2 | Attacker mints 958,330,167 tTokens and transfers them to the wrapper | −500.000002 | 0 | 0 | 1 | 958,330,168 |
| 3 | Victim 0 `deposit(490.00)` → **0 shares** | −255.000002 | −490.00 | 0 | 1 | 1,427,911,949 |
| 4 | Victim 1 `deposit(730.10)` → **0 shares** | **+110.049998** | −490.00 | −730.10 | 1 | 2,127,588,803 |
| 5 | Attacker `redeem(1 share)` → 1,110.05 USDC | **+110.049998** | −490.00 | −730.10 | 0 | 1,063,794,401 |

**Final:**
- attacker **+110.05**;
- victims **−1,220.10**;
- stranded in the wrapper **+1,110.05**;
- Takara LPs +0.000002.

The total is 0.

## Other sequences tested

### Holding while k victims each get 0 shares (D = 1,000 USDC, 1 attacker share)

| k victims | Attacker net | Victims' total loss | Stranded |
|---|---|---|---|
| 1 | −255.00 | −490.00 | 745.00 |
| 2 | **+110.05** | −1,220.10 | 1,110.05 |
| 3 | **+653.97** | −2,307.95 | 1,653.97 |
| 4 | **+1,464.42** | −3,928.84 | 2,464.42 |
| 6 | **+4,471.26** | −9,942.53 | 5,471.26 |
| 10 | **+25,967.00** | −52,934.01 | 26,967.00 |

### Break-even (1 attacker share, D = 1,000 USDC)

The victims' total is split across as many transactions as needed, each staying under the zero-share threshold.

| Victims' total | Attacker net |
|---|---|
| 900 | −50.00 |
| 990 | −5.00 |
| 1,000 | 0.00 |
| 1,001 | +0.50 |
| 1,100 | +50.00 |
| 2,000 | +500.00 |

So the attacker's net is about `(Σ victims − D) / 2`.

### Attacker starting with more shares (4 victims, each filling the zero-share threshold)

| Attacker shares | Victims' loss | Attacker net |
|---|---|---|
| 1 | 4,062.50 | +1,531.25 |
| 2 | 2,160.49 | +1,107.00 |
| 4 | 1,073.60 | +658.88 |
| 10 | 416.30 | +287.54 |
| 96 | 41.88 | +31.14 |

With `s` shares the attacker loses only `D/(s+1)` of the donation, but each victim's zero-share window shrinks to about `D/(s+1)`. Profit needs roughly `Σ victims > D/s`, which always takes at least two victims.

### Sequences that did not make the attacker profit

| Sequence | Result |
|---|---|
| One victim, attacker exits (the original) | Attacker −250 (D = 1,000), −25,000 (D = 100,000) |
| Attacker exits, then re-deposits 1 / 1,000 / 1,000,000 USDC to collect the stranded value | Attacker −251.00 / −375.00 / −250.19. The stranded value can't be recovered, because the virtual share (`+1`) takes it. |
| A victim lands just above the threshold and gets 1 share | That victim breaks even (≈0) and dilutes the attacker, whose net is −250 |
| No donation at all (random, 20,000 sequences) | 0 profitable sequences |

### Random search

- **Space searched:** 20,000 random sequences from the live state. The attacker makes a first deposit (1 wei to 1 USDC), then donates (1e3 to 1e11 micro-USDC). After that come 1–12 random steps:
  - victim deposits (below, near or above the threshold, or random);
  - partial attacker redeems;
  - more donations;
  - more attacker deposits.
- **Result:** the attacker ended in profit in **1,969 sequences (9.8%)**.
- **Best case:** attacker **+188,191.08 USDC** after 10 victim deposits, 8 of which got 0 shares. One victim who got 1 share gained +6,554; the others lost a total of 482,936.

## Single-victim bound (why the original sequence always loses)

Take an attacker holding `s` shares out of `S = s`, after donating so the wrapper holds `V` tTokens, all of them supplied by the attacker.

- A zero-share victim must mint `m < (V+1)/(s+1)` tTokens.
- When the attacker exits, they receive `floor(s·(V+m+1)/(s+1))` tTokens.
- That is less than `s·(V+1)·(s+2)/(s+1)²`, which is at most `V+1`, because `s(s+2) < (s+1)²`.

So with one victim, the attacker gets back at most about what they put in: no profit beyond 1 tToken of rounding. This hand derivation holds for any `s`, and the simulation agrees with it, but it has not been checked on the prover.

## Prover check

The rule `P8d_attackerProfitTwoVictimsWitness` asks the prover for a profitable two-victim sequence on the real contracts. It runs these steps on a new wrapper over a live Takara market, all in the same block:

1. attacker `deposit`;
2. attacker mints tTokens on Takara;
3. attacker transfers them to the wrapper;
4. victim 1 `deposit`;
5. victim 2 `deposit`;
6. attacker `redeem`.

It then asks for both victims to have 0 shares and the attacker to end with more USDC.

**Result: TIMEOUT.** The prover found no example within its time limit, and proved nothing either. Report: [Certora job link removed]

The cause is the same as the earlier P9 timeouts: six state-changing calls through Takara's large-number arithmetic are too much for the solvers. **So the counterexample in this document is not prover-confirmed on the real contracts.** It rests on:
- the exact-maths model;
- the verified rules C1 and C2, which show the contracts' `deposit` and `redeem` compute the model's formulas.

A cheaper check, not run: a pure-maths version that applies the C1/C2 formulas five times. The prover handles that kind of rule in minutes.

## Limits of this search

- **Same block only.** Interest accrual between transactions isn't modelled. It raises the value of every share equally, so it shouldn't change who gains and who loses, but this wasn't tested.
- **No front-running or ordering costs.** The model assumes the attacker gets in first on an empty wrapper and that the victims' deposits land before the attacker exits. Gas and MEV costs are ignored.
- **Victims don't protect themselves.** They are assumed to deposit without checking `previewDeposit`, and without a minimum-shares check. Whether Spectra's router or the PT contracts check that a deposit mints at least some shares was **not** examined. That decides how realistic multi-victim losses are.
- **Wrapper only.** Spectra PT/YT contracts and integrations weren't modelled. Takara's comptroller is assumed to allow every mint and redeem. Borrows and reserves are fixed.
- **Bounded search.** The random search is sampling, not exhaustive. The counterexamples above are concrete. "No profit" results (one victim, re-entry, no donation) rest on the bounded search plus the hand bound, not a proof.

## Impact on the original finding

- **Severity:** the "griefing, not theft" framing in `P8_FINDING.md` understates the issue. Once a wrapper's backing is inflated, deposits by several unprotected users can be stolen, not only destroyed. That argues for **Medium** rather than Low–Medium.
- **Recommended fix:** this needs correcting too. **Reverting on `shares == 0` is not enough on its own.** Victims who receive 1–2 shares when they "deserve" 1.9 lose the rounded-off part to the attacker, so the attack still pays.

## Mitigations tested against the same random attacker

20,000 random sequences per configuration, same seed. Each sequence: an attacker first deposit (2 wei to 1 USDC), a donation of up to 100,000 USDC, and 1–12 victim deposits, some landing just above the zero-share threshold. Model: `scratchpad/tools/p8_mitigations.py`.

| Configuration | Attacker profitable | Best attacker net | Victims' total loss (all sequences) |
|---|---|---|---|
| Current code (higher than the 1,969 in "Random search" because more victims here land near the threshold) | 7,743 / 20,000 | +456,016.89 | 329,088,592 |
| Revert on 0 shares only | **2,902 / 20,000** | +26,496.00 | 108,799,350 |
| `_decimalsOffset() = 6` | 0 / 20,000 | 0 | 278 |
| `_decimalsOffset() = 6` + revert on 0 shares | 0 / 20,000 | 0 | 127 |
| Seed 1 USDC at deployment (shares burned) | 0 / 20,000 | 0 | 1,421 |
| Seed 1 USDC + revert on 0 shares | 0 / 20,000 | 0 | 655 |

A separate run of the revert-only fix (`p8_withfix.py`, different seed) found the attacker profitable in 2,881 / 20,000, best **+34,680.40**: 11 victims got 1–5 shares each, and 3 deposits reverted.

**Revised recommendation:**
1. Set `_decimalsOffset()` to 6, or seed every new wrapper with a deposit whose shares are burned. In this search, either one removed attacker profit.
2. Also revert on `shares == 0`, so the remaining dust and rounding losses fail loudly instead of silently.
3. Optionally, add a `deposit` overload with a minimum-shares argument, so integrators can bound their rounding loss.

The "0 profitable" results are sampled within the ranges above (donations up to 100,000 USDC, up to 12 victims). They are evidence, not a proof that the mitigations are sufficient.
