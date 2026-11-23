// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// Contract "signers" with different ERC-1271 behaviours. Only a normal return
/// of exactly the magic value counts as a valid signature.

/// @dev Approves everything (normal return of the magic value).
contract ApproveAllSigner {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return 0x1626ba7e;
    }
}

/// @dev Always reverts, with the magic value as revert data. Signs nothing.
contract RevertingMagicSigner {
    fallback() external {
        assembly {
            mstore(0, 0x1626ba7e00000000000000000000000000000000000000000000000000000000)
            revert(0, 32)
        }
    }
}

/// @dev Always reverts with empty revert data.
contract RevertingEmptySigner {
    fallback() external {
        revert();
    }
}

/// @dev Returns normally, with a value that is not the magic value.
contract WrongValueSigner {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return 0xdeadbeef;
    }
}

/// @dev Returns normally, with no return data.
contract SilentSigner {
    fallback() external {}
}
