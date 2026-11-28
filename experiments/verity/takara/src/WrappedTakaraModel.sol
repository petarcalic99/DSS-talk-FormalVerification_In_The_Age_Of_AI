// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * MODEL CONTRACT FOR LEAN PROOFS, NOT THE AUDITED CODE.
 *
 * Same vulnerable pricing as SimplifiedWrappedTakara.sol: shares are priced from the
 * wrapper's RAW tToken balance, so a direct transfer ("donation") moves the price.
 *
 * Simplified so that Verity's Solidity importer accepts every function:
 *   - The tToken ledger, the underlying ledger and the market live inside this
 *     contract, so there are no external calls (no re-entrancy question, no assumption
 *     about how an outside tToken behaves).
 *   - Math.mulDiv is replaced by plain checked arithmetic. It differs only when an
 *     intermediate product exceeds 2^256 (this reverts), which theorems exclude by bounds.
 *   - The market rate is fixed at deployment (the simplified contract accrues no interest).
 *     mint rounds floor(a * 1e18 / rate) and redeem floor(t * rate / 1e18), as Compound does.
 *   - Callers act for themselves (no receiver argument).
 */
contract WrappedTakaraModel {
    uint256 public constant SCALE = 1e18;

    /// 10 ** decimalsOffset: 1 in the vulnerable code, 1e6 with OpenZeppelin's mitigation.
    uint256 public immutable virtualShares;
    /// Market exchange rate: underlying per tToken, 1e18-scaled.
    uint256 public immutable rate;

    // Wrapper shares.
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    // The tToken ledger (was the external tToken contract).
    mapping(address => uint256) public tBalance;

    // The underlying (e.g. USDC) ledger (was the external asset contract).
    mapping(address => uint256) public assetBalance;

    constructor(uint256 _virtualShares, uint256 _rate) {
        virtualShares = _virtualShares;
        rate = _rate;
    }

    /*//////////////////////////////////////////////////////////////
                    PRICING: UNCHANGED, WHERE THE BUG LIVES
    //////////////////////////////////////////////////////////////*/

    /// VULNERABLE: the raw balance, so a donation moves the price.
    function totalVaultShares() public view returns (uint256) {
        return tBalance[address(this)];
    }

    /// shares = floor(t * (S + 10^offset) / (V + 1))
    function previewWrap(uint256 tTokens) public view returns (uint256) {
        return tTokens * (totalSupply + virtualShares) / (totalVaultShares() + 1);
    }

    /// tTokens = floor(s * (V + 1) / (S + 10^offset))
    function previewUnwrap(uint256 shares) public view returns (uint256) {
        return shares * (totalVaultShares() + 1) / (totalSupply + virtualShares);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return previewWrap(assets * SCALE / rate);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return previewUnwrap(shares) * rate / SCALE;
    }

    /*//////////////////////////////////////////////////////////////
                    tTOKEN LAYER
    //////////////////////////////////////////////////////////////*/

    function wrap(uint256 tTokens) external returns (uint256 shares) {
        shares = previewWrap(tTokens);
        tBalance[msg.sender] -= tTokens;
        tBalance[address(this)] += tTokens;
        balanceOf[msg.sender] += shares;
        totalSupply += shares;
    }

    function unwrap(uint256 shares) external returns (uint256 tTokens) {
        tTokens = previewUnwrap(shares);
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        tBalance[address(this)] -= tTokens;
        tBalance[msg.sender] += tTokens;
    }

    /// The attack's direct transfer: backing grows, no shares are minted.
    function donate(uint256 tTokens) external {
        tBalance[msg.sender] -= tTokens;
        tBalance[address(this)] += tTokens;
    }

    /*//////////////////////////////////////////////////////////////
                    ASSET LAYER (market inside)
    //////////////////////////////////////////////////////////////*/

    /// No zero-share check, as in the original.
    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = previewDeposit(assets);
        assetBalance[msg.sender] -= assets;
        tBalance[address(this)] += assets * SCALE / rate; // market mint
        balanceOf[msg.sender] += shares;
        totalSupply += shares;
    }

    function redeem(uint256 shares) external returns (uint256 assets) {
        uint256 tTokens = previewUnwrap(shares);
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        tBalance[address(this)] -= tTokens;
        assets = tTokens * rate / SCALE; // market redeem
        assetBalance[msg.sender] += assets;
    }
}
