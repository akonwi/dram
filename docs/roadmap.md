# Dram Roadmap

This checklist collects the planned and incomplete work described by the accepted ADRs. It is an inventory, not a priority order. Completed features are documented in the root README and are intentionally omitted here.

## Request context

- [ ] Evaluate convenience helpers for deriving contexts with cancellation, deadlines, and timeouts.

## Response architecture

- [ ] Introduce an explicit internal response delivery mode.
- [ ] Ensure response helpers consistently replace an earlier uncommitted delivery selection.

## Buffered response helpers

- [ ] Add a JSON response helper.
- [ ] Evaluate an HTML response helper.
- [ ] Add a redirect response helper.

## Headers

- [ ] Make header mutation commitment-aware once non-buffered delivery modes exist.

## Request bodies and limits

- [ ] Evaluate streaming request-body access.
- [ ] Make server and request limits configurable beyond the current body-size setting.

## File responses

- [ ] Add a file delivery mode without buffering the whole file.
- [ ] Support application-provided paths or file handles.
- [ ] Open and validate files before commitment.
- [ ] Delegate efficient transfer to Go HTTP facilities where practical.
- [ ] Support range requests.
- [ ] Support modification and conditional request checks.
- [ ] Produce correct content-length metadata.
- [ ] Return 404 for missing files while the response is uncommitted.
- [ ] Log unexpected file-access failures and return a generic 500 before commitment.
- [ ] Evaluate a static-directory helper with path-traversal protection.

## Streaming responses

- [ ] Add a stream delivery mode and dedicated stream capability.
- [ ] Start stream callbacks only after ordinary middleware completes.
- [ ] Keep headers replaceable until the first successful write or flush.
- [ ] Commit the response on the first successful write or flush.
- [ ] Make stream writes report connection usability with `Bool`.
- [ ] Expose request cancellation and client-disconnect state to streams.
- [ ] Convert panics before first output into a clean 500 response.
- [ ] Log panics after commitment and close the stream.
- [ ] Prevent stream callbacks from continuing ordinary middleware dispatch.

## Server-sent events

- [ ] Add a dedicated SSE delivery mode and event-stream capability.
- [ ] Manage required SSE headers.
- [ ] Format event names and multiline data correctly.
- [ ] Flush events as they are sent.
- [ ] Handle cancellation and client disconnects.
- [ ] Support optional heartbeat comments.
- [ ] Support event IDs.
- [ ] Support retry values.
- [ ] Apply the documented pre- and post-commit panic behavior.
- [ ] Ensure panic details are never emitted as SSE data by default.

## WebSockets

- [ ] Record a separate ADR selecting a Go WebSocket dependency.
- [ ] Add a WebSocket upgrade delivery mode.
- [ ] Store the upgrade callback without committing during ordinary middleware.
- [ ] Allow rejected or failed upgrades to remain ordinary HTTP responses when possible.
- [ ] Treat a successful handshake as commitment.
- [ ] Provide a dedicated socket capability without ordinary response mutation.
- [ ] On recovered panic, send an internal-error close indication when possible and close the socket.

## Panic recovery and observability

- [ ] Replace the current minimal recovery boundary with panic message and stack capture.
- [ ] Add a configurable logger or recovery observer.
- [ ] Keep panic details out of client responses by default.
- [ ] Implement recovery behavior for unopened and opened file responses.
- [ ] Implement recovery behavior before and after stream commitment.
- [ ] Implement recovery behavior before and after SSE commitment.
- [ ] Implement recovery behavior before and after WebSocket upgrade.

## Server lifecycle

- [ ] Add graceful shutdown.
- [ ] Add an explicit server handle or lifecycle API.
- [ ] Make lifecycle timeouts configurable.
- [ ] Revisit write-timeout behavior before introducing long-lived streams and SSE.

## Testing infrastructure

- [ ] Add a delivery recorder that can model response commitment.
- [ ] Simulate flushes and client disconnects.
- [ ] Test efficient and conditional file delivery.
- [ ] Test stream behavior before and after commitment.
- [ ] Test SSE formatting, flushing, cancellation, and heartbeats.
- [ ] Test successful, rejected, and failed WebSocket upgrades.
- [ ] Test recovery in every delivery mode and commitment state.

## Publication discipline

- [ ] Do not publish file, stream, SSE, WebSocket, or commitment placeholders before their behavior is implemented and tested.
