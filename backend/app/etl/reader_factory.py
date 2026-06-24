from app.core.config import PosSourceConfig
from app.etl.odbc_reader import OdbcParadoxReader
from app.etl.pxlib_reader import PxlibParadoxReader
from app.etl.types import ParadoxReader


def build_reader(source: PosSourceConfig) -> ParadoxReader:
    reader = source.reader.lower().strip()
    if reader == "odbc":
        return OdbcParadoxReader()
    if reader == "pxlib":
        return PxlibParadoxReader()
    raise ValueError(f"Unsupported Paradox reader '{source.reader}'. Use 'odbc' or 'pxlib'.")

