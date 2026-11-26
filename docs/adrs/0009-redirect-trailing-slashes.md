# 0009: Redirect Trailing Slashes

## Status

Accepted. Amends the routing decision in [0002](./0002-establish-core-http-architecture.md).

## Context

Dram matches paths exactly, including a trailing slash. `/about` and `/about/` are different routes, and a request for the form that isn't registered gets a 404. A group `/blog` with a `/` route registers `/blog/`, so `/blog` is a 404. A catch-all `/files/*path` matches `/files/` but not `/files`.

Applications want one canonical URL per page, with the other form redirecting to it. Static hosts such as GitHub Pages redirect `/x` to `/x/` for directories, and static exports such as dope's write `/x/` as `x/index.html`. Without help from the router, applications registered both forms by hand. That doubles the routes, and a page served at two URLs splits caches and search ranking.

Frameworks handle this in four ways:

- **Redirect to the registered form**, on by default: Gin and httprouter (301 for `GET`, 307 for other methods), Django's `APPEND_SLASH` (301, adding the slash only), and Go 1.22's `ServeMux`, which redirects `/x` to a registered `/x/` subtree with a 301.
- **Force one form for every path** with middleware: chi's `RedirectSlashes` and `StripSlashes`, Echo's `AddTrailingSlash` and `RemoveTrailingSlash`, and Hono's `trimTrailingSlash` and `appendTrailingSlash`. These ignore which form was registered. Echo (CVE-2022-40083) and chi have both had open-redirect advisories in them: a request for `//evil.example/` was redirected to `//evil.example`, which browsers treat as another host.
- **Serve both forms with one handler**: Fastify's `ignoreTrailingSlash`, Express's default non-strict routing, and Rails. There is no redirect, so every page has two URLs.
- **One site-wide canonical form** with 308 redirects: Next.js, SvelteKit, and Astro.

## Decision

Dram redirects a request to the other trailing-slash form of its path when the request would otherwise get a 404 and that form has a route. It is on by default.

```ard
app.redirect_trailing_slash(enabled: false)  // exact matching only
app.redirect_trailing_slash()                // back on
```

### When a request redirects

A request redirects when:

1. no route matches its path for any method, so it would get a 404; and
2. its path with the trailing slash added or removed has a route for the request's method, with `HEAD` falling back to `GET` as usual.

Each route's registered form is canonical, so one application can use `/posts/` for pages and `/api/posts` for an API. There is no site-wide form to choose.

- **Exact matches win.** A path registered in both forms is served in both, and nothing redirects. A path with routes only for other methods still gets its 405, not a redirect.
- **Params, catch-alls, and groups need nothing special.** `/users/:id` redirects `/users/42/` to `/users/42`. `/files/*path` redirects `/files` to `/files/`. A group's `/` route at `/blog/` redirects `/blog`. An empty segment still doesn't match a parameter, so `/users/` stays a 404 unless `/users` is a route.
- **The root never redirects.** `/` has no form without the slash.
- **Targets stay on the site.** The target path must pass `dram::local_path`, so a path such as `//evil.example/` is never redirected to `//evil.example`, and paths with backslashes or control characters are never redirected. Paths with `.` or `..` segments are never redirected either, because clients resolve those segments and would land somewhere other than the route that was found. The `Location` is the target path percent-escaped, followed by the request's raw query string with any `\` and `#` escaped, so the query stays one local query.

### The response

The redirect is a 308 Permanent Redirect with an empty body, for every method. 308 keeps the method and body, so a `POST` arrives intact. Unlike 301, it never becomes a `GET`. One status for every method keeps the rule simple. There is no option for a temporary redirect. Browsers cache permanent redirects, so changing a route's form during development can leave a browser following the old redirect until its cache is cleared.

The redirect takes the place of the not-found handler and is dispatched like one:

- Global middleware wraps it, so logging, request IDs, and headers set by middleware apply, and middleware can replace it. Group middleware doesn't run, because no route was selected.
- Cross-origin request protection (ADR 0008) runs as for any request that matched no route. A cross-site browser `POST` to the wrong form gets 403, not a redirect.
- Security headers, the completion observer, and `App.handle` all see it like any other response.

## Consequences

- Applications register one form of each path. dope pages that are exported as `x/index.html` can register `/x/`, and `/x` redirects as it does on a static host.
- Existing applications change behavior only for requests that got a 404 and whose other form has a route. Those now get a 308. Responses that weren't 404s don't change. A custom `not_found` handler no longer sees those requests.
- `/files` with a `/files/*path` route redirects instead of returning 404.
- Applications that need exact matching, for example to keep serving 404s for the other form, turn redirects off with `app.redirect_trailing_slash(enabled: false)`.
- Serving both forms without a redirect, a site-wide form, and per-group settings are not supported. They can be added later if needed.

## Related

- [0002: Establish Dram's Core HTTP Architecture](./0002-establish-core-http-architecture.md)
- [0007: Add Cookie, Redirect, and Security Header Helpers](./0007-add-cookie-redirect-and-security-header-helpers.md)
- [0008: Secure Responses and Requests by Default](./0008-secure-responses-and-requests-by-default.md)
- [RFC 9110 §15.4.9: 308 Permanent Redirect](https://www.rfc-editor.org/rfc/rfc9110#section-15.4.9)
- [Gin `RedirectTrailingSlash`](https://pkg.go.dev/github.com/gin-gonic/gin#Engine)
- [Django `APPEND_SLASH`](https://docs.djangoproject.com/en/stable/ref/settings/#append-slash)
