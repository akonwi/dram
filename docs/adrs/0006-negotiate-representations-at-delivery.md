# 0006: Negotiate Representations at Delivery

## Status

Accepted

## Context

Applications on Dram want two common HTTP optimizations: response compression and conditional `GET` (`If-None-Match` answered with 304 Not Modified). Both were left to applications.

Implemented as middleware, both are fragile. Middleware unwinds in registration order, so a compression middleware sees the final response only when it is registered first. A framework built on Dram, such as dope, registers its own middleware after the application's and therefore runs innermost. Outer application middleware can then replace the body, ETag, or `Cache-Control` after compression, producing a body that no longer matches its `Content-Encoding` or validator.

The two features also interact. An ETag validates one representation. Once a gzip representation exists, a conditional request must be compared against the ETag of the representation that would be sent, which is known only after compression is negotiated. Evaluating `If-None-Match` in a handler, before compression is chosen, answers 304 for the wrong representation.

## Decision

Dram negotiates representations in its delivery step: after the complete middleware chain and recovery boundary, before finalization. This applies to buffered responses only. Event streams are never compressed and never answered with 304.

### Compression

`app.compress(min_bytes?, types?)` enables gzip. It is opt-in because compression is often handled by a reverse proxy, and because it costs CPU. A response is compressed when all of these hold:

- its status allows content and is not 206;
- its body has at least `min_bytes` (default 1024);
- it has no `Content-Encoding`;
- its `Cache-Control` has no `no-transform` directive (case-insensitive);
- its media type is compressible: by default `text/*` except `text/event-stream`, JSON, JavaScript, XML, SVG, WebAssembly, and `+json`/`+xml` types. `types` replaces the list, and `type/*` entries match a whole type;
- the request's `Accept-Encoding` allows gzip, honoring `q=0` and `*`.

Every response that passes the response-side checks gets `Vary: Accept-Encoding`, whether or not this client accepts gzip, so shared caches keep the representations apart. The gzip representation gets its own strong ETag, with `"tag"` becoming `"tag-gzip"`. Compressed bodies are cached per strong ETag, bounded to 512 entries, so unchanged assets are compressed once. Weak ETags are not cached because they may cover different bytes. Only gzip is supported. Brotli would add a Go dependency to a package that so far uses only the standard library.

Compression is pure Ard over Go's `compress/gzip`.

### Conditional GET

For `GET` and `HEAD` responses with status 200 and an `ETag`, Dram compares the request's `If-None-Match` against the ETag of the selected representation, using weak comparison as RFC 9110 requires (`W/` is ignored and `*` matches). On a match the response becomes a 304 with no body and keeps its headers, including `ETag`, `Cache-Control`, and `Vary`. Compression is not performed for a 304.

This is automatic, not opt-in. An application that sets an ETag has stated a validator, and a matching `If-None-Match` means the client already holds that representation. Applications that want to bypass it should not set `ETag`. `App.handle` applies the same negotiation, so in-memory tests observe it.

`If-Modified-Since`, `If-Match`, and range requests are out of scope. They remain on the roadmap with file delivery.

## Consequences

- Handlers and frameworks set `ETag`, `Cache-Control`, and a full body. Dram chooses the encoding and answers revalidations correctly for every representation.
- Compression applies to the final response regardless of middleware order.
- Responses with an `ETag` can now be answered with 304, which changes behavior for applications that set ETags and expected their handler's full response every time.
- A request whose response is a 304 still runs its handler. Avoiding that work remains the application's choice.
- Compressing in the delivery step buffers the compressed body. That is acceptable because only buffered responses are eligible.

## Related

- [0004: Define Response Delivery and Commitment](./0004-define-response-delivery-and-commitment.md)
- [0005: Add a Server Lifecycle and Observers](./0005-add-server-lifecycle-and-observers.md)
- [RFC 9110 §13.1.2 If-None-Match](https://www.rfc-editor.org/rfc/rfc9110#section-13.1.2)
