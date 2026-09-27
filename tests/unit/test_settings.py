import pytest

from neurosync.config.settings import Settings

_ENV_VARS = (
    "APP_NAME",
    "APP_VERSION",
    "ENVIRONMENT",
    "DEBUG",
    "HOST",
    "PORT",
    "DATABASE_URL",
    "DATABASE_POOL_SIZE",
    "DATABASE_MAX_OVERFLOW",
    "DATABASE_POOL_TIMEOUT",
    "DATABASE_POOL_RECYCLE",
    "LOG_LEVEL",
    "LOG_FORMAT",
    "CORS_ORIGINS",
)


@pytest.fixture(autouse=True)
def clean_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    """Isolate settings tests from ambient environment variables."""
    for name in _ENV_VARS:
        monkeypatch.delenv(name, raising=False)


def test_settings_defaults() -> None:
    settings = Settings(_env_file=None)

    assert settings.app_name == "NeuroSync"
    assert settings.environment == "development"
    assert settings.debug is False
    assert settings.host == "0.0.0.0"
    assert settings.port == 8000  # noqa: PLR2004


def test_settings_is_production() -> None:
    settings = Settings(_env_file=None, environment="production")

    assert settings.is_production is True
    assert settings.is_development is False


def test_settings_is_development() -> None:
    settings = Settings(_env_file=None, environment="development")

    assert settings.is_development is True
    assert settings.is_production is False


def test_settings_database_url_default() -> None:
    settings = Settings(_env_file=None)

    assert settings.database_url == (
        "postgresql+asyncpg://neurosync:neurosync@localhost:5432/neurosync"
    )
