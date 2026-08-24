# Protocol conformance

Deliverable of Phase 0, completed 2026-08-24. This records exactly what this
package implements and against which revision, so that none of it is ever
re-derived from memory. Every answer below is taken from the specification
text, with the source page named. Quoted sentences are verbatim.

**Revision implemented: `2026-07-28`.**

Source pages, all under `https://modelcontextprotocol.io/specification/2026-07-28/`:
`basic/index`, `basic/versioning`, `basic/transports`, `basic/transports/stdio`,
`server/discover`, `server/tools`, `server/resources`.

---

## 0. The finding that matters most

**This revision has no `initialize` handshake and the protocol is normatively
stateless.** From `basic/index`:

> The Model Context Protocol (MCP) is a **stateless protocol**: all the
> information needed to process a request is contained in the request itself.
> A server processes each request independently; no state should be inferred
> from previous requests, even those on the same connection or stream.

and

> Servers **MUST NOT** rely on prior requests over the same connection to
> establish context (e.g., capabilities, protocol version, client identity).

and

> Clients **SHOULD NOT** use an individual task, thread, or conversation as the
> lifetime boundary for the stdio process.

and

> State that needs to span multiple requests (e.g., long-running tasks,
> application-level handles) **MUST** be referenced by an explicit identifier
> the client passes on each request.

with the note:

> This implies that an open connection, such as a STDIO process, is not a
> conversation or session: clients may interleave unrelated requests on the same
> transport, and a server must not treat connection or process identity as a
> proxy for conversation or session continuity.

**Consequence for `mcp.serve`: none.** The read-only tool set is already
stateless; each call answers from the interpreter's own state, which is a
property of the machine and not of the conversation.

**Consequence for `mcp.serveEval`: the design in `OCTAVE_MCP_PLAN.md` section 2
is void.** "One interpreter per connection, holding a workspace across calls"
is exactly what the paragraphs above forbid, and it was written from a mental
model of MCP that this revision retired. The specification prescribes the
replacement itself, in `server/tools` under "Stateful Tools":

> MCP has no protocol-level session, so a server cannot rely on implicit
> per-connection state to relate one tool call to the next. Servers that need to
> maintain state across calls [...] should do so by returning an explicit handle
> from a creation tool and accepting that handle as an argument on subsequent
> calls.

So a workspace becomes a named object with an explicit lifetime: a creation
tool returns an opaque handle, every evaluation carries it, the handle's
retention policy is stated in the creation tool's description, and a call
against an expired handle returns a tool error saying so. Handles are to be
opaque and generated with sufficient entropy, per the same section.

This is a better design than the one it replaces and it composes with the
worker-process containment of Phase 5 rather than fighting it, since a handle
was always going to be the honest name for "which interpreter".

## 1. Framing

From `basic/transports/stdio`:

> * The server reads JSON-RPC messages from `stdin` and writes JSON-RPC messages to
>   `stdout`.
> * Each message is a single JSON-RPC request, notification, or response.
> * Messages are delimited by newlines, and **MUST NOT** contain embedded newlines.

Newline-delimited JSON. Not length-prefixed. This was the question that had to
be answered from the text and not by analogy, and it is now closed.

Encoding, from `basic/transports`:

> JSON-RPC messages **MUST** be UTF-8 encoded.

## 2. Standard output purity

From `basic/transports/stdio`, and this is the normative basis for decision D4:

> * The server **MAY** write UTF-8 strings to `stderr` for any logging purposes
>   including informational, debug, and error messages.
> * The client **MAY** capture, forward, or ignore the server's `stderr` output and
>   **SHOULD NOT** assume `stderr` output indicates error conditions.
> * The server **MUST NOT** write anything to its `stdout` that is not a valid MCP
>   message.

Also:

> The server **MUST NOT** write JSON-RPC *requests* to `stdout`.

Our server never needs to: server-to-client interaction is carried by
`InputRequiredResult` replies, which we do not use.

## 3. Lifecycle

There is no handshake. From `basic/versioning`:

> There is no negotiation handshake. Every request carries its protocol
> version, and the server accepts or rejects each request independently.

Every client request carries, in `params._meta`:

| Key | Required | Note |
|---|---|---|
| `io.modelcontextprotocol/protocolVersion` | yes | e.g. `"2026-07-28"` |
| `io.modelcontextprotocol/clientCapabilities` | yes | `ClientCapabilities` object |
| `io.modelcontextprotocol/clientInfo` | no | client name and version, display only |

> A request missing any required field is malformed; the server **MUST** reject it with
> JSON-RPC error code `-32602` (Invalid params).

Every result **SHOULD** carry `_meta["io.modelcontextprotocol/serverInfo"]`
with our name and version.

### `server/discover`

From `server/discover`:

> `server/discover` lets a client query a server's supported protocol versions,
> capabilities, and identity before sending any other requests. Servers **MUST**
> implement it.

Request params are `_meta` only. The result shape we return:

```json
{
  "resultType": "complete",
  "supportedVersions": ["2026-07-28"],
  "capabilities": { "tools": {}, "resources": {} },
  "_meta": { "io.modelcontextprotocol/serverInfo": { "name": "mcp", "version": "0.1.0" } },
  "instructions": "...",
  "ttlMs": 3600000,
  "cacheScope": "public"
}
```

`instructions` is optional natural-language guidance for the model on using the
server. It is subject to `TOOL_STYLE.md` for the same reason tool descriptions
are: it is re-sent, and it is read by a model rather than a person.

We declare neither `listChanged` nor `subscribe`. The tool and resource sets are
fixed at load time and never change while a process lives, so there is nothing
to notify about.

### Unsupported version

> If the server does not implement the requested version [...] it **MUST** respond with
> an `UnsupportedProtocolVersionError` listing the versions it does support

Code `-32022`, with `data.supported` and `data.requested`.

## 4. Results

Every result **MUST** carry a `resultType`:

> The `result` **MUST** include a `resultType` field to indicate the type of the result.

We emit `"complete"` and nothing else. `"input_required"` belongs to Multi
Round-Trip Requests, which this server does not use.

Requests carry a string or integer id:

> * Requests **MUST** include a string or integer ID.
> * Unlike base JSON-RPC, the ID **MUST NOT** be `null`.

**Trap:** `jsondecode` returns a double for a JSON integer. An id sent as
`"1"` must be echoed as `"1"`, not `1`. Round-tripping the id's *type* is a
correctness requirement and gets its own BIST.

Notifications carry no id and:

> The receiver **MUST NOT** send a response.

## 5. Errors

Standard JSON-RPC codes `-32700`, `-32600` to `-32603`. MCP additions in
`-32020` to `-32099`, of which we may emit only `-32022`
(`UnsupportedProtocolVersion`). `-32021` (`MissingRequiredClientCapability`) is
unreachable for us: none of our tools requires a client capability.

> New codes **MUST NOT** be allocated in this sub-range [`-32000` to `-32019`]

so we allocate nothing there.

**The protocol-error versus tool-error split**, from `server/tools`:

| Kind | Examples | Wire form |
|---|---|---|
| Protocol error | unknown tool, malformed request, server error | JSON-RPC `error`, typically `-32602` |
| Tool execution error | input validation, business logic, "name not found" | `result` with `isError: true` |

> Clients **SHOULD** provide tool execution errors to language models to enable self-correction.

This settles the shape of our commonest failure: `octave_help ("nosuchthing")`
is a **tool execution error**, not a protocol error, because the model can
correct it. An unknown *tool name* is a protocol error.

Resource not found is `-32602`, per `server/resources`, and:

> Servers **MUST NOT** return an empty `contents` array for a non-existent resource.

## 6. Tools

`tools/list` result fields: `tools`, optional `nextCursor`, optional `ttlMs`
and `cacheScope`. Our list is small and fixed, so we return no cursor and set a
long `ttlMs` with `cacheScope: "public"`, which is a direct saving for every
user on every request.

> Servers **SHOULD** return tools in a deterministic order

We emit a fixed order.

Tool definition fields: `name`, optional `title`, `description`, optional
`icons`, `inputSchema` (**MUST** be a valid JSON Schema object, not null),
optional `outputSchema`, optional `annotations`. For a tool with no parameters
the recommended schema is `{ "type": "object", "additionalProperties": false }`.

`tools/call` result: `content` array, plus `isError`, plus optional
`structuredContent`.

**Adopt `structuredContent`.** `octave_which` and `octave_pkg` return naturally
tabular data, and the specification's guidance is to return both:

> For backwards compatibility, a tool that returns structured content SHOULD also
> return the serialized JSON in a TextContent block.

This was not in the plan and should be. It costs an `outputSchema` per tool and
makes the results machine-checkable at the client.

### Tool names, and decision D3c

> * Tool names **SHOULD** be between 1 and 128 characters in length (inclusive).
> * Tool names **SHOULD** be considered case-sensitive.
> * The following **SHOULD** be the only allowed characters: uppercase and lowercase
>   ASCII letters (A-Z, a-z), digits (0-9), underscore (\_), hyphen (-), and dot (.)

On disambiguation:

> Tool name uniqueness is scoped to a single server. Clients or proxies that
> aggregate tools from multiple servers **MAY** encounter naming collisions (for
> example, two servers each exposing a `search` tool) and **SHOULD** implement a
> disambiguation strategy such as prefixing tool names with a server identifier.
>
> The server `name` (from `serverInfo`) is not guaranteed to be unique across
> servers and **SHOULD NOT** be relied upon for disambiguation.

**D3c is settled: keep the `octave_` prefix.** The specification puts
disambiguation on the client, but only as a **SHOULD**, and it names our exact
situation as the example, since our unprefixed names would be `help`, `which`,
`search` and `pkg`. The cost of prefixing is about one token per tool per
request. The cost of a collision is a model calling another server's `search`
and believing the answer. The asymmetry decides it. Redundant qualification in
a well-behaved host is the price of correctness in a badly behaved one.

## 7. Resources

`resources/list` returns `resources` with optional `nextCursor`, `ttlMs`,
`cacheScope`. `resources/read` returns `contents`, each with `uri`, `mimeType`
and `text` or `blob`.

Custom schemes are permitted:

> This list is not exhaustive—implementations are always free to use additional,
> custom URI schemes.
> Custom URI schemes **MUST** be in accordance with RFC3986

so `octave://version`, `octave://path` and `octave://packages` are well formed.

## 8. Cancellation, and an honest limitation

> To cancel an in-flight request, the client **MUST** send a
> `notifications/cancelled` notification referencing the request's ID. [...]
> Servers **SHOULD** stop work on a cancelled request as soon as practical and
> **MUST NOT** send any further messages for it.

`mcp.serve` reads, dispatches and writes serially in one thread, so a
`notifications/cancelled` for a request already dispatched cannot be seen until
that request's response has been written. We therefore **cannot** honour the
`MUST NOT` for a request already in flight.

In practice the read-only tools return in milliseconds and the window is
negligible, but it is a real non-conformance and it is recorded here rather
than discovered later. It is also a second, independent argument for the worker
process of Phase 5: a supervisor that can service stdin while a worker computes
is what makes cancellation implementable at all.

`notifications/cancelled` for an id we have already answered is discarded
silently, which is correct: it is a notification, and a notification is never
answered.

## 9. Shutdown

> Servers **SHOULD** exit promptly when their standard input is closed or reads
> return end-of-file. This is the primary graceful-shutdown signal and the only
> portable one

End of file on stdin ends the loop and the process exits 0. This is the loop's
only exit condition.

> If the server process exits unexpectedly, the client **SHOULD** restart it.
> Because the protocol is stateless, any in-flight requests are simply lost and
> the client can retry them against the fresh process.

Worth noting for Phase 4: the host restarting a wedged server is a
specification-sanctioned recovery, not a workaround.

## 10. Which era do real hosts speak?  [ANSWERED 2026-08-24: legacy]

The revision is nine months newer than the previous one, and the compatibility
matrix in `basic/versioning` is blunt about the risk:

| Client | Server | Outcome |
|---|---|---|
| Legacy | Modern | **Fails.** |
| Legacy | Dual-era | Works. |
| Modern | Modern | Works. |

A legacy client sends `initialize`; a modern-only server rejects it and the
connection is dead. If the hosts people actually run are still legacy
(`2025-11-25` or earlier), a modern-only implementation is correct and unusable.

A dual-era server is explicitly permitted:

> A dual-era **server** selects its behavior from how the client opens:
> * A request carrying modern per-request `_meta` is served statelessly
>   according to this revision.
> * An `initialize` request selects legacy semantics [...]

**Measured 2026-08-24. The host in use is legacy.** Claude Code 2.1.241, driven
through `claude --mcp-config` with `--strict-mcp-config` and both directions
teed to disk, opened with:

```json
{"method":"initialize","params":{"protocolVersion":"2025-11-25",
 "capabilities":{"roots":{"listChanged":true},"elicitation":{}},
 "clientInfo":{"name":"claude-code","version":"2.1.241"}},"jsonrpc":"2.0","id":0}
```

So **dual-era support is mandatory**, not optional. A prior taken from strings
inside the client binary pointed the other way and was wrong, which is the whole
reason the experiment was run rather than reasoned about.

This server answered as the specification's SHOULD requires, and the obligation
is worth keeping in view because it is what a legacy user sees:

> A server that supports only modern versions **SHOULD** name the protocol
> versions it supports in any error it returns to an `initialize` request [...]
> legacy clients have no fall-forward mechanism, and this message may be the
> only diagnostic they can surface to users.
