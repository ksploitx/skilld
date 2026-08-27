import enum
from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime, Enum, ARRAY, Text
from database import Base

class SkillSourceEnum(enum.Enum):
    skills_sh = "skills_sh"
    github = "github"

class Skill(Base):
    __tablename__ = "skills"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True, nullable=False)
    description = Column(String, nullable=True)
    tags = Column(ARRAY(String), default=[])
    source_url = Column(String, nullable=False)
    raw_content = Column(Text, nullable=False)
    source = Column(Enum(SkillSourceEnum), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
