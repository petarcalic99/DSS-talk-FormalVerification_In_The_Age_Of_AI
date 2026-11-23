// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ModuleSigner
/// @notice Model of an enabled contract module (a smart wallet), for the prover.
///
/// `approved` is the ground truth: the hashes this module really approved
/// (for a real wallet: its owners' keys signed them).
///
/// For any other hash, the prover chooses how its validation code answers:
/// return normally with any value, or revert with any 32 bytes. These choices
/// are initial storage, so they are unconstrained. This is the threat model,
/// not the bug: nothing here singles out a particular revert.
///
/// The one constraint comes from the ERC-1271 definition: a normal return of
/// the magic value IS an approval. So for a hash it did not approve, a normal
/// return never carries the magic value.
///
/// Simplification: revert data is always 32 bytes. With a prover-chosen
/// length, the prover lost track of the revert data and missed the bug.
contract ModuleSigner {
    bytes4 internal constant MAGIC = 0x1626ba7e;

    mapping(bytes32 => bool) public approved;

    // How the module answers for hashes it did not approve, chosen by the prover.
    bool public answerByRevert;
    bytes4 public returnValue;
    bytes32 public revertWord;

    function isValidSignature(bytes32 hash, bytes calldata) external view returns (bytes4) {
        if (approved[hash]) return MAGIC;

        if (answerByRevert) {
            bytes32 word = revertWord;
            assembly {
                mstore(0, word)
                revert(0, 32)
            }
        }

        return returnValue == MAGIC ? bytes4(0) : returnValue;
    }
}
