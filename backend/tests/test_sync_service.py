from datetime import date
from decimal import Decimal

from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

from app.core.config import PosSourceConfig
from app.db.base import Base
from app.etl.fixture_reader import FixtureParadoxReader, payment_record
from app.models.reporting import DailySalesSummary, PaymentMethodSummary, SyncRun
from app.services.sync_service import SyncService


def make_session():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)()


def make_source() -> PosSourceConfig:
    return PosSourceConfig(name="main", path=".", timezone="America/Bogota", currency="USD")


def test_sync_aggregates_multiple_payment_methods() -> None:
    db = make_session()
    target_date = date(2022, 8, 6)
    reader = FixtureParadoxReader(records=[
        payment_record(target_date, "1", "10.25", receipt_key="A:1"),
        payment_record(target_date, "2", "5.75", receipt_key="A:1"),
        payment_record(target_date, "4", "7.00", receipt_key="A:2"),
        payment_record(target_date, "1", "99.00", status="PENDIENTE", receipt_key="A:3"),
    ])

    run = SyncService(reader).sync_day(db, make_source(), target_date)

    assert run.status == "success"
    assert run.rows_read == 4
    assert run.rows_matched == 3

    daily = db.execute(select(DailySalesSummary)).scalar_one()
    assert daily.gross_amount == Decimal("23.00")
    assert daily.payment_count == 3
    assert daily.receipt_count == 2

    payments = {
        row.payment_code: row
        for row in db.execute(select(PaymentMethodSummary)).scalars().all()
    }
    assert payments["1"].total_amount == Decimal("10.25")
    assert payments["2"].payment_label == "VISA"
    assert payments["4"].total_amount == Decimal("7.00")


def test_rerun_replaces_aggregates_without_duplicates() -> None:
    db = make_session()
    target_date = date(2022, 8, 6)
    source = make_source()

    SyncService(FixtureParadoxReader(records=[
        payment_record(target_date, "1", "10.00", receipt_key="A:1"),
    ])).sync_day(db, source, target_date)
    SyncService(FixtureParadoxReader(records=[
        payment_record(target_date, "1", "15.00", receipt_key="A:1"),
        payment_record(target_date, "2", "5.00", receipt_key="A:2"),
    ])).sync_day(db, source, target_date)

    daily_rows = db.execute(select(DailySalesSummary)).scalars().all()
    payment_rows = db.execute(select(PaymentMethodSummary)).scalars().all()

    assert len(daily_rows) == 1
    assert daily_rows[0].gross_amount == Decimal("20.00")
    assert len(payment_rows) == 2
    assert db.execute(select(SyncRun)).scalars().all()[-1].status == "success"


def test_empty_day_creates_zero_summary() -> None:
    db = make_session()
    target_date = date(2022, 8, 7)

    run = SyncService(FixtureParadoxReader(records=[])).sync_day(db, make_source(), target_date)

    assert run.status == "success"
    daily = db.execute(select(DailySalesSummary)).scalar_one()
    assert daily.gross_amount == Decimal("0.00")
    assert daily.payment_count == 0
    assert daily.receipt_count == 0


def test_failed_reader_records_failed_sync_run() -> None:
    db = make_session()
    target_date = date(2022, 8, 6)

    run = SyncService(FixtureParadoxReader(fail=FileNotFoundError("missing table"))).sync_day(
        db,
        make_source(),
        target_date,
    )

    assert run.status == "failed"
    assert "missing table" in (run.error_text or "")
    assert db.execute(select(DailySalesSummary)).scalars().all() == []


def test_unknown_payment_code_is_reported_and_still_aggregated() -> None:
    db = make_session()
    target_date = date(2022, 8, 6)

    run = SyncService(FixtureParadoxReader(records=[
        payment_record(target_date, "99", "3.50", receipt_key="A:1"),
    ])).sync_day(db, make_source(), target_date)

    assert run.status == "success"
    assert run.warnings == ["Unknown payment method code 99"]
    payment = db.execute(select(PaymentMethodSummary)).scalar_one()
    assert payment.payment_label == "Unknown 99"
    assert payment.total_amount == Decimal("3.50")

