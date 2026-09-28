"""Request-scoped dependencies: the container, the caller, and trip access resolved server-side."""

from __future__ import annotations

from fastapi import Depends, Request

from app.container import Container
from app.core.security import Principal, current_user, require_trip_role
from app.domain.models import CrewRole, Trip


def get_container(request: Request) -> Container:
    return request.app.state.container


async def trip_for(trip_id: str, minimum: CrewRole, principal: Principal, c: Container) -> Trip:
    trip = await c.store.get_trip(trip_id)
    require_trip_role(trip, principal, minimum)
    return trip


def trip_access(minimum: CrewRole):
    async def dep(trip_id: str, principal: Principal = Depends(current_user), c: Container = Depends(get_container)) -> Trip:
        return await trip_for(trip_id, minimum, principal, c)

    return dep
