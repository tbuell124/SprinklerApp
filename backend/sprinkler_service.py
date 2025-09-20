# FILE: sprinkler_service.py
"""
Sprinkler backend service (auth'd FastAPI) — pigpio, rain-lock, timers.
- Default GPIO pins expanded to 16 to match app.py (override via SPRINKLER_GPIO_PINS)
- Active-low relays: HIGH = off, LOW = on
"""

from __future__ import annotations

import asyncio
import os
from datetime import datetime, timedelta
from typing import Dict, List, Optional

import pigpio
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

APP_VERSION = "1.1.0"
# Expanded 16-pin default to match app.py
DEFAULT_GPIO_PINS = [12, 16, 20, 21, 26, 19, 13, 6, 5, 11, 9, 10, 22, 27, 17, 4]
DEFAULT_RUNTIME_MINUTES = 30
RAIN_LOCK_DEFAULT_HOURS = int(os.getenv("RAIN_LOCK_DEFAULT_HOURS", "24"))
API_TOKEN = os.getenv("SPRINKLER_API_TOKEN")
API_PORT = int(os.getenv("SPRINKLER_API_PORT", "8000"))
ALLOWED_ORIGINS = (
    os.getenv("SPRINKLER_ALLOWED_ORIGINS", "").split(",")
    if os.getenv("SPRINKLER_ALLOWED_ORIGINS")
    else []
)

if API_TOKEN is None:
    raise RuntimeError("SPRINKLER_API_TOKEN is required in the environment")

def _parse_int_csv(value: str) -> List[int]:
    out: List[int] = []
    for tok in (value or "").split(","):
        tok = tok.strip()
        if not tok:
            continue
        try:
            out.append(int(tok))
        except ValueError:
            continue
    return out

# Allow legacy override of mapping (zone index -> GPIO pin)
GPIO_PINS: List[int] = _parse_int_csv(os.getenv("SPRINKLER_GPIO_PINS", "")) or DEFAULT_GPIO_PINS

# ---------------------------------------------------------------------------
# pigpio initialization (active-low: write 1=OFF, 0=ON)
# ---------------------------------------------------------------------------

pi = pigpio.pi()
if not pi.connected:
    raise RuntimeError(
        "Failed to connect to pigpiod. Start it with: sudo systemctl enable --now pigpiod"
    )

for gpio in GPIO_PINS:
    pi.set_mode(gpio, pigpio.OUTPUT)
    pi.write(gpio, 1)  # default OFF

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

_active_jobs: Dict[int, Dict[str, object]] = {}  # zone -> {"task": Task, "until": datetime}
_rain_lock_until: Optional[datetime] = None

# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class StartZoneRequest(BaseModel):
    minutes: int = Field(default=DEFAULT_RUNTIME_MINUTES, ge=1, le=12 * 60)

class RainLockRequest(BaseModel):
    hours: int = Field(default=RAIN_LOCK_DEFAULT_HOURS, ge=1, le=14 * 24)

# ---------------------------------------------------------------------------
# Auth
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
    except Exception:
        raise HTTPException(status_code=400, detail=f"Zone {zone} is out of range 1..{len(GPIO_PINS)}")

def _minutes_left(zone: int) -> Optional[int]:
    job = _active_jobs.get(zone)
    if not job:
        return None
    until = job.get("until")
    if not isinstance(until, datetime):
        return None
    delta = (until - datetime.utcnow()).total_seconds()
    if delta <= 0:
        return 0
    return int(round(delta / 60.0))

async def _turn_zone_off(zone: int) -> None:
    gpio = _gpio_for_zone(zone)
    pi.write(gpio, 1)
    if zone in _active_jobs:
        _active_jobs.pop(zone, None)

async def _zone_timer(zone: int, duration_minutes: int) -> None:
    gpio = _gpio_for_zone(zone)
    pi.write(gpio, 0)  # ON
    try:
        await asyncio.sleep(duration_minutes * 60)
    finally:
        pi.write(gpio, 1)  # OFF
        if zone in _active_jobs:
            _active_jobs.pop(zone, None)

# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------

app = FastAPI(title="Sprinkler Service", version=APP_VERSION)
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS or ["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/status", dependencies=[Depends(require_token)])
async def get_status() -> JSONResponse:
    zones = []
    for idx, gpio in enumerate(GPIO_PINS, start=1):
        on = pi.read(gpio) == 0  # active-low
        zones.append(
            {
                "zone": idx,
                "gpio": gpio,
                "on": bool(on),
                "minutes_left": _minutes_left(idx),
            }
        )
    return JSONResponse(
        {
            "version": APP_VERSION,
            "rain_lock_expires_at": _rain_lock_until.isoformat() + "Z" if _rain_lock_until else None,
            "zones": zones,
        }
    )

@app.post("/zone/on/{zone}", dependencies=[Depends(require_token)])
async def start_zone(zone: int, payload: StartZoneRequest) -> JSONResponse:
    global _active_jobs
    if _rain_lock_until and datetime.utcnow() < _rain_lock_until:
        raise HTTPException(
            status_code=423, detail=f"Rain lock in effect until {_rain_lock_until.isoformat()}Z"
        )
    # Stop any existing timer
    if zone in _active_jobs:
        task = _active_jobs[zone].get("task")
        if isinstance(task, asyncio.Task) and not task.done():
            task.cancel()
            try:
                await task
            except Exception:
                pass
        _active_jobs.pop(zone, None)

    # Start new timer
    until = datetime.utcnow() + timedelta(minutes=payload.minutes)
    task = asyncio.create_task(_zone_timer(zone, payload.minutes))
    _active_jobs[zone] = {"task": task, "until": until}
    return JSONResponse(
        {"zone": zone, "gpio": _gpio_for_zone(zone), "on": True, "minutes_left": payload.minutes}
    )

@app.post("/zone/off/{zone}", dependencies=[Depends(require_token)])
async def stop_zone(zone: int) -> JSONResponse:
    # Cancel any active timer
    if zone in _active_jobs:
        task = _active_jobs[zone].get("task")
        if isinstance(task, asyncio.Task) and not task.done():
            task.cancel()
            try:
                await task
            except Exception:
                pass
        _active_jobs.pop(zone, None)
    # Force OFF
    await _turn_zone_off(zone)
    return JSONResponse({"zone": zone, "gpio": _gpio_for_zone(zone), "on": False, "minutes_left": 0})

@app.post("/rain-lock", dependencies=[Depends(require_token)])
async def set_rain_lock(body: RainLockRequest) -> JSONResponse:
    global _rain_lock_until
    _rain_lock_until = datetime.utcnow() + timedelta(hours=body.hours)
    # Turn everything off immediately
    tasks = []
    for zone in list(_active_jobs.keys()):
        tasks.append(_turn_zone_off(zone))
    if tasks:
        await asyncio.gather(*tasks, return_exceptions=True)
    _active_jobs.clear()
    return JSONResponse({"rain_lock_expires_at": _rain_lock_until.isoformat() + "Z"})

@app.delete("/rain-lock", dependencies=[Depends(require_token)])
async def clear_rain_lock() -> JSONResponse:
    global _rain_lock_until
    _rain_lock_until = None
    return JSONResponse({"rain_lock_expires_at": None})

# -- helpers --
def _zone_for_pin(pin: int) -> int:
    try:
        return GPIO_PINS.index(pin) + 1
    except ValueError:
        raise HTTPException(status_code=404, detail=f"Pin {pin} not managed")


def _pin_snapshot() -> list[dict]:
    return [
        {"pin": gpio, "on": (pi.read(gpio) == 0), "active_high": False}
        for gpio in GPIO_PINS
    ]


# -- compat routes mirroring older docs/clients --
@app.get("/api/status", dependencies=[Depends(require_token)])
async def api_status_compat():
    return await get_status()  # type: ignore


@app.get("/api/pins", dependencies=[Depends(require_token)])
async def api_pins_compat():
    return _pin_snapshot()


@app.post("/api/pin/{pin}/on", dependencies=[Depends(require_token)])
async def api_pin_on_compat(pin: int):
    zone = _zone_for_pin(pin)
    return await start_zone(  # type: ignore
        zone, StartZoneRequest(minutes=DEFAULT_RUNTIME_MINUTES)
    )


@app.post("/api/pin/{pin}/off", dependencies=[Depends(require_token)])
async def api_pin_off_compat(pin: int):
    zone = _zone_for_pin(pin)
    return await stop_zone(zone)  # type: ignore


@app.exception_handler(Exception)
async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"error": "unexpected_error", "details": str(exc)},
    )
