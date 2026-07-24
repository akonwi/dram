# Dram

Dram is an HTTP server framework for [Ard](https://github.com/akonwi/ard).
Current main requires Ard 0.30.0 or newer so middleware can be registered with the `use` method.

## Current package

The package root provides Dram's HTTP foundation:

- immutable requests carrying Go-compatible contexts and lazily decoded query parameters;
- distinct route handlers and one-shot middleware `Next` capabilities;
- static, `:name`, and final-segment `*name` routes, nested route groups, and customizable 404/405 responses;
- in-memory `App.handle(Request)` dispatch;
- buffered text and byte responses plus deferred server-sent event streams;
- case-insensitive, multi-value headers;
- bounded request bodies with a 1 MiB default;
- `net/http.Server` integration through `App.listen(port, host?)` or a standard `http.Handler` snapshot.

```ard
use dram

struct Greeter {
  greeting: Str,
}

fn main() {
  let greeter = Greeter{greeting: "Hello"}
  mut app = dram::App::new()
  app.use(fn(request: dram::Request, response: mut dram::Response, next: dram::Next) {
    response.header("X-Powered-By", "Dram")
    next.run(request, response)
  })
  app.get("/", fn(request: dram::Request, response: mut dram::Response) {
    response.text(200, "{greeter.greeting} from Dram")
  })

  app.listen(port: 8080).expect("Failed to start server")
}
```

Application dependencies belong in closure captures, not request contexts. Middleware short-circuits by completing the response without calling `Next`. Route handlers never receive `Next`.

The complete path-dependency example is under [`examples/hello/`](./examples/hello/).

## Serving

`App` implements Go's standard `http.Handler` interface. `listen` is the simple blocking entry point; applications that need custom timeouts, asynchronous startup, or graceful shutdown can use the app with their own `http.Server`:

```ard
use go:net/http

mut server = http::Server{
  Addr: "0.0.0.0:8080",
  Handler: app,
}
server.ListenAndServe()
```

Assign `app` by value as shown to capture its configured state. An explicit `mut app` conversion creates a live handler reference instead; applications using that form must synchronize every registration change with request dispatch.

## Routing

Single-segment path parameters use `:name` patterns:

```ard
app.get("/users/:id", fn(request, response) {
  let id = request.param("id").expect("matched route contains :id")
  response.text(200, id)
})
```

Static segments outrank parameters. Equivalent patterns such as `/users/:id` and `/users/:name` are rejected for the same method. `request.param(name)` returns `Str?`, allowing handlers and middleware to distinguish a missing parameter from an empty value.

A final `*name` parameter captures the remaining path using Gin-compatible semantics:

```ard
app.get("/files/*path", fn(request, response) {
  response.text(200, request.param("path").or("/"))
})
```

The captured value includes its leading slash, so `/files/images/logo.png` produces `"/images/logo.png"`. `/files/*path` matches `/files/` with `"/"`, but does not match `/files`. Catch-all routes reject overlapping same-method static, parameter, and catch-all routes.

Groups compose static path prefixes and middleware:

```ard
mut api = app.group("/api")
api.use(authenticate)
api.get("/users/:id", show_user)

mut admin = api.group("/admin")
admin.use(require_admin)
admin.delete("/users/:id", delete_user)
```

Group prefixes cannot contain parameters. Parent middleware runs before child middleware, and newly added group middleware applies only to subsequently registered routes. A child snapshots its parent's middleware when the child is created, so later parent additions do not affect that existing child. Group middleware does not run for 404 or 405 responses.

Application-level fallback handlers customize unmatched paths and method mismatches:

```ard
app.not_found(fn(request, response) {
  response.text(404, "Page not found")
})

app.method_not_allowed(fn(request, response) {
  response.text(405, "Method not allowed")
})
```

Global middleware wraps fallback handlers. Group middleware does not run because no group route was selected. The method-not-allowed handler receives a response already set to 405 with its generated `Allow` header.

## Query parameters

Requests retain the raw query string and decode it only when an accessor is called:

```ard
let search = request.query("q")
let tags = request.query_list("tag")
```

`query(name)` returns the first value as `Str?`; `query_list(name)` returns every repeated value. Missing names return `None` or an empty list, while a present empty value such as `?q=` returns `Some("")`. Decoding follows Go's `net/url` behavior, including percent decoding and converting `+` to a space.

`Request::new` accepts a request target such as `/search?q=ard`, separates its decoded path for routing, retains the raw query for lazy decoding, and uses a background context:

```ard
let request = dram::Request::new("GET", "/search?q=ard")
```

Callers that need custom headers, bodies, or initial contexts may instantiate `Request` directly. Initialize `path_params` as empty; the router replaces it when selecting a parameterized route.

## Context API

Like Go's `net/http`, each `Request` owns a Go `context.Context` interface value:

- `request.context() context::Context`
- `request.with_context(context) Request`
- `context::done(context) Receiver<Void>`
- `context::err(context) Str?`
- `context::deadline(context) time::Time?`
- `context::with_value(parent, key, value) context::Context`
- `context::value(context, key) Any?`

Requests created with `Request::new` use `context::background()`. Directly instantiated requests use their supplied context, while network requests wrap `http.Request.Context()`.

Context values follow Go's dynamic key/value model. Keys must be comparable and should use application-owned types rather than strings. Applications should provide typed accessor functions that perform the `Any` cast in one place:

```ard
use ard/unsafe
use dram/context

private struct RequestIdKey {
  marker: Int,
}

let request_id_key = RequestIdKey{marker: 0}
let derived = context::with_value(request.context(), request_id_key, "req-123")
let id = match context::value(derived, request_id_key) {
  boxed => unsafe::cast<Str>(boxed),
  _ => Maybe::new(),
}
```

## Responses and headers

`response.header(name, value)` replaces a header, while `response.add_header(name, value)` preserves repeated values such as `Set-Cookie`. `response.bytes` uses `application/octet-stream`; use `response.data(status, content_type, bytes)` for an explicit media type.

`response.json(status, value)` buffers compact JSON with `application/json; charset=utf-8`. Encoding completes before the response changes; unsupported values panic and are replaced by the recovery boundary's generic 500 response. Pre-encoded JSON should use `response.data` to avoid encoding it as a JSON string.

### Server-sent events

`response.sse(handler)` selects a deferred SSE delivery mode. The callback starts only after route and middleware dispatch completes, so outer middleware has a final opportunity to set headers. Dram sets status 200 and manages `Content-Type: text/event-stream`, `Cache-Control: no-cache`, and `X-Content-Type-Options: nosniff` without adding a content length.

```ard
app.get(
  "/events",
  fn(request, response) {
    response.sse(
      fn(events) {
        while not events.cancelled() {
          if not events.send(data: "hello", event: "message", id: "42", retry_ms: 1500) {
            break
          }
        }
      },
    )
  },
)
```

`events.send` formats multiline data, optional event names, IDs, and non-negative retry milliseconds, then flushes the event. `events.comment(text)` writes and flushes an SSE comment for application-managed heartbeats. Both return `false` after cancellation or a transport failure. Event names and IDs reject CR, LF, and NUL characters.

The first event or comment commits the status and headers. A panic before commitment becomes Dram's generic 500 response; a panic after commitment aborts the stream without replacing output already sent. A callback that returns without sending still completes an empty SSE response. `HEAD` sends the corresponding headers without running the callback. Selecting a buffered response helper after `sse` replaces the stream.

`App.handle` performs in-memory dispatch but does not execute deferred delivery callbacks. Exercise SSE behavior through `App`'s standard `http.Handler` implementation, as Dram's tests do with `net/http/httptest`.

Through Go's `http.ResponseController`, Dram clears the ordinary response write deadline before invoking an SSE callback and applies a 30-second deadline around each event write and flush. Deadline control is best-effort for custom response-writer middleware; wrappers should implement Go's `Unwrap() http.ResponseWriter` convention. Applications still own subscription state, replay, event persistence, authorization, and heartbeat policy.

## Concurrency

`net/http` runs handlers concurrently. Each request carries its own immutable context and receives a mutable `Response`, but captured closure data may be shared by every request. Application code must synchronize shared maps, lists, mutable references, database clients, counters, and other dependencies. Request contexts, responses, `Next`, and `EventStream` capabilities are synchronous and request-scoped; they must not be retained or used by detached work after their callback returns.

Complete route and middleware registration before calling `listen` or assigning the app by value as an `http.Handler`. Both capture the configured application value for concurrent reads, and later registration changes do not affect that running server. An explicit `mut app` handler conversion shares live configuration and must not be mutated concurrently with request dispatch. `App.handle` likewise reads the application's current configuration and must not run concurrently with registration changes.

## Development

Run the root checks below. The HTTP smoke test also requires Bun:

```sh
ard format dram.ard context.ard
ard check dram.ard
ard test
./test/api_visibility.sh
./test/http_smoke.sh
ard build examples/hello/main.ard --out /tmp/dram-hello
```

## Current limits

Routing supports static paths, single-segment and catch-all parameters, and static-prefix route groups. Ordinary responses and all request bodies are buffered; oversized bodies return 413 and other body decoding failures return 400. SSE is the only streaming delivery mode. Informational statuses and successful CONNECT responses are not supported as final buffered responses. Panic recovery uses Ard's `unsafe` boundary, returns a generic 500 before commitment, and does not currently capture or log a stack. Generic streams, files, WebSockets, automatic SSE heartbeats, and detached request contexts are not exposed yet.

Architecture decisions live in [`docs/`](./docs/).
