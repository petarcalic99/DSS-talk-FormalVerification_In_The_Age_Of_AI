/-
Experiment 2 in Verity: import attempt (expected to FAIL).

Expects experiment 2's sources copied into the Verity checkout as `exp2/src/`
(see ../README.md). Run with `lake env lean lean/Exp2Import.lean`.

Observed result (Verity a10dcd4, solc 0.8.34):
  src/SignatureChecker.sol:60:13: MemberAccess: [solidity-import:unsupported]
  external contract calls are outside this slice
  closure: TimelockModule.execTransactionFromModuleSigned -> ModuleAuth.moduleOnlySigned
           -> SignatureChecker.signedBy -> SignatureChecker._isValidContractSignature
  signer.staticcall

The low-level `staticcall`, returning `(bool, bytes memory)`, is exactly where the bug lives
(the success flag is ignored), so no rewrite that Verity accepts keeps the bug intact
except an inline-assembly version.
-/
import Compiler.SolidityImport.Import

namespace Exp2
solidity_import imported from "exp2" entry "src/TimelockModule.sol"
  using { evmVersion := "osaka", viaIR := false, optimizerRuns := some 200, bytecodeHash := "none" }
  contract TimelockModule
  function execTransactionFromModuleSigned(address,uint256,bytes,uint256,bytes)
end Exp2
