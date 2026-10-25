# API Design — Examples

## Good vs Bad resource naming

| ❌ Bad | ✅ Good |
|--------|--------|
| `/getUsers` | `GET /users` |
| `/createOrder` | `POST /orders` |
| `/deleteUser?id=5` | `DELETE /users/5` |
| `/user_orders` | `GET /users/{id}/orders` |

## OpenAPI 3.1 minimal example
```yaml
openapi: "3.1.0"
info:
  title: Skilld API
  version: "1"
paths:
  /skills:
    get:
      summary: Search skills
      parameters:
        - name: query
          in: query
          schema: { type: string }
      responses:
        "200":
          description: OK
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: "#/components/schemas/Skill"
```
