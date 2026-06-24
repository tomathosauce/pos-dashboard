from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import Date, DateTime, Integer, JSON, Numeric, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class DailySalesSummary(Base):
    __tablename__ = "daily_sales_summaries"
    __table_args__ = (UniqueConstraint("source_name", "business_date", name="uq_daily_sales_source_date"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    source_name: Mapped[str] = mapped_column(String(80), nullable=False)
    business_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, default="USD")
    gross_amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    payment_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    receipt_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    source_row_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


class PaymentMethodSummary(Base):
    __tablename__ = "payment_method_summaries"
    __table_args__ = (
        UniqueConstraint(
            "source_name",
            "business_date",
            "payment_code",
            name="uq_payment_method_source_date_code",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    source_name: Mapped[str] = mapped_column(String(80), nullable=False)
    business_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    payment_code: Mapped[str] = mapped_column(String(40), nullable=False)
    payment_label: Mapped[str] = mapped_column(String(120), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, default="USD")
    total_amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    payment_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


class SyncRun(Base):
    __tablename__ = "sync_runs"

    id: Mapped[int] = mapped_column(primary_key=True)
    source_name: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    business_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    rows_read: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    rows_matched: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    warnings: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    error_text: Mapped[str | None] = mapped_column(Text, nullable=True)

