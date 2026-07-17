# 0001: Record Architecture Decisions

## Status

Accepted

## Context

Important architectural decisions need a durable record of why they were made, which alternatives or constraints shaped them, and what consequences they introduce. Without that record, decisions can be revisited without their original context and project conventions can become difficult to understand.

## Decision

Use Architecture Decision Records (ADRs) for significant decisions that affect the project's architecture, public interfaces, long-term conventions, or implementation direction.

ADRs live in `docs/adrs/` and use sequential four-digit numbers. Each ADR includes status, context, decision, consequences, and related references. Accepted ADRs are historical records; a later decision supersedes an earlier ADR instead of silently rewriting it.

## Consequences

- Architectural decisions and their rationale have a consistent, discoverable home.
- Contributors must decide when a change is significant enough to warrant an ADR.
- The ADR collection requires light maintenance as decisions are proposed, accepted, superseded, or deprecated.

## Related

- [`docs/README.md`](../README.md)
