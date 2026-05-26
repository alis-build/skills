package lroresume

import (
	"context"
	"encoding/gob"
)

func init() {
	gob.Register(ADKResumeContext{})
	gob.Register(resumeToolInfo{})
	// Register each per-tool private state type used in LRO handlers, e.g.:
	// gob.Register(REPLACE_WITH_LRO_TOOL_PrivateState{})
}

// ADKResumeContext carries identifiers needed to resume a conversation after an LRO
// completes. Store it in LRO private state (gob-encoded), typically inside a
// tool-specific private state struct with a Resume field.
type ADKResumeContext struct {
	ToolName       string
	SessionID      string
	UserID         string
	FunctionCallID string
}

// IsEmpty reports whether the context lacks the minimum fields for resume.
func (rc ADKResumeContext) IsEmpty() bool {
	return rc.FunctionCallID == "" || rc.SessionID == ""
}

type resumeToolInfo struct {
	ToolName       string
	SessionID      string
	UserID         string
	FunctionCallID string
}

type resumeToolInfoKey struct{}

// ContextWithResumeTool attaches tool-call metadata to ctx for LRO RPC handlers.
func ContextWithResumeTool(ctx context.Context, toolName, sessionID, userID, functionCallID string) context.Context {
	return context.WithValue(ctx, resumeToolInfoKey{}, resumeToolInfo{
		ToolName:       toolName,
		SessionID:      sessionID,
		UserID:         userID,
		FunctionCallID: functionCallID,
	})
}

// ResumeContextFromContext returns metadata previously stored on ctx.
func ResumeContextFromContext(ctx context.Context) (ADKResumeContext, bool) {
	info, ok := ctx.Value(resumeToolInfoKey{}).(resumeToolInfo)
	if !ok {
		return ADKResumeContext{}, false
	}
	return ADKResumeContext{
		ToolName:       info.ToolName,
		SessionID:      info.SessionID,
		UserID:         info.UserID,
		FunctionCallID: info.FunctionCallID,
	}, true
}

// WrapToolContext is a convenience wrapper for functiontool handlers.
func WrapToolContext(tc interface {
	SessionID() string
	UserID() string
	FunctionCallID() string
}, toolName string, ctx context.Context) context.Context {
	return ContextWithResumeTool(ctx, toolName, tc.SessionID(), tc.UserID(), tc.FunctionCallID())
}
