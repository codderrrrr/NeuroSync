from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from neurosync.api.health import router as health_router
from neurosync.config.logging import configure_logging
from neurosync.config.settings import settings
from neurosync.db import close_db
from neurosync.modules.auth.router import router as auth_router
from neurosync.modules.check_ins.router import router as check_ins_router
from neurosync.modules.doctor_linking.router import router as doctor_linking_router


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None]:  # noqa: ARG001
    configure_logging(settings.log_level, settings.log_format)
    yield
    await close_db()


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
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(health_router)
    app.include_router(auth_router)
    app.include_router(check_ins_router)
    app.include_router(doctor_linking_router)

    return app


app = create_app()
