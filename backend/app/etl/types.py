from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from typing import Protocol

from app.core.config import PosSourceConfig


@dataclass(frozen=True)
class PaymentMethod:
    code: str
    label: str


@dataclass(frozen=True)
class PaymentRecord:
    business_date: date
    payment_code: str
    amount: Decimal
    status: str
    receipt_key: str


class ParadoxReader(Protocol):
    def load_payment_methods(self, source: PosSourceConfig) -> dict[str, PaymentMethod]:
        ...

    def iter_payment_records(self, source: PosSourceConfig, business_date: date) -> list[PaymentRecord]:
        ...

