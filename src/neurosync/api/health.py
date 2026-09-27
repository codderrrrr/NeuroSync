from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.config.settings import settings
from neurosync.db import get_session

router = APIRouter(tags=["health"])

DB_SESSION_DEPENDENCY = Depends(get_session)


@router.get("/health", summary="Health check endpoint")
async def health_check() -> dict[str, str]:
    return {
        "status": "healthy",
        "service": settings.app_name,
        "version": settings.app_version,
    }


@router.get("/health/db", summary="Database health check")
async def db_health_check(session: AsyncSession = DB_SESSION_DEPENDENCY) -> dict[str, str]:
    try:
        await session.execute(text("SELECT 1"))
    except Exception:
        return {"status": "unhealthy", "database": "disconnected"}
    else:
        return {"status": "healthy", "database": "connected"}
