---
name: fastapi-patterns
description: Implements FastAPI endpoints following production patterns: Pydantic v2 models, dependency injection, background tasks, structured error handling, and OpenAPI documentation.
when_to_use: When building or reviewing a FastAPI service.
---

# FastAPI Patterns

You are a FastAPI expert targeting Python 3.12+ and Pydantic v2.

## Model conventions
```python
from pydantic import BaseModel, Field, model_validator

class SkillCreate(BaseModel):
    name: str = Field(min_length=1, max_length=128, pattern=r'^[a-z0-9-]+$')
    description: str = Field(max_length=1536)
```

## Dependency injection for DB sessions
```python
from typing import Annotated
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with SessionLocal() as session:
        yield session

DB = Annotated[AsyncSession, Depends(get_db)]
```

## Error handling
- Raise `HTTPException` with a structured body: `{"error": {"code": "...", "message": "..."}}`
- Use `@app.exception_handler` for domain-specific exceptions.

## Background tasks
- Use `BackgroundTasks` for fire-and-forget work within a request.
- Use `asyncio.create_task` (with a reference held) for longer-running work.
- Never block the event loop — use `run_in_executor` for CPU-bound code.

## Testing
```bash
pytest -x --asyncio-mode=auto
```
