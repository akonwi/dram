# 0003: Use Opaque Middleware Continuations

## Status

Accepted

## Context

ADR 0002 originally used one generic handler shape for middleware and routes and placed dispatch state on `Context`. The feasibility prototype demonstrated indexed dispatch, but it also mixed unrelated responsibilities: request-scoped propagation, application state, and middleware control.

A request may carry a context derived with values or deadlines and be passed into downstream work. Middleware control is different: only middleware may continue the chain, route handlers must be terminal, and application code must not reset the chain index or replay downstream handlers.

Ard does not currently provide field-level visibility. Opaque framework capabilities therefore need private concrete storage boxed behind `Any`, exposing behavior only through public methods.

## Decision

Separate route handlers from middleware:

```ard
type Handler = fn(request: Request, response: mut Response)

type Middleware = fn(
  request: Request,
  response: mut Response,
  next: Next,
)
```

`Request` owns an immutable request-scoped `Context`. Neither type has a middleware chain, index, continuation, abort flag, or application dependency state.

`Next` is an opaque, one-shot capability. Middleware continues synchronously with:

```ard
next.run(request, response)
```

A middleware short-circuits by completing the response and not calling `Next`. There is no `abort()` API. Calling the same `Next` more than once is a no-op and cannot replay downstream middleware or the route handler.

Each middleware invocation receives a continuation for exactly the remaining chain. The continuation accepts a `Request`, so middleware may derive a context and explicitly propagate it with `request.with_context(derived)`. Route handlers receive no continuation and cannot advance middleware.

Middleware and route snapshots are immutable once the server begins listening. Live `Request`, `Context`, `Response`, and `Next` values remain request-scoped and synchronous; they must not be retained for detached work.

## Consequences

- Route handlers cannot continue or replay middleware.
- Middleware short-circuiting is represented by omission rather than mutable abort state.
- Derived contexts propagate only when explicitly passed to `Next.run`.
- Middleware continuation internals remain inaccessible despite Ard's lack of private fields because private storage is boxed behind opaque `Any`.
- A small continuation allocation occurs for each middleware invocation.
- Applications must copy data needed by independently spawned work and must not retain request-owned capabilities.

## Related

- [0002: Establish Dram's Core HTTP Architecture](./0002-establish-core-http-architecture.md)
- [0004: Define Response Delivery and Commitment](./0004-define-response-delivery-and-commitment.md)
