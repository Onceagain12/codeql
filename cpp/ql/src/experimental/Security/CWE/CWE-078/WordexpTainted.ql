/**
 * @name Uncontrolled data used in `wordexp` command
 * @description Using user-supplied data in a `wordexp` command, without
 *              disabling command substitution, can make code vulnerable
 *              to command injection.
 * @kind path-problem
 * @problem.severity error
 * @precision high
 * @id cpp/wordexp-injection
 * @tags security
 *       experimental
 *       external/cwe/cwe-078
 */

import cpp
import semmle.code.cpp.ir.dataflow.TaintTracking
import semmle.code.cpp.security.FlowSources
import WordexpTaint::PathGraph

/**
 * The `wordexp` function, which can perform command substitution.
 */
private class WordexpFunction extends Function {
  WordexpFunction() { hasGlobalName("wordexp") }
}

/**
 * Holds if `fc` disables command substitution by containing `WRDE_NOCMD` as a flag argument.
 */
private predicate isCommandSubstitutionDisabled(FunctionCall fc) {
  fc.getArgument(2).getValue().toInt().bitAnd(4) = 4
  /* 4 = WRDE_NOCMD. Check whether the flag is set.  */
}

/**
 * A configuration to track user-supplied data to the `wordexp` function.
 */
module WordexpTaintConfiguration implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) { source instanceof FlowSource }

  predicate isSink(DataFlow::Node sink) {
    exists(FunctionCall fc | fc.getTarget() instanceof WordexpFunction |
      fc.getArgument(0) = sink.asExpr() and
      not isCommandSubstitutionDisabled(fc)
    )
  }

  predicate isBarrier(DataFlow::Node node) {
    node.asExpr().getUnspecifiedType() instanceof IntegralType
  }
}

module WordexpTaint = TaintTracking::Make<WordexpTaintConfiguration>;

from WordexpTaint::PathNode sourceNode, WordexpTaint::PathNode sinkNode
where WordexpTaint::hasFlowPath(sourceNode, sinkNode)
select sinkNode.getNode(), sourceNode, sinkNode,
  "Using user-supplied data in a `wordexp` command, without disabling command substitution, can make code vulnerable to command injection."
