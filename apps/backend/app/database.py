"""
Database engine, async session factory, and declarative Base.
Import `get_db` as a FastAPI dependency wherever a DB session is needed.
"""
from collections.abc import AsyncGenerator

import redis.asyncio as redis
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.config import get_settings

_settings = get_settings()

engine = create_async_engine(
    _settings.database_url,
    echo=False,
    pool_pre_ping=True,
)

async_session_factory = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency that yields a DB session and closes it after use."""
    async with async_session_factory() as session:
        yield session


# ---------------------------------------------------------------------------
# Redis client — module-level singleton, safe to re-use across requests.
# Not a source of truth: safe to flush at any time.
# ---------------------------------------------------------------------------
redis_client = redis.from_url(_settings.redis_url, decode_responses=True)

