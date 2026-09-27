"""Shared pytest fixtures for the NeuroSync test suite."""

from collections.abc import AsyncGenerator

import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.db import async_session_factory


@pytest_asyncio.fixture
async def db_session() -> AsyncGenerator[AsyncSession]:
    """Provide a database session for tests that need persistence.

    Tests run against the database configured by ``DATABASE_URL``. Apply
    migrations to it (``uv run alembic upgrade head``) before running tests
    that touch tables. Changes are rolled back when the test finishes.
    """
    async with async_session_factory() as session:
        try:
            yield session
        finally:
            await session.rollback()
