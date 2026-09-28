"""Runtime settings. Every secret comes from the environment (never from the mobile client)."""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_ROOT = Path(__file__).resolve().parents[3]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=(REPO_ROOT / ".env", ".env"), env_file_encoding="utf-8", extra="ignore")

    env: Literal["local", "development", "staging", "production"] = "local"
    api_public_url: str = "http://localhost:8787"

    # --- persistence ---------------------------------------------------------------------------------------------
    # "memory" runs the whole API without Postgres/Redis (tests, demos, offline laptops). "postgres" uses Supabase.
    storage: Literal["memory", "postgres"] = "memory"
    database_url: str = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
    redis_url: str | None = None
    seed_dir: Path = REPO_ROOT / "supabase" / "seed" / "places"

    # --- auth (Supabase) -----------------------------------------------------------------------------------------
    supabase_url: str = "http://127.0.0.1:54321"
    supabase_jwt_secret: SecretStr = SecretStr("super-secret-jwt-token-with-at-least-32-characters-long")  # local default
    supabase_jwt_audience: str = "authenticated"
    # Local/dev only: accept `Authorization: Dev <user-id>` so the demo and tests run without Supabase Auth.
    allow_dev_auth: bool = True

    # --- AI ------------------------------------------------------------------------------------------------------
    anthropic_api_key: SecretStr | None = None
    model_extract: str = "claude-haiku-4-5"  # intent parsing, classification, entity extraction
    model_plan: str = "claude-sonnet-5"  # explanations, itinerary narration, guide agent
    model_reason: str = "claude-opus-5-5"  # hard multi-constraint replanning escalation
    ai_timeout_s: float = 45.0
    pii_key: SecretStr = SecretStr("dev-only-pii-key-change-me-0123456789abcdef")  # Fernet key material for token maps

    # --- providers -----------------------------------------------------------------------------------------------
    ors_api_key: SecretStr | None = None
    youtube_api_key: SecretStr | None = None
    ticketmaster_key: SecretStr | None = None
    duffel_token: SecretStr | None = None  # must be a *test* token outside production
    duffel_webhook_secret: SecretStr | None = None
    stripe_secret_key: SecretStr | None = None  # sk_test_… outside production
    stripe_webhook_secret: SecretStr | None = None
    stripe_publishable_key: str | None = None

    # --- safety rails --------------------------------------------------------------------------------------------
    rate_limit_per_minute: int = 120
    booking_rate_limit_per_hour: int = 12
    cors_origins: list[str] = Field(default_factory=lambda: ["http://localhost:5180", "http://localhost:8081"])

    @property
    def is_production(self) -> bool:
        return self.env == "production"

    def assert_safe(self) -> None:
        """Refuse to boot with configurations that could create live bookings or accept forged identities."""
        if self.is_production:
            if self.allow_dev_auth:
                raise RuntimeError("ALLOW_DEV_AUTH must be false in production")
            if self.pii_key.get_secret_value().startswith("dev-only"):
                raise RuntimeError("PII_KEY must be set in production")
        else:
            token = self.duffel_token.get_secret_value() if self.duffel_token else ""
            if token and not token.startswith("duffel_test_"):
                raise RuntimeError("Non-production environments may only use a Duffel *test* token")
            sk = self.stripe_secret_key.get_secret_value() if self.stripe_secret_key else ""
            if sk and not sk.startswith(("sk_test_", "rk_test_")):
                raise RuntimeError("Non-production environments may only use Stripe *test* keys")


@lru_cache
def get_settings() -> Settings:
    s = Settings()
    s.assert_safe()
    return s
