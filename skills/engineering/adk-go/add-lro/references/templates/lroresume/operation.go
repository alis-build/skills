package lroresume

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	lro "go.alis.build/lro/v2"
	"cloud.google.com/go/longrunning/autogen/longrunningpb"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/durationpb"
)

// WaitConfig controls LRO wait behavior shared by resumer implementations.
type WaitConfig struct {
	LROClient   *lro.Client
	WaitTimeout time.Duration
}

// WaitForOperation blocks until the named operation completes or the timeout elapses.
func WaitForOperation(ctx context.Context, cfg WaitConfig, operationName string) (*longrunningpb.Operation, error) {
	if cfg.LROClient == nil {
		return nil, fmt.Errorf("lroresume: LRO client is required")
	}
	timeout := cfg.WaitTimeout
	if timeout == 0 {
		timeout = 2 * time.Minute
	}
	waitCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	op, err := cfg.LROClient.OperationsServer().WaitOperation(waitCtx, &longrunningpb.WaitOperationRequest{
		Name:    operationName,
		Timeout: durationpb.New(timeout),
	})
	if err != nil {
		return nil, fmt.Errorf("wait operation %q: %w", operationName, err)
	}
	if !op.GetDone() {
		return nil, fmt.Errorf("operation %q not done after wait", operationName)
	}
	return op, nil
}

// LoadResumeContext reads ADKResumeContext from LRO private state.
// Extend this when private state is a wrapper struct (see lro-tool-checklist.md).
func LoadResumeContext(ctx context.Context, client *lro.Client, operationName string) (ADKResumeContext, error) {
	if client == nil {
		return ADKResumeContext{}, fmt.Errorf("lroresume: LRO client is required")
	}
	lroOp, err := client.GetOperation(ctx, operationName)
	if err != nil {
		return ADKResumeContext{}, fmt.Errorf("load operation %q: %w", operationName, err)
	}
	var rc ADKResumeContext
	if err := lroOp.DecodePrivateState(&rc); err == nil && !rc.IsEmpty() {
		return rc, nil
	}
	return ADKResumeContext{}, fmt.Errorf("decode resume context from %q: no ADKResumeContext in private state", operationName)
}

// OperationToResponseMap builds a JSON-friendly functionResponse payload from an operation.
func OperationToResponseMap(op *longrunningpb.Operation) (map[string]any, error) {
	if st := op.GetError(); st != nil {
		return map[string]any{
			"name":  op.GetName(),
			"done":  true,
			"error": st.GetMessage(),
		}, nil
	}
	if respAny := op.GetResponse(); respAny != nil {
		m, err := anyToMap(respAny)
		if err != nil {
			return nil, err
		}
		m["name"] = op.GetName()
		m["done"] = true
		return m, nil
	}
	return map[string]any{
		"name": op.GetName(),
		"done": op.GetDone(),
	}, nil
}

func anyToMap(msg *anypb.Any) (map[string]any, error) {
	unmarshaled, err := msg.UnmarshalNew()
	if err != nil {
		return nil, err
	}
	return protoMessageToMap(unmarshaled)
}

func protoMessageToMap(msg proto.Message) (map[string]any, error) {
	raw, err := protojson.MarshalOptions{EmitUnpopulated: true}.Marshal(msg)
	if err != nil {
		return nil, err
	}
	var decoded any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		return nil, err
	}
	if decoded == nil {
		return map[string]any{}, nil
	}
	if asMap, ok := decoded.(map[string]any); ok {
		return asMap, nil
	}
	return map[string]any{"result": decoded}, nil
}

// OperationNameFromToolResult extracts a google LRO operation name from an ADK tool result map.
func OperationNameFromToolResult(result map[string]any) string {
	if name, ok := result["name"].(string); ok && name != "" {
		return name
	}
	if name, ok := result["operation_name"].(string); ok && name != "" {
		return name
	}
	return ""
}
