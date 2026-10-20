"""Which origins a browser may make a cross-origin request from."""

import re

import pytest

from neurosync.config.settings import Settings
from neurosync.main import _origin_regex


def _matches(pattern: str, origin: str) -> bool:
    return bool(re.fullmatch(pattern, origin))


@pytest.fixture
def development_pattern() -> str:
    return _origin_regex(Settings(environment="development"))


@pytest.fixture
def production_pattern() -> str:
    return _origin_regex(Settings(environment="production"))


class TestDevelopment:
    def test_the_local_machine_is_allowed(self, development_pattern: str) -> None:
        assert _matches(development_pattern, "http://localhost:3000")
        assert _matches(development_pattern, "http://127.0.0.1:8000")

    def test_a_device_on_the_network_is_allowed(self, development_pattern: str) -> None:
        # The doctor portal is served from the development machine, so a
        # browser on a phone or tablet loads it from the machine's address.
        assert _matches(development_pattern, "http://192.168.3.111:8080")
        assert _matches(development_pattern, "http://10.0.2.2:8000")

    def test_a_public_origin_is_refused(self, development_pattern: str) -> None:
        assert not _matches(development_pattern, "http://evil.example")
        assert not _matches(development_pattern, "https://evil.example")


class TestProduction:
    def test_the_local_machine_is_allowed(self, production_pattern: str) -> None:
        assert _matches(production_pattern, "http://localhost:3000")
        assert _matches(production_pattern, "http://127.0.0.1:8000")

    def test_a_device_on_the_network_is_refused(self, production_pattern: str) -> None:
        # A private network address is not a production origin.
        assert not _matches(production_pattern, "http://192.168.3.111:8080")
        assert not _matches(production_pattern, "http://10.0.2.2:8000")

    def test_a_public_origin_is_refused(self, production_pattern: str) -> None:
        assert not _matches(production_pattern, "http://evil.example")
