# 0002: Establish Dram's Core HTTP Architecture

## Status

Accepted

## Context

Dram is a reusable HTTP server framework for Ard. Its starting point is the former `ard/http` standard-library API, especially its handler shape:

```ard
type Handler = fn(Request, mut Response)
```

That shape creates one response for a request and lets the handler complete it by mutation. It also makes an untouched or unmatched response naturally remain a 404. This is preferable to handlers returning `Response!Error`: expected application failures are HTTP responses and should not cascade through the server as language errors.

Gin informs the routing, grouping, and middleware model. Merjs informs the use of small framework-owned request and response abstractions. Dram also needs to account for large files, streaming, server-sent events, and WebSockets from the beginning rather than assuming every response is a buffered string.

Ard currently targets Go and supports direct Go package interop. Go's `net/http` package can provide the production HTTP runtime, while focused Go shims can adapt behavior that is not naturally expressible at the Ard boundary.

## Decision

### Package and runtime boundary

Build Dram as an external Ard package backed by Go's `net/http`, not as an Ard standard-library module. Keep the public API Ard-first and use small Go shims only where semantic adaptation is necessary.

### Handlers and context

Route handlers receive an immutable request and mutable response and do not return a value:

```ard
type Handler = fn(request: Request, response: mut Response)
```

As in Go's `net/http`, each `Request` owns a request-scoped `Context`. `request.context()` returns it, and `request.with_context(context)` returns a request carrying a derived context. The request carries the incoming Go `context.Context` interface directly and exposes its cancellation signal, error, deadline state, and request values through `dram/context`. It never contains the request itself, application dependencies, application state, middleware indexes, or continuation callbacks.

Applications provide dependencies by capturing them in handler and middleware closures. Context values follow Go's dynamic key/value model through the `dram/context` module. Keys must be comparable, should use application-owned types to avoid collisions, and values are retrieved as `Any?`. Applications should define typed accessor functions rather than spreading casts through handlers. Dram does not provide string-keyed storage.

Expected failures must be represented by completing the response with an appropriate HTTP status and body. Only server lifecycle operations, such as starting or stopping a listener, return `Result` values.

### Response lifecycle

Create one response for each request and initialize it as an empty 404. If no route matches or a matched handler does nothing, the final response remains a 404. Changing headers alone does not mark a response successful. Convenience methods such as `text`, `json`, `data`, and `redirect` set a complete response, including its status.

The response model must accommodate these delivery modes from the outset:

- buffered text or bytes;
- large files served without reading the entire file into memory;
- streaming responses;
- server-sent events;
- WebSocket upgrades.

Buffered responses are committed only after the middleware chain completes. File, stream, SSE, and WebSocket operations select a terminal delivery mode. Once headers or bytes are committed, the status and headers cannot be replaced.

### Routing and middleware

Routing is method-aware and supports path parameters, route groups, and middleware. Single-segment parameters use the former `ard/http` syntax and accessor:

```ard
app.get("/users/:id", fn(request, response) {
  let id = request.param("id").expect("matched route contains :id")
  response.text(200, id)
})
```

Static segments outrank parameter segments. Structurally equivalent parameter patterns are rejected for the same method, and repeated parameter names within one pattern are invalid. `request.param(name)` returns `Str?` so callers can distinguish a missing parameter from an empty value. Route registration occurs before serving; the route table is frozen once the server starts so request dispatch can remain concurrency-safe without route mutation locks.

Middleware has a distinct type and is the only code that receives a continuation:

```ard
type Middleware = fn(request: Request, response: mut Response, next: Next)
```

Middleware registration order is outermost first. It continues dispatch with `next.run(request, response)` and short-circuits by not invoking `Next`. Middleware may derive a context and propagate it with `next.run(request.with_context(derived), response)`. `Next` is opaque and one-shot. Route handlers never receive it, and there is no context-level `next` or `abort` API.

### Panic recovery

Recovery middleware catches unexpected panics in request execution. A focused Go shim captures both the panic message and stack trace.

Before a response is committed, recovery clears any partial response state and replaces it with a generic 500 response. Panic details are available for logging but are not sent to the client by default. After a stream or SSE response is committed, recovery logs the panic and closes the stream. After a WebSocket upgrade, recovery closes the socket with an internal-error indication.

### Listening

Expose a required port and optional host through Ard's nullable and named argument support:

```ard
fn listen(port: Int, host: Str?) Void!Str
```

The default host is `127.0.0.1`. External binding must be explicit:

```ard
app.listen(port: 8080)
app.listen(host: "0.0.0.0", port: 8080)
```

Validate ports as `0..65535` and form the Go listen address with `net.JoinHostPort` so hostnames, IPv4, and IPv6 are handled correctly.

## Consequences

- Handlers have a consistent imperative model and always communicate application outcomes through HTTP responses.
- An untouched response provides simple, predictable 404 behavior.
- Context remains immutable request-scoped propagation data owned by `Request`; application dependencies are explicit closure captures rather than framework state generics.
- Request values follow Go's `Any` model, with comparable application-owned key types and typed application accessor functions.
- Buffering ordinary responses enables complete recovery, deterministic finalization, and straightforward in-memory testing.
- Streaming and upgraded connections require explicit commitment semantics; a panic cannot become a new HTTP 500 after commitment.
- Large files can use Go's efficient file-serving facilities instead of consuming memory proportional to file size.
- The router becomes immutable during serving, simplifying concurrent dispatch.
- Dram will contain a small Go adaptation layer for panic capture and may require a Go WebSocket dependency.
- Exact request, header, body, stream, SSE, and WebSocket helper shapes may evolve while preserving these architectural constraints.

## Related

- [0001: Record Architecture Decisions](./0001-record-architecture-decisions.md)
- [Former `ard/http` module](https://github.com/akonwi/ard/blob/4cb530bc32de79b4ba1380bf810b1c09a4953cad/compiler/std_lib/http.ard)
- [Gin](https://github.com/gin-gonic/gin)
- [merjs](https://github.com/justrach/merjs)
