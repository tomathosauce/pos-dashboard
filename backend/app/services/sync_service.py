from collections import defaultdict
from datetime import date, datetime, timezone
from decimal import Decimal

from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.core.config import PosSourceConfig
from app.etl.reader_factory import build_reader
from app.etl.types import ParadoxReader
from app.models.reporting import DailySalesSummary, PaymentMethodSummary, SyncRun

PAID_STATUSES = {"PAGADO", "COBRADO"}


class SyncService:
    def __init__(self, reader: ParadoxReader | None = None) -> None:
        self.reader = reader

    def sync_day(self, db: Session, source: PosSourceConfig, business_date: date) -> SyncRun:
        run = SyncRun(
            source_name=source.name,
            business_date=business_date,
            status="running",
            warnings=[],
        )
        db.add(run)
        db.commit()
        db.refresh(run)

        try:
            reader = self.reader or build_reader(source)
            methods = reader.load_payment_methods(source)
            records = reader.iter_payment_records(source, business_date)
            rows_read = len(records)
            matched_records = [record for record in records if record.status.upper() in PAID_STATUSES]

            totals_by_code: dict[str, Decimal] = defaultdict(lambda: Decimal("0.00"))
            counts_by_code: dict[str, int] = defaultdict(int)
            receipt_keys: set[str] = set()
            warnings: list[str] = []

            for record in matched_records:
                totals_by_code[record.payment_code] += record.amount
                counts_by_code[record.payment_code] += 1
                receipt_keys.add(record.receipt_key)
                if record.payment_code not in methods:
                    warnings.append(f"Unknown payment method code {record.payment_code}")

            warnings = sorted(set(warnings))
            total_amount = sum(totals_by_code.values(), Decimal("0.00"))

            db.execute(
                delete(PaymentMethodSummary).where(
                    PaymentMethodSummary.source_name == source.name,
                    PaymentMethodSummary.business_date == business_date,
                )
            )
            db.execute(
                delete(DailySalesSummary).where(
                    DailySalesSummary.source_name == source.name,
                    DailySalesSummary.business_date == business_date,
                )
            )

            db.add(
                DailySalesSummary(
                    source_name=source.name,
                    business_date=business_date,
                    currency=source.currency,
                    gross_amount=total_amount,
                    payment_count=len(matched_records),
                    receipt_count=len(receipt_keys),
                    source_row_count=rows_read,
                )
            )

            for code, amount in sorted(totals_by_code.items(), key=lambda item: item[0]):
                method = methods.get(code)
                db.add(
                    PaymentMethodSummary(
                        source_name=source.name,
                        business_date=business_date,
                        payment_code=code,
                        payment_label=method.label if method else f"Unknown {code}",
                        currency=source.currency,
                        total_amount=amount,
                        payment_count=counts_by_code[code],
                    )
                )

            run.status = "success"
            run.finished_at = datetime.now(timezone.utc)
            run.rows_read = rows_read
            run.rows_matched = len(matched_records)
            run.warnings = warnings
            db.commit()
            db.refresh(run)
            return run
        except Exception as exc:
            db.rollback()
            run = db.get(SyncRun, run.id)
            if run is None:
                raise
            run.status = "failed"
            run.finished_at = datetime.now(timezone.utc)
            run.error_text = str(exc)
            db.commit()
            db.refresh(run)
            return run
