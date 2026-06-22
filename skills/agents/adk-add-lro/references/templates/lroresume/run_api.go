package lroresume

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	lro "go.alis.build/lro/v2"
	"go.alis.build/alog"
)

const (
	defaultRunAPIPath        = "/api/run"
	defaultHTTPClientTimeout = 2 * time.Minute
	// DefaultAppName matches llmagent.Config.Name in the agent entrypoint.
	DefaultAppName = "REPLACE_WITH_AGENT_APP_NAME"
	// DefaultNeuron matches the alis.lro.v2 service id (infra neuron id).
	DefaultNeuron = "REPLACE_WITH_LRO_SERVICE_ID"
)

// RunAPIConfig controls POST /api/run conversation resume requests.
type RunAPIConfig struct {
	AppName       string
	APIPath       string
	BaseURL       string
	LocalPort     int
	Neuron        string
	ProjectNumber string
	Region        string
}

// ResumeConfig groups settings for resuming the ADK session after an LRO completes.
type ResumeConfig struct {
	AppName string
	RunAPI  RunAPIConfig
}

// DefaultResumeConfig returns production defaults (env augments RunAPI URL resolution).
func DefaultResumeConfig() ResumeConfig {
	return ResumeConfig{
		AppName: DefaultAppName,
		RunAPI: RunAPIConfig{
			Neuron: DefaultNeuron,
		},
	}
}

func resolveRunAPIBaseURL(cfg RunAPIConfig) (string, error) {
	if base := strings.TrimSuffix(strings.TrimSpace(cfg.BaseURL), "/"); base != "" {
		if strings.Contains(base, "://") {
			return base, nil
		}
		parsed, err := url.Parse("http://" + base)
		if err == nil && parsed.Host != "" {
			return parsed.String(), nil
		}
		return base, nil
	}
	if v := strings.TrimSpace(os.Getenv("AGENT_SERVICE_URL")); v != "" {
		return strings.TrimSuffix(v, "/"), nil
	}
	if os.Getenv("K_SERVICE") == "" {
		port := cfg.LocalPort
		if port == 0 {
			port = 8080
		}
		return fmt.Sprintf("http://localhost:%d", port), nil
	}
	neuron := strings.TrimSpace(cfg.Neuron)
	if neuron == "" {
		neuron = strings.TrimSpace(os.Getenv("K_SERVICE"))
	}
	projectNumber := strings.TrimSpace(cfg.ProjectNumber)
	if projectNumber == "" {
		projectNumber = strings.TrimSpace(os.Getenv("ALIS_PROJECT_NR"))
	}
	region := strings.TrimSpace(cfg.Region)
	if region == "" {
		region = strings.TrimSpace(os.Getenv("ALIS_REGION"))
	}
	if neuron == "" || projectNumber == "" || region == "" {
		return "", fmt.Errorf("lroresume: missing neuron, project number, or region for Cloud Run URL")
	}
	return fmt.Sprintf("https://%s-%s.%s.run.app", neuron, projectNumber, region), nil
}

// ResumeAgent posts a functionResponse to POST /api/run. No-op when resume context is empty.
func (rc ADKResumeContext) ResumeAgent(ctx context.Context, cfg RunAPIConfig, response map[string]any, stateDelta map[string]any) error {
	if rc.IsEmpty() {
		return nil
	}
	appName := cfg.AppName
	if appName == "" {
		appName = DefaultAppName
	}
	runCfg := cfg
	runCfg.AppName = appName
	return postRunAPI(ctx, runCfg, rc, response, stateDelta)
}

func postRunAPI(ctx context.Context, cfg RunAPIConfig, rc ADKResumeContext, response map[string]any, stateDelta map[string]any) error {
	if rc.IsEmpty() {
		return nil
	}
	if cfg.AppName == "" {
		return fmt.Errorf("lroresume: app name is required")
	}
	apiPath := cfg.APIPath
	if apiPath == "" {
		apiPath = defaultRunAPIPath
	}
	if !strings.HasPrefix(apiPath, "/") {
		apiPath = "/" + apiPath
	}
	base, err := resolveRunAPIBaseURL(cfg)
	if err != nil {
		return err
	}
	payload := map[string]any{
		"appName":   cfg.AppName,
		"userId":    rc.UserID,
		"sessionId": rc.SessionID,
		"newMessage": map[string]any{
			"role": "agent",
			"parts": []any{
				map[string]any{
					"functionResponse": map[string]any{
						"id":       rc.FunctionCallID,
						"name":     rc.ToolName,
						"response": response,
					},
				},
			},
		},
	}
	if stateDelta != nil {
		payload["stateDelta"] = stateDelta
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal run API payload: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base+apiPath, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create run API request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: defaultHTTPClientTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("post /api/run resume: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("/api/run resume returned %d", resp.StatusCode)
	}
	return nil
}

// ResumeAfterOperation resumes the ADK session when the LRO was started from the agent tool path.
func ResumeAfterOperation(ctx context.Context, cfg ResumeConfig, op *lro.Operation) error {
	rc, err := resumeContextFromOperation(op)
	if err != nil {
		alog.Debugf(ctx, "lroresume: skip resume: %v", err)
		return nil
	}
	if rc.IsEmpty() {
		return nil
	}
	response, err := OperationToResponseMap(op.OperationPb())
	if err != nil {
		return fmt.Errorf("build function response: %w", err)
	}
	runAPI := cfg.RunAPI
	runAPI.AppName = cfg.AppName
	if runAPI.AppName == "" {
		runAPI.AppName = DefaultAppName
	}
	if err := rc.ResumeAgent(ctx, runAPI, response, nil); err != nil {
		return err
	}
	alog.Infof(ctx, "lroresume: resumed tool=%s session=%s operation=%s via /api/run",
		rc.ToolName, rc.SessionID, op.OperationPb().GetName())
	return nil
}

// resumeContextFromOperation decodes ADKResumeContext from LRO private state.
// When using a wrapper private state struct, extend this function (see lro-tool-checklist.md).
func resumeContextFromOperation(op *lro.Operation) (ADKResumeContext, error) {
	// Example for wrapper struct — uncomment and replace type name per LRO tool:
	// var wrapped REPLACE_WITH_LRO_TOOL_PrivateState
	// if err := op.DecodePrivateState(&wrapped); err == nil {
	// 	return wrapped.Resume, nil
	// }
	var rc ADKResumeContext
	if err := op.DecodePrivateState(&rc); err != nil {
		return ADKResumeContext{}, fmt.Errorf("decode resume context: %w", err)
	}
	return rc, nil
}
