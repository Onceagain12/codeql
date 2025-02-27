/**
 * @name Overflow in uncontrolled allocation size
 * @description Allocating memory with a size controlled by an external
 *              user can result in integer overflow.
 * @kind path-problem
 * @problem.severity error
 * @security-severity 8.1
 * @precision medium
 * @id cpp/uncontrolled-allocation-size
 * @tags reliability
 *       security
 *       external/cwe/cwe-190
 *       external/cwe/cwe-789
 */

import cpp
import semmle.code.cpp.rangeanalysis.SimpleRangeAnalysis
import semmle.code.cpp.ir.dataflow.TaintTracking
import semmle.code.cpp.ir.IR
import semmle.code.cpp.controlflow.IRGuards
import semmle.code.cpp.security.FlowSources
import TaintedAllocationSize::PathGraph

/**
 * Holds if `alloc` is an allocation, and `tainted` is a child of it that is a
 * taint sink.
 */
predicate allocSink(HeuristicAllocationExpr alloc, DataFlow::Node sink) {
  exists(Expr e | e = sink.asConvertedExpr() |
    e = alloc.getAChild() and
    e.getUnspecifiedType() instanceof IntegralType
  )
}

predicate readsVariable(LoadInstruction load, Variable var) {
  load.getSourceAddress().(VariableAddressInstruction).getAstVariable() = var
}

predicate hasUpperBoundsCheck(Variable var) {
  exists(RelationalOperation oper, VariableAccess access |
    oper.getAnOperand() = access and
    access.getTarget() = var and
    // Comparing to 0 is not an upper bound check
    not oper.getAnOperand().getValue() = "0"
  )
}

predicate nodeIsBarrierEqualityCandidate(DataFlow::Node node, Operand access, Variable checkedVar) {
  exists(Instruction instr | instr = node.asOperand().getDef() |
    readsVariable(instr, checkedVar) and
    any(IRGuardCondition guard).ensuresEq(access, _, _, instr.getBlock(), true)
  )
}

predicate isFlowSource(FlowSource source, string sourceType) { sourceType = source.getSourceType() }

module TaintedAllocationSizeConfiguration implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) { isFlowSource(source, _) }

  predicate isSink(DataFlow::Node sink) { allocSink(_, sink) }

  predicate isBarrier(DataFlow::Node node) {
    exists(Expr e | e = node.asExpr() |
      // There can be two separate reasons for `convertedExprMightOverflow` not holding:
      // 1. `e` really cannot overflow.
      // 2. `e` isn't analyzable.
      // If we didn't rule out case 2 we would place barriers on anything that isn't analyzable.
      (
        e instanceof UnaryArithmeticOperation or
        e instanceof BinaryArithmeticOperation or
        e instanceof AssignArithmeticOperation
      ) and
      not convertedExprMightOverflow(e)
      or
      // Subtracting two pointers is either well-defined (and the result will likely be small), or
      // terribly undefined and dangerous. Here, we assume that the programmer has ensured that the
      // result is well-defined (i.e., the two pointers point to the same object), and thus the result
      // will likely be small.
      e = any(PointerDiffExpr diff).getAnOperand()
    )
    or
    exists(Variable checkedVar, Instruction instr | instr = node.asOperand().getDef() |
      readsVariable(instr, checkedVar) and
      hasUpperBoundsCheck(checkedVar)
    )
    or
    exists(Variable checkedVar, Operand access |
      readsVariable(access.getDef(), checkedVar) and
      nodeIsBarrierEqualityCandidate(node, access, checkedVar)
    )
    or
    // block flow to inside of identified allocation functions (this flow leads
    // to duplicate results)
    any(HeuristicAllocationFunction f).getAParameter() = node.asParameter()
  }
}

module TaintedAllocationSize = TaintTracking::Make<TaintedAllocationSizeConfiguration>;

from
  Expr alloc, TaintedAllocationSize::PathNode source, TaintedAllocationSize::PathNode sink,
  string taintCause
where
  isFlowSource(source.getNode(), taintCause) and
  TaintedAllocationSize::hasFlowPath(source, sink) and
  allocSink(alloc, sink.getNode())
select alloc, source, sink, "This allocation size is derived from $@ and might overflow.",
  source.getNode(), "user input (" + taintCause + ")"
