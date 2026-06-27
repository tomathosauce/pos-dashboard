import json

import pytest

from app.core.config import Settings


def test_pos_sources_accepts_json_array() -> None:
    settings = Settings(pos_sources_json=json.dumps([
        {"name": "main", "path": ".", "reader": "odbc"},
    ]))

    assert len(settings.pos_sources) == 1
    assert settings.pos_sources[0].name == "main"


def test_pos_sources_accepts_legacy_single_object() -> None:
    settings = Settings(pos_sources_json=json.dumps(
        {"name": "main", "path": ".", "reader": "odbc"},
    ))

    assert len(settings.pos_sources) == 1
    assert settings.pos_sources[0].name == "main"


def test_pos_sources_rejects_non_collection_json() -> None:
    settings = Settings(pos_sources_json=json.dumps("main"))

    with pytest.raises(ValueError, match="POS_SOURCES_JSON must be a JSON array"):
        settings.pos_sources
