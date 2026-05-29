// Package lroresume resumes ADK conversations via POST /api/run after google LRO tools complete.
//
// Requires the ADK "api" web sublauncher on the same HTTP server. Handler resume
// (Cloud Tasks → /resume-operation/...) is separate; see go.alis.build/adk/launchers/lro.
//
// Wiring:
//
//  1. [WrapToolContext] in the functiontool wrapper (NewLROTool).
//  2. Persist [ADKResumeContext] in LRO private state in the RPC handler.
//  3. Call [ResumeAfterOperation] from the resumable LRO handler when the operation completes.
package lroresume
