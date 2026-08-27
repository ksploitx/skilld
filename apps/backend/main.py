from fastapi import FastAPI
from database import redis_client

app = FastAPI(title="skilld API")

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.get("/skills")
async def search_skills(query: str = ""):
    # Stub endpoint
    return []
