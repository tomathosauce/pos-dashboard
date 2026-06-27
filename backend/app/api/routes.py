from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db
from app.models.reporting import SyncRun
from app.schemas.reporting import DashboardSummaryOut, PaymentSummaryOut, SourceOut, SyncRunOut
from app.services.dashboard_service import get_payments, get_summary
from app.services.sync_service import SyncService

router = APIRouter()


def _default_yesterday() -> date:
    return date.today() - timedelta(days=1)


@router.get("/sources", response_model=list[SourceOut])
def list_sources() -> list[SourceOut]:
    return [
        SourceOut(
            name=source.name,
            path=str(source.resolved_path),
            reader=source.reader,
            timezone=source.timezone,
            currency=source.currency,
        )
        for source in settings.pos_sources
    ]


@router.get("/dashboard/summary", response_model=DashboardSummaryOut)
def dashboard_summary(
    from_date: date = Query(default_factory=_default_yesterday, alias="from"),
    to_date: date = Query(default_factory=_default_yesterday, alias="to"),
    source: str = "all",
    db: Session = Depends(get_db),
) -> DashboardSummaryOut:
    if from_date > to_date:
        raise HTTPException(status_code=422, detail="'from' date cannot be after 'to' date")
    data = get_summary(db, from_date, to_date, source)
    return DashboardSummaryOut(
        from_date=data["from"],
        to_date=data["to"],
        source=data["source"],
        currency=data["currency"],
        total_amount=data["total_amount"],
        payment_count=data["payment_count"],
        receipt_count=data["receipt_count"],
        source_row_count=data["source_row_count"],
        last_sync=data["last_sync"],
        days=data["days"],
    )


@router.get("/dashboard/payments", response_model=list[PaymentSummaryOut])
def dashboard_payments(
    from_date: date = Query(default_factory=_default_yesterday, alias="from"),
    to_date: date = Query(default_factory=_default_yesterday, alias="to"),
    source: str = "all",
    db: Session = Depends(get_db),
) -> list[PaymentSummaryOut]:
    if from_date > to_date:
        raise HTTPException(status_code=422, detail="'from' date cannot be after 'to' date")
    return [PaymentSummaryOut(**payment) for payment in get_payments(db, from_date, to_date, source)]


@router.get("/sync-runs", response_model=list[SyncRunOut])
def sync_runs(limit: int = Query(default=50, ge=1, le=200), db: Session = Depends(get_db)) -> list[SyncRun]:
    statement = select(SyncRun).order_by(SyncRun.started_at.desc()).limit(limit)
    return list(db.execute(statement).scalars().all())


@router.post("/sync/run", response_model=list[SyncRunOut])
def run_sync(
    business_date: date | None = Query(default=None, alias="date"),
    source: str = "all",
    db: Session = Depends(get_db),
) -> list[SyncRun]:
    service = SyncService()
    sources = settings.pos_sources if source == "all" else [settings.get_source(source)]
    if business_date is not None:
        return [service.sync_day(db, source_config, business_date) for source_config in sources]

    runs: list[SyncRun] = []
    for source_config in sources:
        runs.extend(service.sync_all_available(db, source_config))
    return runs
