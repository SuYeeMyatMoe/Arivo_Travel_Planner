"""Composition root. Everything is constructed once per process; tests build their own Container with fakes."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Callable

from app.ai.privacy import PrivacyGateway
from app.ai.router import ModelRouter
from app.bookings.providers.sandbox import SandboxFlightProvider, SandboxGroundProvider, SandboxHotelProvider, SandboxPaymentProvider
from app.bookings.service import BookingService
from app.config import Settings
from app.core.events import EventBus
from app.fx.providers import FrankfurterFX
from app.places.providers import SeedPlaceProvider
from app.planning.engine import PlannerDeps, TripPlanner
from app.planning.replan import Replanner
from app.store.base import Store
from app.store.memory import MemoryStore
from app.trips.service import TripService
from app.weather.providers import OpenMeteoProvider


@dataclass
class Container:
    settings: Settings
    store: Store
    places: SeedPlaceProvider
    router: ModelRouter
    privacy: PrivacyGateway
    bus: EventBus
    trips: TripService
    bookings: BookingService
    replanner: Replanner
    weather: OpenMeteoProvider | None
    fx: FrankfurterFX | None
    extras: dict = field(default_factory=dict)


def build_container(settings: Settings, *, store: Store | None = None, anthropic_client=None, weather=..., fx=...,
                    today: Callable[[], date] = date.today, trends: dict[str, float] | None = None) -> Container:
    store = store or MemoryStore()
    places = SeedPlaceProvider(settings.seed_dir)
    privacy = PrivacyGateway(settings.pii_key.get_secret_value())
    router = ModelRouter(settings=settings, privacy=privacy, client=anthropic_client)
    weather = OpenMeteoProvider() if weather is ... else weather
    fx = FrankfurterFX() if fx is ... else fx
    bus = EventBus(store)
    trends = trends if trends is not None else {}
    planner = TripPlanner(PlannerDeps(places=places, weather=weather, trends=trends, today=today))
    replanner = Replanner(places)
    trips = TripService(store, planner, replanner, router, bus)

    flights = SandboxFlightProvider()
    if settings.duffel_token:
        from app.bookings.providers.duffel import DuffelProvider

        flights = DuffelProvider(settings.duffel_token.get_secret_value())
    payments = SandboxPaymentProvider()
    if settings.stripe_secret_key:
        from app.bookings.providers.stripe_pay import StripePaymentProvider

        payments = StripePaymentProvider(settings.stripe_secret_key.get_secret_value(), auto_confirm_test_card=not settings.is_production)
    if settings.is_production and (getattr(flights, "sandbox", False) or getattr(payments, "sandbox", False)):
        raise RuntimeError("Production requires live flight and payment providers; sandbox providers are dev-only")
    bookings = BookingService(store, bus, flights=flights, hotels=SandboxHotelProvider(places), ground=SandboxGroundProvider(), payments=payments)
    return Container(settings=settings, store=store, places=places, router=router, privacy=privacy, bus=bus, trips=trips,
                     bookings=bookings, replanner=replanner, weather=weather, fx=fx, extras={"trends": trends})
