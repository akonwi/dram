# 0005: Add a Server Lifecycle and Observers

## Status

Accepted

## Context

`App.listen` wrapped `http.Server.ListenAndServe` and returned only when the server failed. A process stopped by SIGTERM, as container platforms and process supervisors do on every deploy, dropped in-flight requests mid-response. Applications that wanted graceful shutdown had to build their own `http.Server` around the app, and then nothing told their event streams to finish: Go's `Server.Shutdown` waits for active handlers but never cancels their contexts, so every open SSE response held shutdown until its deadline.

The recovery boundary turned panics into generic 500 responses and discarded them. ADR 0002 and ADR 0004 require panic messages and stacks to be available for logging while staying out of client responses, but neither the message nor the stack reached any observer, so production failures were invisible.

Applications also had no framework-level place to observe completed requests. Middleware cannot do this reliably: an inner middleware does not see responses produced by short-circuiting outer middleware, and no middleware sees when a deferred SSE stream ends or how many bytes it wrote.

## Decision

### Server handle

`App.bind(port, host?) Server!Str` validates the port, opens the listener immediately, and returns a `Server` serving an isolated snapshot of the app, as `listen` already did. Binding eagerly reports address errors before serving begins and makes the bound address available for port 0.

```ard
let server = try app.bind(port: 0)
server.address() // "127.0.0.1:49152"
server.port()    // 49152
server.set_timeouts(write_ms: 60_000)
server.serve()   // blocks until the server stops
```

`Server` is opaque. `serve`, `shutdown`, and `close` may be called from different tasks:

- `serve() Void!Str` accepts connections until the server stops. It returns `ok` only after a graceful shutdown has finished, not when the listener closes, so a program that exits after `serve` returns never cuts off draining requests.
- `shutdown(timeout_ms?) Void!Str` stops gracefully. It closes the listener, signals draining, and waits up to `timeout_ms` (default 10 seconds) for in-flight requests. Connections still open at the deadline are closed and the call returns an error, which `serve` also returns. Later calls wait for the first and report the same outcome.
- `close() Void!Str` stops immediately.
- Stopping a server before `serve` releases its listener, and a later `serve` returns at once.
- `set_timeouts(read_header_ms?, read_ms?, write_ms?, idle_ms?)` replaces the server timeouts. It panics once serving or stopping has begun, because Go reads the timeouts concurrently from then on. The defaults are unchanged: 5s read header, 30s read, 30s write, and 120s idle.

The default host remains `127.0.0.1`. External binding stays explicit, as ADR 0002 requires.

### Draining

Each server owns a drain context that `shutdown` and `close` cancel. Dram stores it as a private value in the server's base context, so every request served by a `Server` can reach it while its own context stays independent. In-flight buffered requests are never cancelled by draining. They run to completion within the shutdown timeout.

- `request.draining() Bool` reports whether the accepting server has begun shutting down. It is false for in-memory requests and for apps served by an application-owned `http.Server`.
- Event streams end on draining. Dram derives each stream's context from the request context and cancels it when the transport closes or the server drains. `stream.cancelled()` becomes true and sends return `false`. The new `stream.done() Receiver<Void>` closes at the same moment, so callbacks that wait for application events can `select` on it instead of polling.

A client whose stream ends this way sees an ordinary end of stream. `EventSource` reconnects, which during a rolling deploy reaches the replacement process.

### Signals

`App.listen(port, host?)` now binds, serves, and on SIGINT or SIGTERM performs `shutdown()` with the default timeout. A second signal calls `close()`. `listen` returns `ok` after a graceful stop. Its signature is unchanged. Applications that need their own signal policy, log lines, or timeouts use `bind`, `serve`, and `shutdown` directly.

### Panic observer

Recovery now records the panic message and the goroutine stack at the panic site. The stack is captured by a deferred call inside the guarded function, which runs while the panic is still unwinding. The enclosing `unsafe` block then recovers as before, so no Go shim is needed.

```ard
struct Panic { method: Str, path: Str, message: Str, stack: Str }
app.on_panic(fn(report: dram::Panic) { ... })
```

Without an observer, Dram writes the method, path, message, and stack to stderr. The observer is called for panics in middleware, handlers, and fallbacks (including `App.handle`) and in SSE callbacks before and after commitment. Client behavior is unchanged: a generic 500 before commitment, an aborted stream after it.

### Completion observer

```ard
struct Completion { method: Str, path: Str, status: Int, bytes: Int, duration: time::Duration }
app.on_complete(fn(completion: dram::Completion) { ... })
```

The observer runs after each HTTP request is delivered, including requests rejected before dispatch (413, 400) and SSE streams, which report when the stream ends with the bytes written. `status` is what reached the client, or 0 when nothing was written. `bytes` counts body bytes from writes that succeeded, so a write that fails partway is not counted. The report is deferred, so streams aborted by a post-commitment panic are reported too. `App.handle` does not call it because nothing is delivered. Dram itself does not write access logs. Formatting and destinations belong to applications.

## Consequences

- A Dram app stopped by SIGTERM finishes in-flight requests and closes event streams instead of dropping them.
- Applications can embed a server in tests or supervisors with port 0, `serve`, and `shutdown`, without constructing an `http.Server`.
- Event-stream callbacks should watch `done()` or `cancelled()`. Callbacks that block without either hold shutdown until its timeout.
- Panics are visible by default on stderr and can be routed elsewhere. Panic details still never reach clients.
- Access logs and metrics have one hook that sees every delivered request, including streams and short-circuited middleware.
- Apps served by an application-owned `http.Server` do not get draining or SSE shutdown signals. They keep observers and recovery.
- `listen` gains signal handling. Programs that relied on SIGTERM killing the process immediately now get a bounded graceful exit.

## Related

- [0002: Establish Dram's Core HTTP Architecture](./0002-establish-core-http-architecture.md)
- [0004: Define Response Delivery and Commitment](./0004-define-response-delivery-and-commitment.md)
- [Go `http.Server.Shutdown`](https://pkg.go.dev/net/http#Server.Shutdown)
