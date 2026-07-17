# 0004: Define Response Delivery and Commitment

## Status

Accepted

## Context

Dram handlers and middleware share one mutable `Response`. The response begins as an empty 404, and normal application failures are represented by completing that response rather than returning errors from handlers.

A buffered text response is sufficient for the feasibility prototype, but the framework must also support binary bodies, large files, streaming, server-sent events, and WebSocket upgrades. These modes differ in when headers become immutable, whether recovery can replace a partial response, and how transport failures are reported.

Without an explicit commitment model, middleware and recovery could attempt to change a status after bytes have reached the client, or streaming APIs could accidentally retain the ordinary request context beyond its valid lifetime.

## Decision

### Response state

Create one mutable response per request. Its initial state is an empty buffered response with status 404.

A response has one active delivery mode:

- buffered text or bytes;
- file;
- stream;
- server-sent events;
- WebSocket upgrade.

Before commitment, response helpers replace the current status, headers, and delivery mode as appropriate. This permits recovery or outer middleware to replace work performed by downstream handlers. Selecting a delivery mode does not itself write to the network.

Expose high-level helpers along these lines:

```ard
response.text(200, "Hello")
response.json(200, json)
response.data(200, "image/png", bytes)
response.file(path)
response.stream(200, "text/csv", write_csv)
response.sse(send_events)
response.websocket(handle_socket)
```

The exact callback and helper signatures may evolve, but they must preserve the commitment rules in this ADR.

### Implementation sequence

The first implementation may support only buffered text and byte responses. It must still place response finalization behind an internal delivery boundary so adding files, streams, and SSE does not require changing the handler signature or replacing the mutable response model.

Do not publish placeholder file, stream, SSE, or WebSocket helpers before their behavior is implemented. Add those capabilities incrementally while preserving the response modes and commitment semantics defined here.

### Commitment

A response is committed when its status and headers have been sent or when an HTTP upgrade succeeds. After commitment:

- status and headers are immutable;
- the delivery mode cannot be replaced;
- recovery cannot turn the response into a new HTTP 500;
- transport failures terminate the active delivery operation rather than becoming a handler result.

The framework may expose a read-only `committed()` query for middleware and diagnostics. Ordinary handlers should not need to manage commitment directly.

### Buffered responses

Buffered text and bytes are held until the middleware chain and recovery boundary complete. The framework then writes status, headers, and body together.

This mode supports complete replacement by recovery and deterministic in-memory testing. Text, JSON, HTML, and small binary payloads use this path.

For `HEAD`, the framework emits the same status and headers that `GET` would produce but suppresses the body. Statuses that forbid bodies, including 204 and 304, also suppress body bytes during finalization.

### Files

A file response stores a path or file handle instead of reading the entire file into memory. The server opens and validates the file before commitment, then delegates range requests, modification checks, content length, and efficient transfer to Go's HTTP facilities where practical.

A missing file becomes a 404 if the response is still uncommitted. Unexpected file access failures become a generic 500 and are logged. File paths supplied by applications are trusted application inputs; any future static-directory helper must separately prevent path traversal.

### Streams

A stream response stores a callback and invokes it only after ordinary middleware has completed. Headers remain uncommitted until the stream first writes or flushes, allowing a panic before the first output to become a clean 500.

The stream API reports whether the connection remains usable and exposes cancellation. A client disconnect ends the stream without cascading an error through the HTTP handler.

Conceptually:

```ard
response.stream(
  200,
  "text/csv",
  fn(stream: mut Stream) {
    if not stream.write("name,email\n") {
      // The client disconnected.
    }
  },
)
```

After the first successful write or flush, a panic is logged and the connection is closed because the status can no longer be replaced.

### Server-sent events

SSE is a specialized streaming mode with framework-managed headers, event formatting, flushing, cancellation, and optional heartbeat comments.

Conceptually:

```ard
response.sse(
  fn(events: mut EventStream) {
    while not events.cancelled() {
      if not events.send(Event{event: "message", data: "hello"}) {
        break
      }
    }
  },
)
```

Event IDs and retry values must be supported. Internal panic details are never sent as SSE data by default.

### WebSockets

A WebSocket response stores an upgrade callback. Commitment occurs only after a successful handshake. A rejected or failed upgrade may still become an ordinary HTTP response while uncommitted.

After upgrade, HTTP response mutation is no longer available. A recovered panic is logged, an internal-error close indication is sent when possible, and the socket is closed.

The WebSocket implementation may use a focused Go dependency because `net/http` does not implement the protocol. Dependency selection is a separate decision.

### Headers and middleware

Headers remain mutable until commitment. The header API must support both replacement and repeated values:

```ard
response.headers.set("content-type", "application/json")
response.headers.add("set-cookie", cookie)
```

Outer middleware may inspect or replace an uncommitted downstream response after `next.run(request, response)` returns. Route handlers do not receive `Next`. Streaming callbacks do not begin until middleware has finished.

### Recovery behavior

Recovery depends on commitment state:

| Delivery state | Recovery behavior |
| --- | --- |
| Buffered or unopened file | Clear partial state and produce a generic 500 |
| Stream or SSE before first write | Produce a generic 500 |
| Stream or SSE after commitment | Log and close the stream |
| WebSocket before successful upgrade | Produce a generic 500 |
| WebSocket after upgrade | Log, send an internal-error close indication when possible, and close |

Panic messages and stack traces are for logging and observability only. They are not included in client responses by default.

### Callback lifetime

Delivery callbacks run within the connection's request goroutine unless a later implementation explicitly documents otherwise. They receive dedicated stream, event, or socket capabilities rather than permission to continue ordinary middleware dispatch.

The live request, its context, and the mutable response remain request-scoped. Applications are responsible for copying application data needed by independently spawned asynchronous work.

### Accepted review outcomes

- Begin implementation with simple buffered responses while preserving an extensible delivery boundary.
- Pre-commit response helpers may replace an earlier delivery mode rather than panicking.
- Stream and SSE write operations report connection usability with `Bool` instead of exposing transport errors as handler `Result` values.
- Missing application-selected files become 404, while other pre-commit file failures become 500.
- WebSocket dependency selection remains a separate ADR.

## Consequences

- Ordinary responses remain simple, buffered, recoverable, and easy to test.
- Large files do not require memory proportional to file size.
- Middleware has a clear final opportunity to modify responses before delivery begins.
- Streaming and upgraded connections have weaker recovery guarantees after commitment.
- The implementation must track response mode and commitment explicitly.
- Header mutation methods must reject or panic after commitment rather than silently doing nothing.
- Streaming, SSE, and WebSocket APIs require dedicated capability types and cancellation handling.
- In-memory tests can inspect buffered responses directly, while delivery-mode tests require a recorder capable of simulating commitment, flushing, disconnects, and upgrades.
- WebSocket support may add an external Go dependency even though the core HTTP server uses only the Go standard library.

## Related

- [0002: Establish Dram's Core HTTP Architecture](./0002-establish-core-http-architecture.md)
- [0003: Use Indexed Middleware Dispatch](./0003-use-indexed-middleware-dispatch.md)
- [Go `net/http`](https://pkg.go.dev/net/http)
