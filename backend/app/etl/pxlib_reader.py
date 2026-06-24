from datetime import date
from pathlib import Path
from typing import Any

from app.core.config import PosSourceConfig
from app.etl.types import PaymentMethod, PaymentRecord
from app.etl.value_utils import attr_or_item, clean_code, coerce_date, coerce_decimal


class PxlibParadoxReader:
    def load_payment_methods(self, source: PosSourceConfig) -> dict[str, PaymentMethod]:
        table = self._open_table(source.resolved_path, "tformas.DB")
        methods: dict[str, PaymentMethod] = {}
        try:
            for index in range(len(table)):
                row = table[index]
                code = clean_code(row["CODIGO"])
                label = str(row["DESCRIPCION"] or code).strip() or code
                methods[code] = PaymentMethod(code=code, label=label)
            return methods
        finally:
            self._close_table(table)

    def iter_payment_records(self, source: PosSourceConfig, business_date: date) -> list[PaymentRecord]:
        table = self._open_table(source.resolved_path, "tdocumentos_formas.DB")
        records: list[PaymentRecord] = []
        try:
            for index in range(len(table)):
                row = table[index]
                row_date = coerce_date(row["FECHA"])
                if row_date != business_date:
                    continue
                records.append(self._row_to_payment_record(row))
            return records
        finally:
            self._close_table(table)

    def _row_to_payment_record(self, row: Any) -> PaymentRecord:
        business_date = coerce_date(attr_or_item(row, "FECHA"))
        payment_code = clean_code(attr_or_item(row, "CODIGOFORMAPAGO"))
        amount = coerce_decimal(attr_or_item(row, "IMPORTE"))
        status = str(attr_or_item(row, "ESTADO") or "").strip().upper()
        receipt_key = f"{str(attr_or_item(row, 'SERIE') or '').strip()}:{clean_code(attr_or_item(row, 'NUMERO'))}"
        return PaymentRecord(
            business_date=business_date,
            payment_code=payment_code,
            amount=amount,
            status=status,
            receipt_key=receipt_key,
        )

    def _open_table(self, source_path: Path, table_name: str):
        try:
            from pypxlib import Table
        except ImportError as exc:
            raise RuntimeError(
                "pypxlib is not installed. Install backend/requirements-pxlib.txt to use reader='pxlib'."
            ) from exc

        table_path = self._find_table(source_path, table_name)
        return Table(str(table_path))

    def _find_table(self, source_path: Path, table_name: str) -> Path:
        candidates = [
            source_path / table_name,
            source_path / table_name.lower(),
            source_path / table_name.upper(),
        ]
        for candidate in candidates:
            if candidate.exists():
                return candidate
        raise FileNotFoundError(f"Missing required Paradox table {table_name} in {source_path}")

    def _close_table(self, table: Any) -> None:
        close = getattr(table, "close", None)
        if close is not None:
            close()

