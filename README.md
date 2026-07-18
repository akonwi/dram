# Dram

Dram is an HTTP server framework for [Ard](https://github.com/akonwi/ard).

## Current package

The package root provides the first buffered HTTP slice:

- immutable requests carrying Go-compatible contexts and lazily decoded query parameters;
- distinct route handlers and one-shot middleware `Next` capabilities;
- static, `:name`, and final-segment `*name` routes, nested route groups, and method-aware 404/405 responses;
- in-memory `App.handle(Request)` dispatch;
- buffered text and byte responses with case-insensitive, multi-value headers;
- bounded request bodies with a 1 MiB default;
- `net/http.Server` serving with defensive timeouts through `App.listen(port, host?)`.

```ard
use dram

struct Greeter {
  greeting: Str,
}

fn main() {
  let greeter = Greeter{greeting: "Hello"}
  mut app = dram::App::new()
  app.use_middleware(fn(request: dram::Request, response: mut dram::Response, next: dram::Next) {
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
api.use_middleware(authenticate)
api.get("/users/:id", show_user)

mut admin = api.group("/admin")
admin.use_middleware(require_admin)
admin.delete("/users/:id", delete_user)
```

Group prefixes cannot contain parameters. Parent middleware runs before child middleware, and newly added group middleware applies only to subsequently registered routes. A child snapshots its parent's middleware when the child is created, so later parent additions do not affect that existing child. Group middleware does not run for 404 or 405 responses.

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

## Concurrency

`net/http` runs handlers concurrently. Each request carries its own immutable context and receives a mutable `Response`, but captured closure data may be shared by every request. Application code must synchronize shared maps, lists, mutable references, database clients, counters, and other dependencies. Request contexts, responses, and `Next` capabilities are synchronous and must not be retained or used by detached work after the handler returns.

Complete route and middleware registration before calling `listen`; the server captures an immutable configuration snapshot for concurrent reads. Later registration changes do not affect that running server. Do not mutate registration concurrently with `App.handle`, which reads the application's current configuration.

## Development

The independent projects under `examples/` have their own manifests, so run root-package tests against the root test directory explicitly:

```sh
ard-dev format dram.ard context.ard
ard-dev check dram.ard
ard-dev test test
./test/api_visibility.sh
./test/http_smoke.sh
ard-dev build examples/hello/main.ard --out /tmp/dram-hello
```

The compiler probe under [`examples/feasibility/`](./examples/feasibility/) remains isolated from the root package.

## Current limits

Routing supports static paths, single-segment and catch-all parameters, and static-prefix route groups. Responses and request bodies are fully buffered, oversized bodies return 413, and other body decoding failures return 400. Informational statuses and successful CONNECT responses are not supported as final buffered responses. Panic recovery uses Ard's `unsafe` boundary, returns a generic 500, and does not currently capture or log a stack. Streaming, files, SSE, WebSockets, and detached request contexts are intentionally not exposed yet.

Architecture decisions live in [`docs/`](./docs/).
