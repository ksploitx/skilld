"""
skilld FastAPI application entry-point.

Run locally:
    uvicorn app.main:app --reload
"""
from fastapi import FastAPI

from app.api.skills import router as skills_router

app = FastAPI(
    title="skilld API",
    description="Skill index and search API for the skilld platform.",
    version="0.2.0",
)

# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/health", tags=["meta"])
async def health() -> dict:
    return {"status": "ok"}


# ── Routers ───────────────────────────────────────────────────────────────────

app.include_router(skills_router)

