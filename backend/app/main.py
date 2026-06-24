from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.routes import router
from app.core.config import settings
from app.scheduler import build_scheduler


@asynccontextmanager
async def lifespan(app: FastAPI):
    scheduler = None
    if settings.enable_scheduler:
        scheduler = build_scheduler()
        scheduler.start()
    yield
    if scheduler:
        scheduler.shutdown(wait=False)


app = FastAPI(title="Daily POS Dashboard API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router, prefix="/api")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


def _frontend_dist_dir() -> Path:
    if settings.frontend_dist_dir:
        return Path(settings.frontend_dist_dir).expanduser().resolve()
    return Path(__file__).resolve().parents[2] / "frontend" / "dist"


frontend_dist_dir = _frontend_dist_dir()
if frontend_dist_dir.exists():
    app.mount("/", StaticFiles(directory=frontend_dist_dir, html=True), name="frontend")
