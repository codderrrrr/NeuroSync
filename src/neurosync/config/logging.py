import logging
import sys

import structlog


def configure_logging(log_level: str = "INFO", log_format: str = "json") -> None:
    log_level_int = getattr(logging, log_level.upper(), logging.INFO)

    renderer: structlog.processors.JSONRenderer | structlog.dev.ConsoleRenderer = (
        structlog.processors.JSONRenderer()
    )

    if log_format == "json":
        renderer = structlog.processors.JSONRenderer()
    else:
        renderer = structlog.dev.ConsoleRenderer()

    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.StackInfoRenderer(),
            structlog.dev.set_exc_info,
            structlog.processors.TimeStamper(fmt="iso"),
            renderer,
        ],
        wrapper_class=structlog.make_filtering_bound_logger(log_level_int),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(file=sys.stdout),
        cache_logger_on_first_use=True,
    )

    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=log_level_int,
    )

    for logger_name in ["uvicorn", "uvicorn.error", "uvicorn.access", "sqlalchemy"]:
        logging.getLogger(logger_name).handlers = []
        logging.getLogger(logger_name).propagate = True
