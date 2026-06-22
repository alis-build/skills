# Add a synchronous tool

Use this checklist for each new **immediate-return** RPC on `ToolsService`. For long-running operations, stop here and use the **add-lro** skill instead.

Confirm paths with **`workspace-tools.md`** / **`alis-workspace.md`** (same directory) before editing.

## Checklist

1. **Proto** — Add RPC + request/response messages to **this agent’s** `tools.proto`.
   - Write multi-line comments on the RPC: when to use, when not to use, constraints.
   - Use `google.protobuf.Empty` only for no-payload success responses.
   - Tool name will be **snake_case** derived from the RPC (e.g. `LookupTicket` → `lookup_ticket`).
   - Optionally refine fields with `(alis.open.options.v1.field).json_schema` (see **`references/json-schema.md`**).

2. **define (user)** — Ask: **run a define on the package** **`<package from tools.proto>`**. **Stop.** No `go mod edit`, no `go get`, no Go. See **`define-stubs.md`**.

3. **Install deps (user)** — Ask: **install the required dependencies**. Wait for confirmation.

4. **Handler** — Implement the method on `myToolsService` in `internal/tools/service.go`.
   - Validate required fields; return `codes.InvalidArgument` for bad input.
   - Keep business logic in the service method (same code path for ADK and gRPC).

5. **Register** — Append to `MyTools()`:
   - Normal response: `NewTool("snake_name", pb.ToolsService_<Rpc>_FullMethodDescription, toolsService.<Rpc>)`
   - Empty response: `NewToolForEmpty(...)`
   - Sensitive/destructive: add `WithRequireConfirmation()` as the last option.

6. **Verify**
   - `go build ./...`
   - Local ADK web: invoke the tool with realistic inputs.
   - Confirm the model sees the description from proto comments.

## Worked example: `lookup_ticket`

### Proto (add to `tools.proto`)

```protobuf
rpc LookupTicket(LookupTicketRequest) returns (LookupTicketResponse);

message LookupTicketRequest {
  string ticket_id = 1;  // Required. Ticket ID, e.g. "TKT-12345".
}

message LookupTicketResponse {
  string status = 1;
  string summary = 2;
}
```

### Handler

```go
func (s *myToolsService) LookupTicket(ctx context.Context, req *pb.LookupTicketRequest) (*pb.LookupTicketResponse, error) {
    ticketID := strings.TrimSpace(req.GetTicketId())
    if ticketID == "" {
        return nil, status.Error(codes.InvalidArgument, "ticket_id is required")
    }
    // business logic...
    return &pb.LookupTicketResponse{Status: "open", Summary: "..."}, nil
}
```

### Registration

```go
NewTool(
    "lookup_ticket",
    pb.ToolsService_LookupTicket_FullMethodDescription,
    toolsService.LookupTicket,
),
```

## Worked example: `archive_session` (empty + confirmation)

### Proto

```protobuf
rpc ArchiveSession(ArchiveSessionRequest) returns (google.protobuf.Empty);

message ArchiveSessionRequest {
  string session_id = 1;
}
```

### Handler

```go
func (s *myToolsService) ArchiveSession(ctx context.Context, req *pb.ArchiveSessionRequest) (*emptypb.Empty, error) {
    if strings.TrimSpace(req.GetSessionId()) == "" {
        return nil, status.Error(codes.InvalidArgument, "session_id is required")
    }
    return &emptypb.Empty{}, nil
}
```

### Registration

```go
NewToolForEmpty(
    "archive_session",
    pb.ToolsService_ArchiveSession_FullMethodDescription,
    toolsService.ArchiveSession,
    WithRequireConfirmation(),
),
```

## Optional: toolsets

If you prefer grouping over a flat `Tools` slice:

```go
Toolsets: []tool.Toolset{tools.MyToolsSet()},
```

Do not register the same tool in both `Tools` and `Toolsets`.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Missing `json_schema.generate` | Add file option; user runs define on the package (see `references/json-schema.md`) |
| Field validation too weak | Add field-level `json_schema` options (`pattern`, `format`, bounds) |
| Tool name not snake_case | Match ADK convention: `lookup_ticket` not `LookupTicket` |
| LRO RPC added in add-tool flow | Use add-lro; sync and LRO may share `tools.proto` |
| Weak RPC comments | Model uses `FullMethodDescription` for tool choice |
| LRO tool added here | Use add-lro skill instead |

Full runnable examples live in `references/templates/service.go.example` and `references/templates/tools.proto.example`.
