"""
Root-level shim — delegates to app.main.
Run with: uvicorn app.main:app --reload
This file kept for backward compatibility with any tooling that references
apps/backend/main.py directly.
"""
from app.main import app  # noqa: F401
