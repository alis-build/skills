# JSON Schema options (`protoc-gen-go-jsonschema`)

ADK tools need `JsonSchema()` on request/response messages. Set options in **`tools.proto`**; they take effect when the user runs **define** through Alis Build’s DBD pipeline (see **`../../../references/define-stubs.md`**).

Plugin reference: [protoc-gen-go-jsonschema — field-level options](https://github.com/alis-exchange/protoc-gen-go-jsonschema#field-level-options).

## Proto setup

```protobuf
import "alis/open/options/v1/options.proto";
```

## File-level (required for tools)

```protobuf
option (alis.open.options.v1.file).json_schema.generate = true;
```

Then ask the user to **run a define on the package** `<proto package>`.

## Message-level (optional)

```protobuf
message InternalState {
  option (alis.open.options.v1.message).json_schema.generate = false;
}
```

## Field-level (optional)

| Option | Type | Purpose |
|--------|------|---------|
| `ignore` | bool | Exclude field from schema |
| `title` | string | Schema title |
| `description` | string | Field description |
| `format` | string | `email`, `uri`, `date-time`, … |
| `pattern` | string | Regex for strings |
| `minimum` / `maximum` | double | Numeric bounds |
| `exclusive_minimum` / `exclusive_maximum` | bool | Exclusive bounds |
| `min_length` / `max_length` | int64 | String length |
| `min_items` / `max_items` | int64 | Array length |
| `unique_items` | bool | Unique array items |
| `min_properties` / `max_properties` | int64 | Object property count |
| `content_encoding` | string | e.g. `base64` |
| `content_media_type` | string | Media type hint |

Example:

```protobuf
message LookupTicketRequest {
  string ticket_id = 1 [(alis.open.options.v1.field).json_schema = {
    title: "Ticket ID"
    description: "Support ticket identifier, e.g. TKT-12345"
    pattern: "^TKT-[0-9]+$"
  }];
}
```

## RPC tool descriptions

`ToolsService_<Rpc>_FullMethodDescription` comes from **RPC comments** in `tools.proto`, not from json_schema field options.

## After define

Confirm with the user that define finished. Generated types should expose `JsonSchema()` and `*_FullMethodDescription` constants.

## Schema property names

Generated schemas use **proto field names** (snake_case), not JSON camelCase.

## Troubleshooting

| Symptom | Action |
|---------|--------|
| `JsonSchema undefined` | User should run a define on the package |
| Schema missing a field | Check `ignore: true` on field options |
| Stale generated code | User should re-run define on the package or neuron |
