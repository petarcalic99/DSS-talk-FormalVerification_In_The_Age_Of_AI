/-
Experiment 1 in Verity: import of the model contract `wrapper/src/WrapperModel.sol`.

Run inside the Verity checkout with `lake env lean lean/Model.lean`.
All ten functions import (`importable denoteCovered true`); the `#eval` prints Verity's report.

This file only translates the contract into a Verity `CompilationModel`. The theorems in
`RoundTrip.lean` are stated over the same formulas, copied by hand; the bridge theorem that
links them to this imported model is not written yet.
-/
import Compiler.SolidityImport.Import

namespace Wrapper.Model
solidity_import imported from "wrapper" entry "src/WrapperModel.sol"
  using { evmVersion := "osaka", viaIR := false, optimizerRuns := some 200, bytecodeHash := "none" }
  contract WrapperModel
  function totalVaultShares()
  function previewWrap(uint256)
  function previewUnwrap(uint256)
  function previewDeposit(uint256)
  function previewRedeem(uint256)
  function wrap(uint256)
  function unwrap(uint256)
  function donate(uint256)
  function deposit(uint256)
  function redeem(uint256)
end Wrapper.Model

#eval IO.println Wrapper.Model.imported.report.toText
