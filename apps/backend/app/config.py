"""
Centralised settings loaded from environment variables (and .env file).
All magic strings for external services live here.
"""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Postgres
    database_url: str = (
        "postgresql+asyncpg://postgres:postgres@localhost:5432/skilld"
    )

    # Redis
    redis_url: str = "redis://localhost:6379/0"
    search_cache_ttl_seconds: int = 60  # TTL for cached search results

    # GitHub scraper
    github_token: str = ""  # PAT or Actions token; anonymous = 60 req/h
    github_api_base: str = "https://api.github.com"

    # Feature flags
    skills_sh_enabled: bool = False  # stub only until ToS checked


@lru_cache
def get_settings() -> Settings:
    return Settings()

