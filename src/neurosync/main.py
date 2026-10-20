from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from neurosync.api.health import router as health_router
from neurosync.config.logging import configure_logging
from neurosync.config.settings import Settings, settings
from neurosync.db import close_db
from neurosync.modules.auth.router import router as auth_router
from neurosync.modules.check_ins.router import router as check_ins_router
from neurosync.modules.doctor.router import router as doctor_router
from neurosync.modules.doctor_linking.router import router as doctor_linking_router
from neurosync.modules.medication.router import router as medication_router
from neurosync.modules.monitoring.router import catalog_router as monitoring_catalog_router
from neurosync.modules.monitoring.router import router as monitoring_router


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None]:  # noqa: ARG001
    configure_logging(settings.log_level, settings.log_format)
    yield
    await close_db()


# A browser on the local machine, on any port.
_LOCAL_ORIGIN = r"https?://(localhost|127\.0\.0\.1)(:\d+)?"

# A browser on the same private network, on any port. Only in development:
# the doctor portal is served from the development machine, and the point of
# running it on a phone or tablet is to see the real layout, which means
# loading it from the machine's network address.
_PRIVATE_ORIGIN = r"https?://(10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+)(:\d+)?"


def _origin_regex(settings: Settings) -> str:
    """The origins a browser may make a cross-origin request from."""
    if settings.is_development:
        return f"{_LOCAL_ORIGIN}|{_PRIVATE_ORIGIN}"
    return _LOCAL_ORIGIN


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description="NeuroSync - Longitudinal Parkinson's motor monitoring and care coordination",
        lifespan=lifespan,
        docs_url="/docs" if settings.is_development else None,
        redoc_url="/redoc" if settings.is_development else None,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_origin_regex=_origin_regex(settings),
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(health_router)
    app.include_router(auth_router)
    app.include_router(check_ins_router)
    app.include_router(doctor_linking_router)
    app.include_router(doctor_router)
    app.include_router(medication_router)
    app.include_router(monitoring_catalog_router)
    app.include_router(monitoring_router)

    return app


app = create_app()
