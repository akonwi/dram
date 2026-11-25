# Project Docs

This directory contains project-wide architecture and design documentation.

## Roadmap

Planned and incomplete work from the accepted ADRs is tracked in [`roadmap.md`](./roadmap.md).

## Architecture Decision Records

Architecture Decision Records (ADRs) live in [`adrs/`](./adrs/). An ADR records a significant decision, the context that motivated it, and its consequences.

To add an ADR:

1. Copy the structure from an existing ADR.
2. Use the next sequential number: `NNNN-short-title.md`.
3. Keep the title in the form `# NNNN: Title`.
4. Include these sections:
   - `## Status`
   - `## Context`
   - `## Decision`
   - `## Consequences`
   - `## Related`
5. Prefer a concise record of the decision and tradeoffs over a long design document.

Common statuses are `Proposed`, `Accepted`, `Superseded`, and `Deprecated`. When a decision changes, add a new ADR and link the old and new records rather than rewriting history.

## ADR Index

- [0001: Record Architecture Decisions](./adrs/0001-record-architecture-decisions.md)
- [0002: Establish Dram's Core HTTP Architecture](./adrs/0002-establish-core-http-architecture.md)
- [0003: Use Opaque Middleware Continuations](./adrs/0003-use-indexed-middleware-dispatch.md)
- [0004: Define Response Delivery and Commitment](./adrs/0004-define-response-delivery-and-commitment.md)
- [0005: Add a Server Lifecycle and Observers](./adrs/0005-add-server-lifecycle-and-observers.md)
- [0006: Negotiate Representations at Delivery](./adrs/0006-negotiate-representations-at-delivery.md)
- [0007: Add Cookie, Redirect, and Security Header Helpers](./adrs/0007-add-cookie-redirect-and-security-header-helpers.md)
- [0008: Secure Responses and Requests by Default](./adrs/0008-secure-responses-and-requests-by-default.md)
