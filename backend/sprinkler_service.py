"""Sprinkler backend service exposing authenticated HTTP endpoints.

This module is designed for Raspberry Pi deployments that control 24VAC sprinkler
valves via relay boards wired to GPIO pins. It uses pigpio for reliable timing
and enforces token-based authentication on every request.
"""
from __future__ import annotations

import asyncio
import os
from datetime import datetime, timedelta
from typing import Dict, List, Optional

import pigpio
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from starlette.responses import JSONResponse

# ---------------------------------------------------------------------------
# Configuration helpers
# ---------------------------------------------------------------------------

APP_VERSION = "1.0.0"
DEFAULT_GPIO_PINS = [4, 17, 27, 22, 5, 6, 13, 19]
DEFAULT_RUNTIME_MINUTES = 30
RAIN_LOCK_DEFAULT_HOURS = int(os.getenv("RAIN_LOCK_DEFAULT_HOURS", "24"))
API_TOKEN = os.getenv("SPRINKLER_API_TOKEN")
API_PORT = int(os.getenv("SPRINKLER_API_PORT", "8000"))
ALLOWED_ORIGINS = os.getenv("SPRINKLER_ALLOWED_ORIGINS", "").split(",") if os.getenv("SPRINKLER_ALLOWED_ORIGINS") else []

if API_TOKEN is None:
    raise RuntimeError("SPRINKLER_API_TOKEN is required in the environment")

GPIO_PINS: List[int] = [
    int(pin.strip()) for pin in os.getenv("SPRINKLER_GPIO_PINS", ",".join(str(p) for p in DEFAULT_GPIO_PINS)).split(",") if pin.strip()
]

# ---------------------------------------------------------------------------
# pigpio setup
# ---------------------------------------------------------------------------

pi = pigpio.pi()
if not pi.connected:
    raise RuntimeError("Failed to connect to pigpiod. Ensure 'sudo systemctl status pigpiod' shows active.")

for gpio in GPIO_PINS:
    pi.set_mode(gpio, pigpio.OUTPUT)
    pi.write(gpio, 1)  # Relays are active-low; set HIGH to keep valves off.

# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------

class ZoneState(BaseModel):
    zone: int
    gpio: int
    is_on: bool
    remaining_minutes: Optional[int] = None

class SystemStatus(BaseModel):
    version: str
    zones: List[ZoneState]
    rain_lock_expires_at: Optional[datetime]

# ---------------------------------------------------------------------------
# In-memory state
# ---------------------------------------------------------------------------

_active_jobs: Dict[int, asyncio.Task] = {}
_rain_lock_until: Optional[datetime] = None

# ---------------------------------------------------------------------------
# Authentication dependency
# ---------------------------------------------------------------------------

def require_token(request: Request) -> None:
    header = request.headers.get("authorization")
    if not header or header.strip() != f"Bearer {API_TOKEN}":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing or invalid token")

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

def _gpio_for_zone(zone: int) -> int:
    try:
        return GPIO_PINS[zone - 1]
    except IndexError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Zone not configured") from exc


def _remaining_minutes(task: asyncio.Task) -> Optional[int]:
    if task.done():
        return None
    seconds_left = getattr(task, "seconds_left", None)
    if seconds_left is None:
        return None
    return max(0, round(seconds_left() / 60))


async def _turn_zone_off(zone: int) -> None:
    gpio = _gpio_for_zone(zone)
    pi.write(gpio, 1)
    if zone in _active_jobs:
        _active_jobs.pop(zone, None)


async def _zone_timer(zone: int, duration_minutes: int) -> None:
    gpio = _gpio_for_zone(zone)
    pi.write(gpio, 0)  # energize relay
    end_time = datetime.utcnow() + timedelta(minutes=duration_minutes)

    def seconds_left() -> float:
        return max(0.0, (end_time - datetime.utcnow()).total_seconds())

    asyncio.current_task().seconds_left = seconds_left  # type: ignore[attr-defined]

    try:
        await asyncio.sleep(duration_minutes * 60)
    finally:
        pi.write(gpio, 1)  # de-energize relay
        _active_jobs.pop(zone, None)

# ---------------------------------------------------------------------------
# FastAPI application
# ---------------------------------------------------------------------------

app = FastAPI(title="Sprinkler Controller", version=APP_VERSION)

if ALLOWED_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=ALLOWED_ORIGINS,
        allow_methods=["*"],
        allow_headers=["*"]
    )

@app.get("/status", response_model=SystemStatus, dependencies=[Depends(require_token)])
async def get_status() -> SystemStatus:
    zones: List[ZoneState] = []
    for idx, gpio in enumerate(GPIO_PINS, start=1):
        is_on = pi.read(gpio) == 0
        remaining = _remaining_minutes(_active_jobs[idx]) if idx in _active_jobs else None
        zones.append(ZoneState(zone=idx, gpio=gpio, is_on=is_on, remaining_minutes=remaining))

    return SystemStatus(
        version=APP_VERSION,
        zones=zones,
        rain_lock_expires_at=_rain_lock_until,
    )


@app.post("/zone/on/{zone}", dependencies=[Depends(require_token)])
async def turn_zone_on(zone: int, minutes: int = DEFAULT_RUNTIME_MINUTES) -> JSONResponse:
    if _rain_lock_until and datetime.utcnow() < _rain_lock_until:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Rain lock active")

    if minutes <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Runtime must be positive")

    if zone in _active_jobs:
        _active_jobs[zone].cancel()

    task = asyncio.create_task(_zone_timer(zone, minutes))
    _active_jobs[zone] = task
    return JSONResponse({"status": "on", "zone": zone, "minutes": minutes})


@app.post("/zone/off/{zone}", dependencies=[Depends(require_token)])
async def turn_zone_off(zone: int) -> JSONResponse:
    await _turn_zone_off(zone)
    return JSONResponse({"status": "off", "zone": zone})


@app.post("/rain-lock", dependencies=[Depends(require_token)])
async def enable_rain_lock(hours: int = RAIN_LOCK_DEFAULT_HOURS) -> JSONResponse:
    global _rain_lock_until
    if hours <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Hours must be positive")

    _rain_lock_until = datetime.utcnow() + timedelta(hours=hours)
    for zone in list(_active_jobs.keys()):
        await _turn_zone_off(zone)
    return JSONResponse({"rain_lock_expires_at": _rain_lock_until.isoformat()})


@app.delete("/rain-lock", dependencies=[Depends(require_token)])
async def clear_rain_lock() -> JSONResponse:
    global _rain_lock_until
    _rain_lock_until = None
    return JSONResponse({"rain_lock_expires_at": None})


@app.exception_handler(Exception)
async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"error": "unexpected_error", "details": str(exc)},
    )
