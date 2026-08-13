"""Central logging: everything goes to logs/game-launcher.log and stderr."""
from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler

from config import LOG_DIR

_configured = False


def _configure() -> None:
    global _configured
    if _configured:
        return
    fmt = logging.Formatter(
        "%(asctime)s %(levelname)-7s %(name)-12s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    file_handler = RotatingFileHandler(
        LOG_DIR / "game-launcher.log", maxBytes=2_000_000, backupCount=3
    )
    file_handler.setFormatter(fmt)
    stream = logging.StreamHandler()
    stream.setFormatter(fmt)

    root = logging.getLogger("gl")
    root.setLevel(logging.INFO)
    root.addHandler(file_handler)
    root.addHandler(stream)
    _configured = True


def get_logger(name: str) -> logging.Logger:
    _configure()
    return logging.getLogger(f"gl.{name}")
