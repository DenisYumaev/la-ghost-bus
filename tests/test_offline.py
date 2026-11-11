"""Guards hard rule 7: no test may make a network call."""

import socket

import pytest


def test_network_access_is_blocked() -> None:
    # pytest-socket (enabled via --disable-socket in pyproject.toml) raises
    # on any socket creation. If this test fails, the guard is off.
    with pytest.raises(Exception, match="socket"):
        socket.socket(socket.AF_INET, socket.SOCK_STREAM)
