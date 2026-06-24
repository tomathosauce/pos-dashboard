from datetime import date
from decimal import Decimal

from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session

from app.models.reporting import DailySalesSummary, PaymentMethodSummary, SyncRun


def _source_filter(statement: Select, model, source: str) -> Select:
    if source != "all":
        return statement.where(model.source_name == source)
    return statement


def get_summary(db: Session, start_date: date, end_date: date, source: str) -> dict:
    summary_stmt = select(
        func.coalesce(func.sum(DailySalesSummary.gross_amount), 0),
        func.coalesce(func.sum(DailySalesSummary.payment_count), 0),
        func.coalesce(func.sum(DailySalesSummary.receipt_count), 0),
        func.coalesce(func.sum(DailySalesSummary.source_row_count), 0),
        func.min(DailySalesSummary.currency),
    ).where(DailySalesSummary.business_date >= start_date, DailySalesSummary.business_date <= end_date)
    summary_stmt = _source_filter(summary_stmt, DailySalesSummary, source)
    total_amount, payment_count, receipt_count, source_row_count, currency = db.execute(summary_stmt).one()

    last_sync_stmt = select(SyncRun).order_by(SyncRun.started_at.desc()).limit(1)
    if source != "all":
        last_sync_stmt = last_sync_stmt.where(SyncRun.source_name == source)
    last_sync = db.execute(last_sync_stmt).scalar_one_or_none()

    by_day_stmt = select(
        DailySalesSummary.business_date,
        func.coalesce(func.sum(DailySalesSummary.gross_amount), 0),
        func.coalesce(func.sum(DailySalesSummary.receipt_count), 0),
    ).where(DailySalesSummary.business_date >= start_date, DailySalesSummary.business_date <= end_date)
    by_day_stmt = _source_filter(by_day_stmt, DailySalesSummary, source)
    by_day_stmt = by_day_stmt.group_by(DailySalesSummary.business_date).order_by(DailySalesSummary.business_date)

    return {
        "from": start_date,
        "to": end_date,
        "source": source,
        "currency": currency or "USD",
        "total_amount": Decimal(total_amount),
        "payment_count": int(payment_count or 0),
        "receipt_count": int(receipt_count or 0),
        "source_row_count": int(source_row_count or 0),
        "last_sync": last_sync,
        "days": [
            {
                "business_date": row[0],
                "total_amount": Decimal(row[1]),
                "receipt_count": int(row[2] or 0),
            }
            for row in db.execute(by_day_stmt).all()
        ],
    }


def get_payments(db: Session, start_date: date, end_date: date, source: str) -> list[dict]:
    statement = select(
        PaymentMethodSummary.payment_code,
        PaymentMethodSummary.payment_label,
        func.min(PaymentMethodSummary.currency),
        func.coalesce(func.sum(PaymentMethodSummary.total_amount), 0),
        func.coalesce(func.sum(PaymentMethodSummary.payment_count), 0),
    ).where(PaymentMethodSummary.business_date >= start_date, PaymentMethodSummary.business_date <= end_date)
    statement = _source_filter(statement, PaymentMethodSummary, source)
    statement = statement.group_by(
        PaymentMethodSummary.payment_code,
        PaymentMethodSummary.payment_label,
    ).order_by(func.sum(PaymentMethodSummary.total_amount).desc())

    return [
        {
            "payment_code": row[0],
            "payment_label": row[1],
            "currency": row[2] or "USD",
            "total_amount": Decimal(row[3]),
            "payment_count": int(row[4] or 0),
        }
        for row in db.execute(statement).all()
    ]

