"""
Root-level shim — re-exports from app.database for backward compatibility.
"""
from app.database import Base, async_session_factory as async_session, engine, redis_client  # noqa: F401
