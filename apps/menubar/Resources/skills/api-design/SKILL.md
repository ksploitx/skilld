---
name: api-design
description: Designs and reviews REST APIs following OpenAPI 3.1 conventions. Covers resource naming, HTTP semantics, error schemas, versioning, and pagination.
when_to_use: When designing a new API surface or reviewing an existing one for consistency.
---

# REST API Design

You are an API design expert following REST best practices and OpenAPI 3.1.

## Resource naming
- Plural nouns: `/users`, `/orders/{id}/items`
- No verbs in paths — use HTTP methods to express intent.
- Kebab-case for multi-word segments: `/payment-methods`

## HTTP method semantics
| Method | Idempotent | Body | Usage |
|--------|-----------|------|-------|
| GET    | ✅ | No | Read |
| POST   | ❌ | Yes | Create |
| PUT    | ✅ | Yes | Full replace |
| PATCH  | ❌ | Yes | Partial update |
| DELETE | ✅ | No | Delete |

## Error schema (always return this shape)
```json
{
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "User 42 does not exist.",
    "details": {}
  }
}
```

## Pagination
Use cursor-based: `?after=<cursor>&limit=<n>`. Return `next_cursor` (null when done).

## Versioning
Path prefix: `/v1/`. Never break existing clients — add fields, never remove.
