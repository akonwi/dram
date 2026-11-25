# 0008: Secure Responses and Requests by Default

## Status

Accepted. Amends the security header decision in [0007](./0007-add-cookie-redirect-and-security-header-helpers.md).

## Context

ADR 0007 added `dram::security_headers()` as opt-in middleware. Two problems remained.

- **Opt-in protection is missing protection.** Most applications never add it. Frameworks built on Dram, such as dope, could register it on the application's behalf. But middleware registered last runs inside the application's own middleware, so it misses responses that application middleware completes without calling `next`, such as authentication redirects and 401s. It never reaches Dram's own 400, 413, and 500 responses. An application that registered its own global policy was silently overridden by the framework's inner one.
- **Nothing guarded state-changing requests against cross-site request forgery (CSRF).** dope guarded its generated RPC and, when the author remembered, Datastar actions. Ordinary `POST` routes, including the login and logout forms in its documentation, had no guard, and a plain HTML form cannot send the headers those guards check.

We compared other frameworks. Full-stack frameworks enable both protections by default (Rails, Django, Phoenix, and Sinatra for CSRF; Rails, Django, Phoenix, Sinatra, and Rocket for headers). Minimal routers leave them to the application. CSRF defenses are moving from synchronizer tokens to fetch metadata: Rails 8.2 makes `Sec-Fetch-Site` the default for new applications, and Go 1.25 added `http.CrossOriginProtection`. Header-based checks need no sessions, form helpers, or client changes, which suits Dram, which has none of them. The common customization surface is a list of trusted origins, a per-route exemption, and an opt-out.

## Decision

Dram is secure by default. Both protections are on for every `App` and are configured through the app, with group-level scoping.

### Security headers

The app has a security header policy, on by default with the defaults from ADR 0007: `nosniff`, `X-Frame-Options: SAMEORIGIN` with `frame-ancestors 'self'`, and `Referrer-Policy: strict-origin-when-cross-origin`. HSTS and a content CSP are not set by default.

- **Applied at delivery.** The policy is applied after the middleware chain and recovery, before representation negotiation (ADR 0006), so it covers every response: handlers, fallbacks, short-circuits, event streams, 304s, gzip responses, and Dram's own 400, 413, and 500 responses. Each header is filled only if the response doesn't have it.
- **Configured with `app.security_headers(...)`.** It takes the middleware's options, and `enabled: false` turns the policy off.
- **The middleware stays for scoping.** A response handled by a `dram::security_headers(...)` middleware is left to that middleware's policy, and the innermost middleware decides, as before. A group can therefore have a different policy, for example `Framing::allow` for embeddable pages.

### Cross-origin request protection

Every app rejects cross-origin browser requests with unsafe methods, following Go's `http.CrossOriginProtection`:

1. `GET`, `HEAD`, and `OPTIONS` pass.
2. When `Sec-Fetch-Site` is present: `same-origin` and `none` pass, and anything else (`cross-site`, `same-site`, or unknown) is rejected unless `Origin` is trusted. Rejecting `same-site` keeps a compromised or user-content subdomain from posting to the app. Applications that span subdomains trust those origins explicitly.
3. Without `Sec-Fetch-Site`, a request whose `Origin` host equals the request host passes, and other origins are rejected unless trusted.
4. A request with neither header passes. It is not from a browser, and CSRF requires a browser's ambient credentials. Every major browser has sent `Sec-Fetch-Site` since 2023.

The check runs after route matching and before any middleware, inside the recovery boundary. A rejection is `403 Forbidden: cross-origin request`, with the app's security headers. Middleware cannot skip the check, and middleware does not run for rejected requests. `App.handle` applies it too.

`Request` gains `host: Str?`, the `Host` the client addressed, because Go removes `Host` from the header map. It is set for network requests and none for `Request::new`. The field is optional, so existing direct `Request` literals still compile.

Customization:

- `app.cross_origin_protection(trusted_origins: [...])` lists origins (`scheme://host[:port]`, no path) allowed to make cross-origin requests, such as an identity provider or another application. Invalid origins panic at configuration.
- `group.allow_cross_origin()` exempts routes registered on the group afterwards, and groups created from it afterwards, for endpoints such as payment callbacks that receive cross-site form posts. This follows Dram's existing group semantics for middleware.
- `app.cross_origin_protection(enabled: false)` turns the check off.

There is no custom rejection handler yet. Applications that need a different response can disable the check and run their own.

## Consequences

- Every Dram application sends defensive headers and resists CSRF without configuration. Frameworks on Dram no longer need to register either protection.
- Existing applications change behavior. Responses gain headers, which handlers can override. Cross-origin browser `POST`, `PUT`, `PATCH`, and `DELETE` requests that used to succeed now get 403 until their origin is trusted or their routes are exempted. Requests from non-browser clients are unaffected.
- Behind a proxy that rewrites `Host`, browsers without `Sec-Fetch-Site` fail closed unless their origin is trusted.
- The middleware from ADR 0007 keeps its signature and behavior. It is now for scoping rather than the primary way to enable headers.
- Safe methods must not change state; the check does not cover them.

## Related

- [0006: Negotiate Representations at Delivery](./0006-negotiate-representations-at-delivery.md)
- [0007: Add Cookie, Redirect, and Security Header Helpers](./0007-add-cookie-redirect-and-security-header-helpers.md)
- [Go `http.CrossOriginProtection`](https://pkg.go.dev/net/http#CrossOriginProtection)
- [Fetch Metadata Request Headers](https://www.w3.org/TR/fetch-metadata/)
