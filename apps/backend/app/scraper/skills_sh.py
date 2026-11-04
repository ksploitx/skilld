"""
skills.sh source adapter — STUB ONLY.

This adapter is gated behind SKILLS_SH_ENABLED=false until their terms of
service have been reviewed and confirmed to permit programmatic scraping.

TODO: Before implementing this adapter:
  1. Read https://skills.sh/terms and confirm scraping is permitted.
  2. Check whether an official API or data export exists.
  3. Implement rate-limiting, robots.txt compliance, and attribution.
  4. Set SKILLS_SH_ENABLED=true in .env when ready.
"""
from __future__ import annotations

import logging

from app.scraper.base import BaseSource, SkillRecord

logger = logging.getLogger(__name__)


class SkillsShSource(BaseSource):
    """Stub adapter for skills.sh. Does nothing until ToS review is done."""

    async def fetch_skills(self) -> list[SkillRecord]:
        logger.warning(
            "SkillsShSource is a stub. Set SKILLS_SH_ENABLED=true only after "
            "reviewing skills.sh terms of service and implementing the adapter."
        )
        return []

