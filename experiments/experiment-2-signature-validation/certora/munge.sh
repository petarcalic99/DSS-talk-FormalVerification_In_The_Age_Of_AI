#!/usr/bin/env bash
# Copies src/ to certora/munged/ and makes ONE change for the prover:
# SignatureChecker reads the contract signer's address through a virtual
# function instead of slicing it out of the signature bytes. The prover cannot
# follow an address sliced out of symbolic bytes, so it could not resolve the
# call to the signer. The harness overrides the function to return the model
# wallet. _isValidContractSignature, where the bug is, is not touched.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf certora/munged
cp -r src certora/munged
python3 - certora/munged/SignatureChecker.sol <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "        signer = address(bytes20(signature[0:20]));"
assert old in s, "munge target not found"
s = s.replace(old, "        signer = _contractSigner(signature); // MUNGED")
s = s.replace(
    "    /// @dev Asks the signer contract",
    "    /// @dev MUNGED: where the contract signer's address comes from.\n"
    "    function _contractSigner(bytes calldata signature) internal view virtual returns (address) {\n"
    "        return address(bytes20(signature[0:20]));\n"
    "    }\n\n"
    "    /// @dev Asks the signer contract",
)
open(p, "w").write(s)
PY
echo "munged: certora/munged/"
