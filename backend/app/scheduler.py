from apscheduler.schedulers.background import BackgroundScheduler

from app.core.config import settings
from app.db.session import SessionLocal
from app.services.sync_service import SyncService


def sync_all_available() -> None:
    service = SyncService()
    with SessionLocal() as db:
        for source in settings.pos_sources:
            service.sync_all_available(db, source)


def build_scheduler() -> BackgroundScheduler:
    scheduler = BackgroundScheduler(timezone=settings.default_timezone)
    scheduler.add_job(
        sync_all_available,
        trigger="cron",
        hour=settings.daily_sync_hour,
        minute=settings.daily_sync_minute,
        id="daily-pos-sync",
        replace_existing=True,
        misfire_grace_time=60 * 60,
    )
    return scheduler

