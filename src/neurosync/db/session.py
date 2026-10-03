from collections.abc import AsyncGenerator
from enum import StrEnum

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from neurosync.config.settings import settings


class Base(DeclarativeBase):
    pass


def sql_values(enum: type[StrEnum]) -> str:
    """Render enum members as a SQL ``IN (...)`` list for a check constraint.

    Lives here rather than in any one feature module because every module that
    constrains a stored enum to its Python values needs exactly this, and the
    constraint text has to stay identical to what the migrations wrote.
    """
    return ", ".join(f"'{member.value}'" for member in enum)


engine: AsyncEngine = create_async_engine(
    settings.database_url,
    pool_size=settings.database_pool_size,
    max_overflow=settings.database_max_overflow,
    pool_timeout=settings.database_pool_timeout,
    pool_recycle=settings.database_pool_recycle,
    echo=settings.is_development,
)

async_session_factory = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


async def get_session() -> AsyncGenerator[AsyncSession]:
    async with async_session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def close_db() -> None:
    await engine.dispose()
