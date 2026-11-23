/*
 * Property: a transaction is queued through a module's signature only if that
 * module really approved exactly that transaction.
 *
 * The module is a contract wallet (ModuleSigner). Its `approved` mapping is the
 * ground truth. For hashes it did not approve, the prover chooses freely how its
 * isValidSignature behaves (return or revert, any data). We never tell the
 * prover what the attack looks like: it has to find it.
 */

using ModuleSigner as module;

methods {
    function queueNonce() external returns (uint256) envfree;
    function isModuleEnabled(address) external returns (bool) envfree;
    function hashTypedData(bytes32) external returns (bytes32); // not envfree: it reads block.chainid
    function moduleTxStructHash(address, uint256, bytes, uint256) external returns (bytes32) envfree;
    function module.approved(bytes32) external returns (bool) envfree;

    function signerModel() external returns (address) envfree;
}

rule signedQueueRequiresModuleApproval(env e, address to, uint256 value, bytes data, uint256 salt, bytes tail) {
    // The module is enabled.
    require isModuleEnabled(module);
    // The harness sends every contract signature to the model wallet.
    require signerModel() == module;
    // Stay on the contract-signature path: a 65-byte signature is first tried
    // as an EOA signature with ecrecover.
    require tail.length != 45;

    bytes32 digest = hashTypedData(e, moduleTxStructHash(to, value, data, salt));
    bool moduleApproved = module.approved(digest);
    uint256 queuedBefore = queueNonce();

    relayContractSignature(e, to, value, data, salt, tail);

    assert queueNonce() != queuedBefore => moduleApproved,
        "a transaction was queued that the module never approved";
}
