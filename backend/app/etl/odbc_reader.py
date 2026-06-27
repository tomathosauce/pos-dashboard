from datetime import date
from pathlib import Path
from typing import Any

from app.core.config import PosSourceConfig
from app.etl.types import PaymentMethod, PaymentRecord
from app.etl.value_utils import clean_code, coerce_date, coerce_decimal


class OdbcParadoxReader:
    def _default_connection_string(self, pyodbc: Any, source: PosSourceConfig) -> str:
        path = str(source.resolved_path)
        driver = "Microsoft Paradox Driver (*.db)"
        for candidate in pyodbc.drivers():
            normalized = candidate.lower().replace(" ", "")
            if "paradox" in normalized and "*.db" in normalized:
                driver = candidate
                break
        return f"Driver={{{driver}}};DefaultDir={path};DBQ={path};FIL=Paradox 5.X;ReadOnly=1"

    def _connect(self, source: PosSourceConfig):
        try:
            import pyodbc
        except ImportError as exc:
            raise RuntimeError(
                "pyodbc is not installed. Install backend/requirements-odbc.txt on the Windows "
                "machine that has the Paradox/BDE ODBC driver."
            ) from exc

        if source.odbc_connection_string:
            connection_string = source.odbc_connection_string
        elif source.odbc_dsn:
            connection_string = f"DSN={source.odbc_dsn};ReadOnly=1"
        else:
            connection_string = self._default_connection_string(pyodbc, source)

        return pyodbc.connect(connection_string, autocommit=True, timeout=30)

    def load_payment_methods(self, source: PosSourceConfig) -> dict[str, PaymentMethod]:
        self._assert_table_exists(source.resolved_path, "tformas.DB")
        with self._connect(source) as connection:
            rows = connection.cursor().execute("SELECT CODIGO, DESCRIPCION FROM tformas").fetchall()

        methods: dict[str, PaymentMethod] = {}
        for row in rows:
            code = clean_code(row.CODIGO)
            label = str(row.DESCRIPCION or code).strip() or code
            methods[code] = PaymentMethod(code=code, label=label)
        return methods

    def iter_payment_records(self, source: PosSourceConfig, business_date: date | None = None) -> list[PaymentRecord]:
        self._assert_table_exists(source.resolved_path, "tdocumentos_formas.DB")
        query = "SELECT SERIE, NUMERO, CODIGOFORMAPAGO, IMPORTE, FECHA, ESTADO FROM tdocumentos_formas"
        params: tuple[date, ...] = ()
        if business_date is not None:
            query = f"{query} WHERE FECHA >= ? AND FECHA <= ?"
            params = (business_date, business_date)
        with self._connect(source) as connection:
            rows = connection.cursor().execute(query, *params).fetchall()

        return [self._row_to_payment_record(row) for row in rows]

    def _row_to_payment_record(self, row: Any) -> PaymentRecord:
        payment_code = clean_code(row.CODIGOFORMAPAGO)
        amount = coerce_decimal(row.IMPORTE)
        status = str(row.ESTADO or "").strip().upper()
        receipt_key = f"{str(row.SERIE or '').strip()}:{clean_code(row.NUMERO)}"
        return PaymentRecord(
            business_date=coerce_date(row.FECHA),
            payment_code=payment_code,
            amount=amount,
            status=status,
            receipt_key=receipt_key,
        )

    def _assert_table_exists(self, source_path: Path, table_name: str) -> None:
        if not (source_path / table_name).exists() and not (source_path / table_name.lower()).exists():
            raise FileNotFoundError(f"Missing required Paradox table {table_name} in {source_path}")
