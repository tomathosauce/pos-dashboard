import json
from functools import cached_property
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class PosSourceConfig(BaseModel):
    name: str
    path: str
    reader: str = "odbc"
    timezone: str = "America/Bogota"
    currency: str = "USD"
    odbc_connection_string: str | None = None
    odbc_dsn: str | None = None

    @property
    def resolved_path(self) -> Path:
        return Path(self.path).expanduser().resolve()


def _default_source_path() -> str:
    # app/core/config.py -> backend/app/core -> firestec folder
    return str(Path(__file__).resolve().parents[4])


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    database_url: str = "postgresql+psycopg://pos_dashboard:pos_dashboard@localhost:5432/pos_dashboard"
    api_cors_origins: str = "http://localhost:5173,http://127.0.0.1:5173"
    enable_scheduler: bool = True
    daily_sync_hour: int = 8
    daily_sync_minute: int = 0
    default_timezone: str = "America/Bogota"
    default_currency: str = "USD"
    pos_sources_json: str = Field(default_factory=lambda: json.dumps([{
        "name": "main",
        "path": _default_source_path(),
        "reader": "odbc",
        "timezone": "America/Bogota",
        "currency": "USD",
        "odbc_connection_string": None,
        "odbc_dsn": None,
    }]))

    @cached_property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.api_cors_origins.split(",") if origin.strip()]

    @cached_property
    def pos_sources(self) -> list[PosSourceConfig]:
        raw: Any = json.loads(self.pos_sources_json)
        if not isinstance(raw, list):
            raise ValueError("POS_SOURCES_JSON must be a JSON array")
        return [PosSourceConfig.model_validate(item) for item in raw]

    def get_source(self, name: str) -> PosSourceConfig:
        for source in self.pos_sources:
            if source.name == name:
                return source
        available = ", ".join(source.name for source in self.pos_sources)
        raise KeyError(f"Unknown POS source '{name}'. Available sources: {available}")


settings = Settings()
