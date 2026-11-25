# 0007: Add Cookie, Redirect, and Security Header Helpers

## Status

Accepted. Security headers amended by [0008](./0008-secure-responses-and-requests-by-default.md): they are now on by default at the app level, and the middleware remains for groups.

## Context

Applications on Dram handle sessions, sign-in flows, and browser hardening with raw headers. A security review of Dram and dope found three recurring patterns:

- Reading a cookie meant Go interop with `http.ParseCookie` over every `Cookie` header. Setting one meant building an `http.Cookie` by hand, where forgetting `HttpOnly`, `SameSite`, or `Path` is silent. Go's `Cookie.String()` also drops invalid bytes with only a log line, so a bad value produced a different cookie than the one the application asked for.
- Redirects were a `Location` header plus a status. After a form `POST` the right status is 303, but 302 was common. Sign-in flows that redirect to a `?next=` parameter were open redirects unless each application rejected `//host`, `/\host`, schemes, and control characters itself.
- Defensive headers (`nosniff`, frame protection, `Referrer-Policy`, HSTS, CSP) had to be written per application, and a naive middleware would overwrite headers that handlers set on purpose.

The roadmap already listed a redirect helper.

## Decision

### Cookies

`request.cookie(name) Str?` returns the first cookie with that name, and `request.cookies() [Str: Str]` returns all of them, with the first value winning for a repeated name. Parsing is Go's lenient request parsing, so a malformed pair does not hide valid ones.

`response.set_cookie(name, value, max_age?, expires?, path?, domain?, secure?, http_only?, same_site?)` adds one `Set-Cookie` header per call, so cookies coexist through Dram's multi-value headers.

- Defaults are `Path=/`, `HttpOnly`, and `SameSite=Lax`, with no `Domain` and a browser-session lifetime. `SameSite` is the enum `dram::SameSite { lax, strict, none }`.
- `Secure` defaults to false. Development over plain http (Safari on `localhost`, or a LAN address from a phone) drops `Secure` cookies, which makes sign-in fail silently. Production applications pass `secure: true`, and the README examples do.
- Names must be HTTP tokens. Values must be RFC 6265 cookie-octets: printable ASCII except space, `"`, `,`, `;`, and `\`. Dram never quotes values. Applications encode arbitrary data, for example as hex or base64. Paths must start with `/` and contain no `;` or control characters. Go's `Cookie.Valid` checks domains and `Expires`.
- `max_age` must be positive. `SameSite=None` requires `secure: true`. `__Secure-` and `__Host-` names require `secure: true`, and `__Host-` also requires path `/` and no domain.
- Invalid input panics, like invalid header values in `Headers.set`. These are programmer errors. Inside a handler they become the recovery boundary's generic 500 and reach the panic observer, and no partial or rewritten cookie is sent. A `Void!Str` result was rejected because handlers return `Void`, so most call sites would `expect` anyway.

`response.clear_cookie(name, path?, domain?)` adds a `Set-Cookie` with an empty value, `Max-Age=0`, and an `Expires` of the Unix epoch, using the same defaults. `__Secure-` and `__Host-` names are cleared with `Secure`, as browsers require.

### Redirects

`response.redirect(location, status?, external?)` replaces the response with an empty-bodied redirect, like the other buffered helpers. It keeps headers already set, including `Set-Cookie`.

- The default status is 303 See Other. It is correct after a `POST` and equivalent to 302 for `GET`. Only 301, 302, 303, 307, and 308 are accepted.
- Redirects are local by default. `location` must pass `dram::local_path`, otherwise `redirect` panics. An off-site target needs `external: true`, which makes leaving the site explicit at the call site. Every location rejects control characters.
- `dram::local_path(target) Str?` returns `target` only when it is a same-origin absolute path. It must start with `/`, must not start with `//`, and must contain no backslash or control character. Browsers treat `\` as `/` and strip tabs and newlines, so `/\host` and `/\t/host` would otherwise leave the site. Applications validate untrusted targets with it rather than catching panics: `request.query("next").and_then(dram::local_path).or("/")`.

### Security headers

`dram::security_headers(frame?, referrer_policy?, csp?, hsts_max_age?, hsts_include_subdomains?) Middleware` is opt-in middleware. It runs the rest of the chain, then fills each header only if the response does not already have it. A handler's own value always wins.

| Header | Default | Option |
| --- | --- | --- |
| `X-Content-Type-Options` | `nosniff` | always |
| `X-Frame-Options` | `SAMEORIGIN` | `frame: Framing::deny` sends `DENY`; `Framing::allow` sends none |
| `Content-Security-Policy` | `frame-ancestors 'self'` | `csp` is sent as given, with the frame directive appended when it has no `frame-ancestors` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | `""` omits it |
| `Strict-Transport-Security` | not sent | `hsts_max_age` seconds, plus `includeSubDomains` on request |

Both frame headers are sent because browsers that support CSP prefer `frame-ancestors`, and `X-Frame-Options` still protects when a handler replaces the CSP. HSTS is opt-in. It only takes effect over HTTPS, and applications usually terminate TLS at a proxy Dram cannot see. A mistaken HSTS policy is hard to undo. Options are validated when the middleware is created.

When several instances run for one request, for example one global and one on a group, the innermost decides. It marks the response as handled, and outer instances add nothing. A group with `Framing::allow` therefore stays frameable under a global default.

It is middleware, not an app setting applied at delivery. Middleware composes: it can be registered globally or per group, for example with `Framing::allow` for an embeddable group. Because it fills headers after `next.run` returns, it covers route handlers, fallbacks, and short-circuiting inner middleware. It runs before Dram's delivery step, so its headers are on SSE responses before they commit (ADR 0004) and are kept by gzip and 304 negotiation (ADR 0006). It does not reach responses Dram creates outside the middleware chain: the 400 and 413 rejected before dispatch, and the generic 500 after a panic. Those have short plain-text bodies with no application content.

## Consequences

- Applications set and read cookies without Go interop, with safe attributes by default and loud failures for values that browsers would mangle.
- Sign-in flows get POST-redirect-GET and open-redirect protection by default. External redirects are visible in code review as `external: true`.
- Empty bodies are never gzip-compressed, even with `app.compress(min_bytes: 0)`, so redirects stay empty.
- A relative redirect such as `"page"` or `"?tab=2"` panics unless marked external. Applications use absolute paths.
- Cookies are not marked `Secure` unless requested. Deployments over HTTPS must pass `secure: true`.
- `security_headers` is opt-in. Frameworks built on Dram, such as dope, decide whether to enable it.
- Its placement relative to other middleware matters only for headers that other middleware sets after it fills them. Registering it first lets every inner layer set its own values.

## Related

- [0004: Define Response Delivery and Commitment](./0004-define-response-delivery-and-commitment.md)
- [0006: Negotiate Representations at Delivery](./0006-negotiate-representations-at-delivery.md)
- [RFC 6265bis: Cookies](https://datatracker.ietf.org/doc/draft-ietf-httpbis-rfc6265bis/)
- [RFC 9110 §15.4: Redirection](https://www.rfc-editor.org/rfc/rfc9110#section-15.4)
