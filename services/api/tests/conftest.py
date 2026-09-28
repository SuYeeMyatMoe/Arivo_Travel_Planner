from __future__ import annotations

import logging
from datetime import date

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.container import build_container
from app.main import create_app

logging.getLogger("httpx").setLevel(logging.WARNING)
TODAY = date(2026, 9, 24)
DEMO = "I'm visiting Tokyo for five days with three friends. Around RM4,000 each. We love anime, food and photography but hate rushing."


def make_settings(**kw) -> Settings:
    base = dict(env="local", storage="memory", allow_dev_auth=True, anthropic_api_key=None, duffel_token=None, stripe_secret_key=None,
                rate_limit_per_minute=10_000)
    base.update(kw)
    return Settings(_env_file=None, **base)


@pytest.fixture(scope="session")
def settings() -> Settings:
    return make_settings()


@pytest.fixture
def container(settings):
    # offline: no weather/FX network calls in unit tests
    return build_container(settings, weather=None, fx=None, today=lambda: TODAY)


@pytest.fixture
def client(settings, container) -> TestClient:
    app = create_app(settings, container)
    return TestClient(app)


def auth(user: str) -> dict:
    return {"Authorization": f"Dev {user}"}


@pytest.fixture(scope="session")
def demo_trip_payload() -> dict:
    return {"text": DEMO, "quick": {"start_date": "2026-11-16"}}
