"""Password hashing and session-token primitives.

Passwords are hashed with ``scrypt`` from the standard library, so no extra
dependency is required. Session tokens are high-entropy random strings; only
their SHA-256 digest is stored.
"""

import base64
import hashlib
import hmac
import secrets
from dataclasses import dataclass
from datetime import timedelta
from typing import Final

ALGORITHM: Final[str] = "scrypt"
SESSION_COOKIE_NAME: Final[str] = "neurosync_session"
SESSION_TTL: Final[timedelta] = timedelta(days=30)

_SALT_BYTES: Final[int] = 16
_DERIVED_KEY_BYTES: Final[int] = 32
# scrypt needs roughly 128 * n * r bytes; 64 MiB comfortably covers n=2**15, r=8.
_MAX_MEMORY: Final[int] = 64 * 1024 * 1024

_TOKEN_BYTES: Final[int] = 32


@dataclass(frozen=True, slots=True)
class ScryptParameters:
    """Work factors stored alongside a hash so it stays verifiable."""

    n: int
    r: int
    p: int


DEFAULT_PARAMETERS: Final[ScryptParameters] = ScryptParameters(n=2**15, r=8, p=1)


def _derive(
    password: str,
    *,
    salt: bytes,
    length: int,
    parameters: ScryptParameters,
) -> bytes:
    return hashlib.scrypt(
        password.encode("utf-8"),
        salt=salt,
        n=parameters.n,
        r=parameters.r,
        p=parameters.p,
        dklen=length,
        maxmem=_MAX_MEMORY,
    )


def hash_password(password: str) -> str:
    """Hash a password with a fresh random salt.

    The returned value encodes the algorithm and its parameters so existing
    hashes stay verifiable when the parameters are tuned later.
    """
    salt = secrets.token_bytes(_SALT_BYTES)
    derived = _derive(
        password,
        salt=salt,
        length=_DERIVED_KEY_BYTES,
        parameters=DEFAULT_PARAMETERS,
    )
    encoded_salt = base64.b64encode(salt).decode("ascii")
    encoded_hash = base64.b64encode(derived).decode("ascii")
    parameters = DEFAULT_PARAMETERS
    return f"{ALGORITHM}${parameters.n}${parameters.r}${parameters.p}${encoded_salt}${encoded_hash}"


def verify_password(password: str, password_hash: str) -> bool:
    """Return ``True`` when ``password`` matches ``password_hash``.

    Malformed hashes, or hashes using unsupported parameters, fail closed
    instead of raising.
    """
    try:
        algorithm, n, r, p, encoded_salt, encoded_hash = password_hash.split("$")
        if algorithm != ALGORITHM:
            return False
        expected = base64.b64decode(encoded_hash)
        derived = _derive(
            password,
            salt=base64.b64decode(encoded_salt),
            length=len(expected),
            parameters=ScryptParameters(n=int(n), r=int(r), p=int(p)),
        )
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(derived, expected)


def generate_session_token() -> str:
    """Return a new opaque, high-entropy session token."""
    return secrets.token_urlsafe(_TOKEN_BYTES)


def hash_session_token(token: str) -> str:
    """Return the digest stored for a session token."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
