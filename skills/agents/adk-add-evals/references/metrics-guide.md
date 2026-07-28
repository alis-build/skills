# Eval metrics guide

The evals sublauncher scores eval cases via `metrics.Registry`. Call `GET /api/dev/apps/{app}/metrics-info` to list registered metrics and metadata.

For eval design rationale (trajectory vs final response, groundtruth vs rubric metrics), see [Evaluate agents](https://adk.dev/evaluate/) on adk.dev.

Default registry: `metrics.NewDefaultRegistry()` / `metrics.DefaultRegistry` in `go.alis.build/adk/launchers/evals/evaluation/metrics`.

## Why wire a judge client

The default registry registers all standard adk-python metrics but leaves injectable clients nil. Metrics that need an LLM judge or Vertex client return **`NOT_EVALUATED`** when the client is missing — they do not fail the run silently with a zero score.

Wire `RegistryConfig.JudgeClient` for LLM-judge metrics. See `references/templates/evals-metrics-registry.go.example`.

Use a **separate** `genai.Client` for the judge (not the agent's model client) so judge failures do not affect user-facing inference. Fail fast at startup if judge client creation fails.

## Metric catalog

| Metric name | Needs | Description |
|-------------|-------|-------------|
| `tool_trajectory_avg_score` | None | Expected vs actual tool call trajectories. Score 0–1. |
| `response_match_score` | None | ROUGE-1 final response vs expected. Score 0–1. |
| `final_response_match_v2` | `JudgeClient` | LLM-judge comparison of final response. Score 0–1. |
| `hallucinations_v1` | `JudgeClient` | Detects false or unsupported claims. Score 0–1. |
| `rubric_based_final_response_quality_v1` | `JudgeClient` | Rubric-based judge on final response (needs golden expected data). |
| `rubric_based_tool_use_quality_v1` | `JudgeClient` | Rubric-based judge on tool trajectory (reference-free). |
| `rubric_based_multi_turn_trajectory_quality_v1` | `JudgeClient` | Rubric-based judge on full dialogue. |
| `per_turn_user_simulator_quality_v1` | `JudgeClient` | LLM-backed user simulator turn quality. |
| `response_evaluation_score` | `VertexEvalClient` | Vertex coherence. Range 1–5. |
| `safety_v1` | `VertexEvalClient` | Vertex harmlessness. Score 0–1. |
| `multi_turn_task_success_v1` | `VertexEvalClient` | Multi-turn task success. |
| `multi_turn_trajectory_quality_v1` | `VertexEvalClient` | Multi-turn trajectory quality. |
| `multi_turn_tool_use_quality_v1` | `VertexEvalClient` | Multi-turn tool use quality. |

## Recommended starting set

For most agents without `VertexEvalClient` wired:

- **Trajectory:** `tool_trajectory_avg_score` (no client needed)
- **Response match:** `response_match_score` or `final_response_match_v2` (latter needs judge)
- **Quality rubrics:** `rubric_based_tool_use_quality_v1`, `rubric_based_final_response_quality_v1` (need judge + rubric criteria in eval case)
- **Hallucination:** `hallucinations_v1` (needs judge)

Avoid requesting Vertex metrics until `VertexEvalClient` is implemented — they will all return `NOT_EVALUATED`.

## Judge model

Use a fast/cheap model for judge calls (eval runs can invoke the judge many times per case). Common default: `gemini-2.5-flash`.

Per-metric `JudgeModelOptions` can override model and `GenerateContentConfig`. The registry's default model applies when the metric omits a model.

## Rubric-based metrics

Three rubric metrics score against caller-supplied `RubricsBasedCriterion`:

- **Final response quality** — requires golden expected data; judges actual final response against reference.
- **Tool use quality** — reference-free; judges actual tool trajectory.
- **Multi-turn trajectory quality** — single LLM call over full dialogue; earlier turns marked `NOT_EVALUATED`.

Judge responses use adk-python prompt templates and parse `Property:` / `Rationale:` / `Verdict:` blocks. Verdicts must be `yes` or `no`.

When `JudgeModelOptions.NumSamples` > 1, samples are majority-vote aggregated per rubric.

## Run eval request

`POST /api/dev/apps/{app}/eval-sets/{id}/run` body:

```json
{
  "eval_case_ids": ["case-1"],
  "eval_metrics": [
    {
      "metric_name": "tool_trajectory_avg_score"
    },
    {
      "metric_name": "final_response_match_v2"
    }
  ]
}
```

Legacy field `eval_ids` is accepted as an alias for `eval_case_ids`.

## Custom metrics

Metrics with `custom_function_path` set use a placeholder evaluator that returns `NOT_EVALUATED` until registered via `Registry.RegisterEvaluator`.

## Verifying metrics are wired

1. Start agent with `evals` sublauncher active.
2. `GET /api/dev/apps/{AppName}/metrics-info` — should return metric metadata list.
3. Run a small eval set with a judge metric — score should not be `NOT_EVALUATED` if `JudgeClient` is wired and Vertex auth works.

If judge metrics stay `NOT_EVALUATED`, check: registry passed to `WithMetricRegistry`, judge client non-nil, Vertex project/region env vars set, model name valid.
