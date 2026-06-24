from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from typing import Any


def clean_code(value: Any) -> str:
    if value is None:
        return "UNKNOWN"
    try:
        numeric = Decimal(str(value))
        if numeric == numeric.to_integral_value():
            return str(int(numeric))
    except InvalidOperation:
        pass
    return str(value).strip()


def coerce_decimal(value: Any) -> Decimal:
    if value is None:
        return Decimal("0.00")
    return Decimal(str(value)).quantize(Decimal("0.01"))


def coerce_date(value: Any) -> date:
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    return date.fromisoformat(str(value))


def attr_or_item(row: Any, name: str) -> Any:
    if isinstance(row, dict):
        return row.get(name)
    try:
        return getattr(row, name)
    except AttributeError:
        return row[name]

