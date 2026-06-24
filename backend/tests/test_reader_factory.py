from datetime import date
from decimal import Decimal

import pytest

from app.core.config import PosSourceConfig
from app.etl.odbc_reader import OdbcParadoxReader
from app.etl.pxlib_reader import PxlibParadoxReader
from app.etl.reader_factory import build_reader


def test_reader_factory_builds_odbc_reader() -> None:
    source = PosSourceConfig(name="main", path=".", reader="odbc")

    assert isinstance(build_reader(source), OdbcParadoxReader)


def test_reader_factory_builds_pxlib_reader() -> None:
    source = PosSourceConfig(name="main", path=".", reader="pxlib")

    assert isinstance(build_reader(source), PxlibParadoxReader)


def test_reader_factory_rejects_unknown_reader() -> None:
    source = PosSourceConfig(name="main", path=".", reader="mystery")

    with pytest.raises(ValueError, match="Unsupported Paradox reader"):
        build_reader(source)


def test_pxlib_reader_normalizes_payment_row() -> None:
    row = {
        "SERIE": "C002",
        "NUMERO": 22080602010450.0,
        "CODIGOFORMAPAGO": 1.0,
        "IMPORTE": 3.849,
        "FECHA": date(2022, 8, 6),
        "ESTADO": " cobrado ",
    }

    record = PxlibParadoxReader()._row_to_payment_record(row)

    assert record.business_date == date(2022, 8, 6)
    assert record.payment_code == "1"
    assert record.amount == Decimal("3.85")
    assert record.status == "COBRADO"
    assert record.receipt_key == "C002:22080602010450"

