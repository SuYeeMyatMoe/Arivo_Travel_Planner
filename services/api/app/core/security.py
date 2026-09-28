"""Authentication (Supabase JWT) and resource authorization (ownership / crew role). Never trust client IDs."""

from __future__ import annotations

from dataclasses import dataclass

import jwt
from fastapi import Depends, Header, HTTPException, Request, status

from app.config import Settings, get_settings
from app.domain.models import CrewRole, Trip

ROLE_RANK = {CrewRole.VIEWER: 0, CrewRole.MEMBER: 1, CrewRole.EDITOR: 2, CrewRole.OWNER: 3}


@dataclass(frozen=True)
class Principal:
    user_id: str
    email: str | None = None
    display_name: str | None = None
    auth: str = "supabase"  # supabase | dev
    aal: str = "aal1"  # authenticator assurance level; step-up flows require aal2


def _unauthorized(msg: str = "Sign in required") -> HTTPException:
    return HTTPException(status.HTTP_401_UNAUTHORIZED, msg, headers={"WWW-Authenticate": "Bearer"})


async def current_user(request: Request, authorization: str | None = Header(default=None),
                       settings: Settings = Depends(get_settings)) -> Principal:
    if not authorization:
        raise _unauthorized()
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() == "dev":
        if not settings.allow_dev_auth or settings.is_production:
            raise _unauthorized("Dev auth disabled")
        user_id = token.strip()
        if not user_id or len(user_id) > 64 or not user_id.replace("-", "").replace("_", "").isalnum():
            raise _unauthorized("Invalid dev user")
        principal = Principal(user_id=user_id, display_name=user_id.split("-")[0].title(), auth="dev")
    elif scheme.lower() == "bearer":
        try:
            claims = jwt.decode(token, settings.supabase_jwt_secret.get_secret_value(), algorithms=["HS256"],
                                audience=settings.supabase_jwt_audience, options={"require": ["exp", "sub"]})
        except jwt.PyJWTError as e:
            raise _unauthorized("Invalid or expired session") from e
        meta = claims.get("user_metadata") or {}
        principal = Principal(user_id=claims["sub"], email=claims.get("email"), display_name=meta.get("full_name") or meta.get("name"),
                              aal=claims.get("aal", "aal1"))
    else:
        raise _unauthorized()
    request.state.user_id = principal.user_id
    return principal


def role_in_trip(trip: Trip, user_id: str) -> CrewRole | None:
    if trip.owner_id == user_id:
        return CrewRole.OWNER
    for m in trip.crew:
        if m.user_id == user_id:
            return m.role
    return None


def require_trip_role(trip: Trip | None, principal: Principal, minimum: CrewRole) -> CrewRole:
    """BOLA defence: resolve the caller's role from server-side membership. Unknown trip and no access look the same."""
    if trip is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Trip not found")
    role = role_in_trip(trip, principal.user_id)
    if role is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Trip not found")
    if ROLE_RANK[role] < ROLE_RANK[minimum]:
        raise HTTPException(status.HTTP_403_FORBIDDEN, f"Needs {minimum.value} access")
    return role
