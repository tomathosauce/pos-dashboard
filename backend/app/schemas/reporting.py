from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict


class SourceOut(BaseModel):
    name: str
    path: str
    reader: str
    timezone: str
    currency: str


class SyncRunOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    source_name: str
    business_date: date
    status: str
    started_at: datetime
    finished_at: datetime | None
    rows_read: int
    rows_matched: int
    warnings: list[str]
    error_text: str | None


class SummaryDayOut(BaseModel):
    business_date: date
    total_amount: Decimal
    receipt_count: int


class DashboardSummaryOut(BaseModel):
    from_date: date
    to_date: date
    source: str
    currency: str
    total_amount: Decimal
    payment_count: int
    receipt_count: int
    source_row_count: int
    last_sync: SyncRunOut | None
    days: list[SummaryDayOut]


class PaymentSummaryOut(BaseModel):
    payment_code: str
    payment_label: str
    currency: str
    total_amount: Decimal
    payment_count: int
