import string

from neurosync.modules.auth.security import (
    generate_session_token,
    hash_password,
    hash_session_token,
    verify_password,
)

PASSWORD = "correct-horse-battery"
_TOKEN_ALPHABET = set(string.ascii_letters + string.digits + "-_")
_TOKEN_SAMPLE_SIZE = 50
_SHA256_HEX_LENGTH = 64


def test_hash_password_does_not_store_the_plaintext() -> None:
    password_hash = hash_password(PASSWORD)

    assert PASSWORD not in password_hash
    assert password_hash.startswith("scrypt$")


def test_hash_password_uses_a_fresh_salt_each_time() -> None:
    assert hash_password(PASSWORD) != hash_password(PASSWORD)


def test_verify_password_accepts_the_correct_password() -> None:
    assert verify_password(PASSWORD, hash_password(PASSWORD)) is True


def test_verify_password_rejects_a_wrong_password() -> None:
    assert verify_password("wrong-horse-battery", hash_password(PASSWORD)) is False


def test_verify_password_fails_closed_on_malformed_hashes() -> None:
    assert verify_password(PASSWORD, "not-a-hash") is False
    assert verify_password(PASSWORD, "bcrypt$1$1$1$abcd$abcd") is False
    assert verify_password(PASSWORD, "scrypt$0$0$0$abcd$abcd") is False


def test_session_tokens_are_unique_and_urlsafe() -> None:
    tokens = {generate_session_token() for _ in range(_TOKEN_SAMPLE_SIZE)}

    assert len(tokens) == _TOKEN_SAMPLE_SIZE
    assert all(set(token) <= _TOKEN_ALPHABET for token in tokens)


def test_hash_session_token_is_a_stable_sha256_digest() -> None:
    token = generate_session_token()

    digest = hash_session_token(token)

    assert digest == hash_session_token(token)
    assert len(digest) == _SHA256_HEX_LENGTH
    assert token not in digest
