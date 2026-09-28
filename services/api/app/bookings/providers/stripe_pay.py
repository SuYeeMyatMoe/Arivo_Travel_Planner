"""Stripe PaymentProvider (test mode outside production). Manual capture: authorize → supplier order → capture | void.

Card details never touch Arivo: the mobile PaymentSheet confirms the PaymentIntent with Stripe directly using the
client_secret; the backend only ever sees PaymentIntent ids. Every call carries an idempotency key.
"""

from __future__ import annotations

import asyncio

import stripe

from app.bookings.providers.base import PaymentAuth
from app.domain.models import Money


class StripePaymentProvider:
    name = "stripe"

    def __init__(self, secret_key: str, auto_confirm_test_card: bool = False):
        self.sandbox = secret_key.startswith(("sk_test_", "rk_test_"))
        self.client = stripe.StripeClient(secret_key)
        # Server-side demo only (no phone): confirm with Stripe's documented test PaymentMethod. Never in production.
        self.auto_confirm = auto_confirm_test_card and self.sandbox

    async def authorize(self, amount: Money, idempotency_key: str, metadata: dict) -> PaymentAuth:
        params: dict = {
            "amount": amount.amount_minor, "currency": amount.currency.lower(), "capture_method": "manual",
            "metadata": {k: str(v) for k, v in metadata.items()},
            "automatic_payment_methods": {"enabled": True, "allow_redirects": "never"},
        }
        if self.auto_confirm:
            params.update({"payment_method": "pm_card_visa", "confirm": True})
        pi = await asyncio.to_thread(self.client.payment_intents.create, params, {"idempotency_key": idempotency_key})
        if pi.status == "requires_capture":
            return PaymentAuth(payment_ref=pi.id, status="authorized", risk=_risk(pi))
        if pi.status in {"requires_payment_method", "requires_confirmation", "requires_action"}:
            return PaymentAuth(payment_ref=pi.id, status="requires_action", client_secret=pi.client_secret)
        return PaymentAuth(payment_ref=pi.id, status="failed")

    async def capture(self, payment_ref: str, idempotency_key: str) -> None:
        await asyncio.to_thread(self.client.payment_intents.capture, payment_ref, {}, {"idempotency_key": idempotency_key})

    async def void(self, payment_ref: str, idempotency_key: str) -> None:
        await asyncio.to_thread(self.client.payment_intents.cancel, payment_ref, {}, {"idempotency_key": idempotency_key})

    async def refund(self, payment_ref: str, amount: Money, idempotency_key: str) -> str:
        r = await asyncio.to_thread(self.client.refunds.create, {"payment_intent": payment_ref, "amount": amount.amount_minor},
                                    {"idempotency_key": idempotency_key})
        return r.id

    async def status(self, payment_ref: str) -> str:
        pi = await asyncio.to_thread(self.client.payment_intents.retrieve, payment_ref)
        return pi.status


def _risk(pi) -> str | None:
    try:
        return pi.latest_charge and None  # Radar outcome is read from the charge webhook; kept out of the hot path
    except Exception:  # noqa: BLE001
        return None
