"""Shared pytest fixtures for the NeuroSync test suite."""

import os
import subprocess
import sys
from collections.abc import AsyncGenerator, Iterator
from pathlib import Path

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from neurosync.config.settings import settings
from neurosync.db import get_session
from neurosync.main import app

_REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
_ALEMBIC_EXECUTABLE = Path(sys.executable).parent / "alembic"

# Truncated between tests.
_DOMAIN_TABLES = "check_ins, doctor_links, doctor_codes, patient_sessions, patients, doctors"

# pytest-asyncio runs every test on a fresh event loop, and asyncpg connections
# are bound to the loop that opened them. The suite therefore uses NullPool so
# no connection outlives the test that created it, and the pooled production
# engine is never exercised by the tests.
test_engine = create_async_engine(settings.database_url, poolclass=NullPool)
test_session_factory = async_sessionmaker(
    test_engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


async def _test_get_session() -> AsyncGenerator[AsyncSession]:
    """Mirror ``neurosync.db.get_session`` but on the NullPool test engine."""
    async with test_session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


@pytest.fixture(scope="session", autouse=True)
def migrated_database() -> Iterator[None]:
    """Apply Alembic migrations so tests run against the real schema.

    Tests never call ``metadata.create_all``; migrating here means a broken
    migration fails the suite instead of being papered over.
    """
    result = subprocess.run(
        [str(_ALEMBIC_EXECUTABLE), "upgrade", "head"],
        cwd=_REPOSITORY_ROOT,
        capture_output=True,
        text=True,
        check=False,
        env={**os.environ, "ENVIRONMENT": "test"},
    )
    if result.returncode != 0:
        failure = f"alembic upgrade head failed:\n{result.stdout}\n{result.stderr}"
        raise RuntimeError(failure)
    yield


@pytest_asyncio.fixture(autouse=True)
async def clean_database(request: pytest.FixtureRequest) -> AsyncGenerator[None]:
    """Empty the domain tables before each test."""
    request.getfixturevalue("migrated_database")
    async with test_session_factory() as session:
        await session.execute(text(f"TRUNCATE {_DOMAIN_TABLES} RESTART IDENTITY CASCADE"))
        await session.commit()
    yield


@pytest_asyncio.fixture
async def db() -> AsyncGenerator[AsyncSession]:
    """Provide a session for direct database assertions and setup."""
    async with test_session_factory() as session:
        try:
            yield session
        finally:
            await session.rollback()
            await session.close()


@pytest_asyncio.fixture
async def client() -> AsyncGenerator[AsyncClient]:
    """Provide an HTTP client bound to the application."""
    app.dependency_overrides[get_session] = _test_get_session
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as http_client:
        yield http_client
    app.dependency_overrides.pop(get_session, None)
