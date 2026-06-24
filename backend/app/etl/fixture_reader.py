from datetime import date
from decimal import Decimal

from app.core.config import PosSourceConfig
from app.etl.types import PaymentMethod, PaymentRecord


class FixtureParadoxReader:
    def __init__(
        self,
        methods: dict[str, str] | None = None,
        records: list[PaymentRecord] | None = None,
        fail: Exception | None = None,
    ) -> None:
        self.methods = methods or {"1": "CONTADO", "2": "VISA", "4": "MASTER CARD"}
        self.records = records or []
        self.fail = fail

    def load_payment_methods(self, source: PosSourceConfig) -> dict[str, PaymentMethod]:
        if self.fail:
            raise self.fail
        return {code: PaymentMethod(code=code, label=label) for code, label in self.methods.items()}

    def iter_payment_records(self, source: PosSourceConfig, business_date: date) -> list[PaymentRecord]:
        if self.fail:
            raise self.fail
        return [record for record in self.records if record.business_date == business_date]


def payment_record(
    business_date: date,
    code: str,
    amount: str,
    status: str = "PAGADO",
    receipt_key: str = "A:1",
) -> PaymentRecord:
    return PaymentRecord(
        business_date=business_date,
        payment_code=code,
        amount=Decimal(amount),
        status=status,
        receipt_key=receipt_key,
    )

