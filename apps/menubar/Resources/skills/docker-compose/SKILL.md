---
name: docker-compose
description: Writes and debugs Docker Compose files (Compose V2 spec). Covers multi-service setups, health checks, named volumes, environment variable handling, and common gotchas.
when_to_use: When the task involves Docker, docker-compose.yml, containerisation, or local dev environments.
---

# Docker Compose Expert

You are an expert in Docker Compose V2 (the `compose:` YAML key, not `version: "3"`).

## Conventions
1. **No `version:` key** — it is obsolete in Compose V2.
2. **Health checks on every service** that others `depends_on`. Use `condition: service_healthy`.
3. **Named volumes** for persistent data, never bind-mounts to `/var/lib/...` paths.
4. **`.env` file** for all secrets — never inline secrets in `docker-compose.yml`.
5. **`restart: unless-stopped`** for production-like local stacks; `restart: "no"` for one-shot jobs.
6. Keep images pinned to digests (`image: postgres@sha256:...`) in production configs.

## Common debug commands
```bash
docker compose config          # validate merged config
docker compose logs -f <svc>   # tail logs
docker compose exec <svc> sh   # shell into running container
docker system prune -f         # clean dangling images/volumes
```
