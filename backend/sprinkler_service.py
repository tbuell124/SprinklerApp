# FILE: sprinkler_service.py
"""Authenticated FastAPI sprinkler service with GPIO + schedule automation."""

from __future__ import annotations

import asyncio
import json
import logging
import os
from collections import OrderedDict
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional

import pigpio
from fastapi import Body, Depends, FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator

# ---------------------------------------------------------------------------
# Logging configuration
# ---------------------------------------------------------------------------

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("sprinkler")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

APP_VERSION = "1.2.0"
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
STATE_ROOT = Path(os.getenv("SPRINKLER_STATE_DIR", "/srv/sprinkler-controller/state"))
STATE_ROOT.mkdir(parents=True, exist_ok=True)
SCHEDULES_FILE = STATE_ROOT / "schedules.json"

if API_TOKEN is None:
    raise RuntimeError("SPRINKLER_API_TOKEN is required in the environment")

# ---------------------------------------------------------------------------
# GPIO setup (active-low: write 1=OFF, 0=ON)
# ---------------------------------------------------------------------------

pi = pigpio.pi()
if not pi.connected:
    raise RuntimeError(
        "Failed to connect to pigpiod. Start it with: sudo systemctl enable --now pigpiod"
    )

GPIO_PINS: List[int] = []

ALLOW_ENV = os.getenv("SPRINKLER_GPIO_ALLOW", "")
DENY_ENV = os.getenv("SPRINKLER_GPIO_DENY", "")


def _parse_int_csv(value: str) -> List[int]:
    entries: List[int] = []
    if not value:
        return entries
    for token in value.split(","):
        token = token.strip()
        if not token:
            continue
        try:
            entries.append(int(token))
        except ValueError:
            continue
    return entries


_allow_list = _parse_int_csv(ALLOW_ENV) or DEFAULT_GPIO_PINS
_deny_list = set(_parse_int_csv(DENY_ENV))

for candidate in _allow_list:
    if candidate in _deny_list:
        continue
    if candidate not in GPIO_PINS:
        GPIO_PINS.append(candidate)

if not GPIO_PINS:
    GPIO_PINS = DEFAULT_GPIO_PINS.copy()

for gpio in GPIO_PINS:
    pi.set_mode(gpio, pigpio.OUTPUT)
    pi.write(gpio, 1)  # default OFF

ALLOWED_PIN_SET = set(GPIO_PINS)

# ---------------------------------------------------------------------------
# Day helpers
# ---------------------------------------------------------------------------

DAY_NAME_MAP = OrderedDict(
    (
        ("mon", "Mon"),
        ("tue", "Tue"),
        ("wed", "Wed"),
        ("thu", "Thu"),
        ("fri", "Fri"),
        ("sat", "Sat"),
        ("sun", "Sun"),
    )
)


# ---------------------------------------------------------------------------
# Schedules
# ---------------------------------------------------------------------------


class ScheduleStep(BaseModel):
    """Single step in a watering sequence (pin + minutes)."""

    model_config = ConfigDict(populate_by_name=True, extra="forbid")

    pin: int
    duration: int = Field(alias="duration", ge=1, le=12 * 60)

    @field_validator("pin")
    @classmethod
    def validate_pin(cls, value: int) -> int:
        if value not in ALLOWED_PIN_SET:
            raise ValueError(f"Pin {value} is not in the allowed GPIO list")
        return value


class ScheduleModel(BaseModel):
    """Schedule persisted to disk and exposed over the REST API."""

    model_config = ConfigDict(populate_by_name=True, extra="forbid")

    id: str
    name: Optional[str] = None
    duration: Optional[int] = Field(default=None, alias="duration", ge=1, le=12 * 60)
    start_time: str = Field(alias="start_time")
    days: List[str] = Field(default_factory=list)
    is_enabled: bool = Field(default=True, alias="is_enabled")
    sequence: List[ScheduleStep] = Field(default_factory=list)

    @field_validator("start_time")
    @classmethod
    def validate_start_time(cls, value: str) -> str:
        try:
            hour_str, minute_str = value.split(":", maxsplit=1)
            hour = int(hour_str)
            minute = int(minute_str)
        except Exception as exc:  # noqa: BLE001
            raise ValueError("start_time must be HH:MM") from exc
        if not (0 <= hour < 24 and 0 <= minute < 60):
            raise ValueError("start_time must be between 00:00 and 23:59")
        return f"{hour:02d}:{minute:02d}"

    @field_validator("days", mode="before")
    @classmethod
    def normalize_days(cls, value: Any) -> List[str]:
        if value is None:
            return []
        result: List[str] = []
        for item in value:
            token = str(item).strip().lower()
            if not token:
                continue
            canonical = DAY_NAME_MAP.get(token)
            if canonical is None:
                raise ValueError(f"Unsupported day value: {item}")
            if canonical not in result:
                result.append(canonical)
        return result

    @model_validator(mode="after")
    def ensure_duration_present(self) -> "ScheduleModel":
        if not self.sequence and self.duration is None:
            raise ValueError("Schedule requires a duration or a sequence")
        return self

    @property
    def resolved_duration(self) -> int:
        if self.sequence:
            return sum(step.duration for step in self.sequence)
        return int(self.duration or 0)

    def to_public_dict(self) -> Dict[str, Any]:
        payload = self.model_dump(by_alias=True, exclude_none=True)
        payload["duration"] = self.resolved_duration
        return payload

    def start_datetime_on(self, target_date: datetime) -> datetime:
        hour_str, minute_str = self.start_time.split(":", maxsplit=1)
        hour = int(hour_str)
        minute = int(minute_str)
        return target_date.replace(hour=hour, minute=minute, second=0, microsecond=0)

    def should_run(self, now: datetime, last_run: Optional[datetime]) -> bool:
        if not self.is_enabled:
            return False
        if not self.days:
            return False
        weekday_key = list(DAY_NAME_MAP.keys())[now.weekday()]
        if DAY_NAME_MAP[weekday_key] not in self.days:
            return False
        run_at = self.start_datetime_on(now)
        window_start = run_at
        window_end = run_at + timedelta(minutes=1)
        if not (window_start <= now < window_end):
            return False
        if last_run and last_run.date() == now.date():
            return False
        return True


@dataclass
class StoredScheduleState:
    schedules: Dict[str, ScheduleModel]
    order: List[str]


class ScheduleStore:
    """In-memory + JSON persisted schedule storage."""

    def __init__(self, file_path: Path):
        self._file_path = file_path
        self._lock = asyncio.Lock()
        self._state = StoredScheduleState(schedules={}, order=[])
        self._last_run: Dict[str, datetime] = {}
        self._active_tasks: Dict[str, asyncio.Task[Any]] = {}
        self._load_from_disk()

    def _load_from_disk(self) -> None:
        if not self._file_path.exists():
            return
        try:
            with self._file_path.open("r", encoding="utf-8") as handle:
                raw = json.load(handle)
        except json.JSONDecodeError as exc:  # noqa: PERF203
            logger.warning("Failed to parse schedules.json: %s", exc)
            return
        schedules: Dict[str, ScheduleModel] = {}
        order: List[str] = []
        for payload in raw.get("schedules", []):
            try:
                schedule = ScheduleModel.model_validate(payload)
            except ValidationError as exc:
                logger.warning("Skipping invalid schedule payload: %s", exc)
                continue
            schedules[schedule.id] = schedule
        persisted_order = raw.get("order")
        if isinstance(persisted_order, list):
            for identifier in persisted_order:
                if identifier in schedules:
                    order.append(identifier)
        for identifier in schedules.keys():
            if identifier not in order:
                order.append(identifier)
        self._state = StoredScheduleState(schedules=schedules, order=order)

    async def _persist(self) -> None:
        data = {
            "schedules": [self._state.schedules[sid].model_dump(by_alias=True) for sid in self._state.order if sid in self._state.schedules],
            "order": [sid for sid in self._state.order if sid in self._state.schedules],
        }
        tmp_path = self._file_path.with_suffix(".tmp")
        tmp_path.parent.mkdir(parents=True, exist_ok=True)
        with tmp_path.open("w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
        tmp_path.replace(self._file_path)

    async def list(self) -> List[ScheduleModel]:
        async with self._lock:
            return [self._state.schedules[sid] for sid in self._state.order if sid in self._state.schedules]

    async def get(self, schedule_id: str) -> Optional[ScheduleModel]:
        async with self._lock:
            return self._state.schedules.get(schedule_id)

    async def upsert(self, schedule: ScheduleModel) -> None:
        async with self._lock:
            is_new = schedule.id not in self._state.schedules
            self._state.schedules[schedule.id] = schedule
            if is_new:
                self._state.order.append(schedule.id)
        await self._persist()

    async def delete(self, schedule_id: str) -> bool:
        async with self._lock:
            removed = self._state.schedules.pop(schedule_id, None) is not None
            if schedule_id in self._state.order:
                self._state.order.remove(schedule_id)
            self._last_run.pop(schedule_id, None)
            task = self._active_tasks.pop(schedule_id, None)
            if task and not task.done():
                task.cancel()
        if removed:
            await self._persist()
        return removed

    async def reorder(self, identifiers: List[str]) -> None:
        async with self._lock:
            new_order: List[str] = []
            seen: set[str] = set()
            for identifier in identifiers:
                if identifier in self._state.schedules and identifier not in seen:
                    seen.add(identifier)
                    new_order.append(identifier)
            for identifier in self._state.order:
                if identifier not in seen and identifier in self._state.schedules:
                    new_order.append(identifier)
            self._state.order = new_order
        await self._persist()

    async def mark_run(self, schedule_id: str, run_time: datetime) -> None:
        async with self._lock:
            self._last_run[schedule_id] = run_time

    async def last_run(self, schedule_id: str) -> Optional[datetime]:
        async with self._lock:
            return self._last_run.get(schedule_id)

    async def set_active_task(self, schedule_id: str, task: asyncio.Task[Any]) -> None:
        async with self._lock:
            self._active_tasks[schedule_id] = task

    async def clear_active_task(self, schedule_id: str) -> None:
        async with self._lock:
            existing = self._active_tasks.get(schedule_id)
            if existing and not existing.done():
                existing.cancel()
            self._active_tasks.pop(schedule_id, None)

    async def active_task(self, schedule_id: str) -> Optional[asyncio.Task[Any]]:
        async with self._lock:
            return self._active_tasks.get(schedule_id)


schedule_store = ScheduleStore(SCHEDULES_FILE)

# ---------------------------------------------------------------------------
# Authentication dependency
# ---------------------------------------------------------------------------


def require_token(request: Request) -> None:
    header = request.headers.get("authorization")
    if not header or header.strip() != f"Bearer {API_TOKEN}":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing or invalid token")


# ---------------------------------------------------------------------------
# State & helpers
# ---------------------------------------------------------------------------

_active_jobs: Dict[int, Dict[str, Any]] = {}
_rain_lock_until: Optional[datetime] = None
_schedule_loop: Optional[asyncio.Task[Any]] = None


class ZoneBusyError(Exception):
    """Raised when attempting to start a zone that is already running."""


class RainLockActiveError(Exception):
    """Raised when a manual rain delay prevents watering."""


def _gpio_for_zone(zone: int) -> int:
    try:
        return GPIO_PINS[zone - 1]
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"Zone {zone} is out of range 1..{len(GPIO_PINS)}") from exc


def _zone_for_pin(pin: int) -> int:
    try:
        return GPIO_PINS.index(pin) + 1
    except ValueError as exc:  # noqa: BLE001
        raise HTTPException(status_code=404, detail=f"Pin {pin} not managed") from exc


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


async def _zone_timer(zone: int, duration_minutes: int, source: str) -> None:
    gpio = _gpio_for_zone(zone)
    logger.info("Starting zone %s via %s for %s minutes", zone, source, duration_minutes)
    pi.write(gpio, 0)
    try:
        await asyncio.sleep(duration_minutes * 60)
    finally:
        pi.write(gpio, 1)
        _active_jobs.pop(zone, None)
        logger.info("Zone %s completed for %s", zone, source)


async def _start_zone_internal(
    zone: int,
    duration_minutes: int,
    source: str,
    *,
    cancel_existing: bool,
    wait: bool = False,
) -> datetime:
    if duration_minutes <= 0:
        raise ValueError("Duration must be positive")
    if _rain_lock_until and datetime.utcnow() < _rain_lock_until:
        raise RainLockActiveError("Rain delay active")
    existing = _active_jobs.get(zone)
    if existing:
        if not cancel_existing:
            raise ZoneBusyError(f"Zone {zone} is currently running")
        task = existing.get("task")
        if isinstance(task, asyncio.Task) and not task.done():
            task.cancel()
            try:
                await task
            except Exception:  # noqa: BLE001
                pass
        _active_jobs.pop(zone, None)
    until = datetime.utcnow() + timedelta(minutes=duration_minutes)
    task = asyncio.create_task(_zone_timer(zone, duration_minutes, source))
    _active_jobs[zone] = {"task": task, "until": until, "source": source}
    if wait:
        try:
            await task
        finally:
            return until
    return until


async def _turn_zone_off(zone: int) -> None:
    gpio = _gpio_for_zone(zone)
    pi.write(gpio, 1)
    _active_jobs.pop(zone, None)


def _pin_snapshot() -> List[Dict[str, Any]]:
    snapshot: List[Dict[str, Any]] = []
    for gpio in GPIO_PINS:
        snapshot.append({"pin": gpio, "name": None, "is_active": pi.read(gpio) == 0, "is_enabled": True})
    return snapshot


# ---------------------------------------------------------------------------
# FastAPI app setup
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
# Startup/shutdown hooks
# ---------------------------------------------------------------------------


async def _schedule_loop_runner() -> None:
    logger.info("Schedule loop started")
    try:
        while True:
            await _evaluate_schedules()
            await asyncio.sleep(30)
    except asyncio.CancelledError:
        logger.info("Schedule loop cancelled")
        raise
    except Exception as exc:  # noqa: BLE001
        logger.exception("Schedule loop crashed: %s", exc)
        raise


async def _evaluate_schedules() -> None:
    now = datetime.utcnow()
    if _rain_lock_until and now < _rain_lock_until:
        return
    schedules = await schedule_store.list()
    for schedule in schedules:
        last_run = await schedule_store.last_run(schedule.id)
        if await schedule_store.active_task(schedule.id):
            continue
        if schedule.should_run(now, last_run):
            schedule_id = schedule.id
            logger.info("Dispatching schedule %s", schedule_id)
            await schedule_store.mark_run(schedule_id, now)
            task = asyncio.create_task(_execute_schedule(schedule))
            await schedule_store.set_active_task(schedule_id, task)
            task.add_done_callback(
                lambda _task, identifier=schedule_id: asyncio.create_task(
                    schedule_store.clear_active_task(identifier)
                )
            )


async def _execute_schedule(schedule: ScheduleModel) -> None:
    logger.info("Running schedule %s", schedule.id)
    steps: List[ScheduleStep]
    if schedule.sequence:
        steps = schedule.sequence
    elif schedule.duration:
        default_pin = GPIO_PINS[0]
        steps = [ScheduleStep(pin=default_pin, duration=schedule.duration)]
    else:
        logger.warning("Schedule %s has no actionable duration", schedule.id)
        return

    for step in steps:
        try:
            zone = _zone_for_pin(step.pin)
        except HTTPException as exc:
            logger.warning("Skipping invalid pin %s for schedule %s: %s", step.pin, schedule.id, exc.detail)
            return
        try:
            await _start_zone_internal(zone, step.duration, f"schedule:{schedule.id}", cancel_existing=False, wait=True)
        except ZoneBusyError:
            logger.warning("Zone %s busy, aborting schedule %s", zone, schedule.id)
            return
        except RainLockActiveError:
            logger.info("Rain delay activated during schedule %s", schedule.id)
            return
        except Exception as exc:  # noqa: BLE001
            logger.exception("Failed to run zone %s for schedule %s: %s", zone, schedule.id, exc)
            return
    logger.info("Schedule %s completed", schedule.id)


@app.on_event("startup")
async def on_startup() -> None:  # pragma: no cover - exercised on device
    global _schedule_loop
    if _schedule_loop is None:
        _schedule_loop = asyncio.create_task(_schedule_loop_runner())


@app.on_event("shutdown")
async def on_shutdown() -> None:  # pragma: no cover - exercised on device
    global _schedule_loop
    if _schedule_loop:
        _schedule_loop.cancel()
        try:
            await _schedule_loop
        except Exception:  # noqa: BLE001
            pass
        _schedule_loop = None


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------


class StartZoneRequest(BaseModel):
    minutes: int = Field(default=DEFAULT_RUNTIME_MINUTES, ge=1, le=12 * 60)


class RainLockRequest(BaseModel):
    hours: int = Field(default=RAIN_LOCK_DEFAULT_HOURS, ge=1, le=14 * 24)


class RainDelayPayload(BaseModel):
    active: bool = True
    hours: Optional[int] = Field(default=None, ge=1, le=14 * 24)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.get("/status", dependencies=[Depends(require_token)])
async def get_status() -> JSONResponse:
    schedules = await schedule_store.list()
    rain_active = bool(_rain_lock_until and datetime.utcnow() < _rain_lock_until)
    rain_payload: Dict[str, Any] = {
        "is_active": rain_active,
        "ends_at": _rain_lock_until.isoformat() + "Z" if _rain_lock_until else None,
        "duration_hours": int(
            round(((_rain_lock_until - datetime.utcnow()).total_seconds() / 3600))
        )
        if rain_active and _rain_lock_until
        else None,
        "chance_percent": None,
        "threshold_percent": None,
        "zip_code": None,
        "automation_enabled": None,
    }
    payload = {
        "version": APP_VERSION,
        "last_updated": datetime.utcnow().isoformat() + "Z",
        "pins": _pin_snapshot(),
        "schedules": [schedule.to_public_dict() for schedule in schedules],
        "rain": rain_payload,
    }
    return JSONResponse(payload)


@app.post("/zone/on/{zone}", dependencies=[Depends(require_token)])
async def start_zone(zone: int, payload: StartZoneRequest) -> JSONResponse:
    try:
        await _start_zone_internal(zone, payload.minutes, "manual", cancel_existing=True, wait=False)
    except RainLockActiveError as exc:
        raise HTTPException(status_code=423, detail=str(exc)) from exc
    except ZoneBusyError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return JSONResponse({"zone": zone, "gpio": _gpio_for_zone(zone), "on": True, "minutes_left": payload.minutes})


@app.post("/zone/off/{zone}", dependencies=[Depends(require_token)])
async def stop_zone(zone: int) -> JSONResponse:
    existing = _active_jobs.get(zone)
    if existing:
        task = existing.get("task")
        if isinstance(task, asyncio.Task) and not task.done():
            task.cancel()
            try:
                await task
            except Exception:  # noqa: BLE001
                pass
    await _turn_zone_off(zone)
    return JSONResponse({"zone": zone, "gpio": _gpio_for_zone(zone), "on": False, "minutes_left": 0})


@app.post("/rain-lock", dependencies=[Depends(require_token)])
async def set_rain_lock(body: RainLockRequest) -> JSONResponse:
    global _rain_lock_until
    _rain_lock_until = datetime.utcnow() + timedelta(hours=body.hours)
    await _shutdown_all_zones()
    return JSONResponse({"rain_lock_expires_at": _rain_lock_until.isoformat() + "Z"})


@app.delete("/rain-lock", dependencies=[Depends(require_token)])
async def clear_rain_lock() -> JSONResponse:
    global _rain_lock_until
    _rain_lock_until = None
    return JSONResponse({"rain_lock_expires_at": None})


async def _shutdown_all_zones() -> None:
    tasks = []
    for zone in list(_active_jobs.keys()):
        tasks.append(_turn_zone_off(zone))
    if tasks:
        await asyncio.gather(*tasks, return_exceptions=True)
    _active_jobs.clear()


# -- Schedule endpoints -----------------------------------------------------


@app.get("/api/schedules", dependencies=[Depends(require_token)])
async def list_schedules() -> JSONResponse:
    schedules = await schedule_store.list()
    return JSONResponse([schedule.to_public_dict() for schedule in schedules])


@app.post("/api/schedules", dependencies=[Depends(require_token)])
async def create_schedule(payload: ScheduleModel) -> JSONResponse:
    existing = await schedule_store.get(payload.id)
    if existing:
        raise HTTPException(status_code=409, detail="Schedule with that identifier already exists")
    await schedule_store.upsert(payload)
    return JSONResponse(payload.to_public_dict(), status_code=status.HTTP_201_CREATED)


@app.put("/api/schedules/{schedule_id}", dependencies=[Depends(require_token)])
async def update_schedule(schedule_id: str, payload: ScheduleModel) -> JSONResponse:
    if payload.id != schedule_id:
        raise HTTPException(status_code=400, detail="Schedule identifier mismatch")
    await schedule_store.upsert(payload)
    return JSONResponse(payload.to_public_dict())


@app.delete("/api/schedules/{schedule_id}", dependencies=[Depends(require_token)])
async def delete_schedule(schedule_id: str) -> JSONResponse:
    removed = await schedule_store.delete(schedule_id)
    if not removed:
        raise HTTPException(status_code=404, detail="Schedule not found")
    return JSONResponse({"status": "deleted"})


@app.post("/api/schedules/reorder", dependencies=[Depends(require_token)])
async def reorder_schedules(order: List[str]) -> JSONResponse:
    await schedule_store.reorder(order)
    return JSONResponse({"status": "ok"})


# -- Rain delay -------------------------------------------------------------


@app.post("/api/rain-delay", dependencies=[Depends(require_token)])
async def trigger_rain_delay(payload: RainDelayPayload) -> JSONResponse:
    global _rain_lock_until
    if payload.active:
        hours = payload.hours or RAIN_LOCK_DEFAULT_HOURS
        _rain_lock_until = datetime.utcnow() + timedelta(hours=hours)
        await _shutdown_all_zones()
    else:
        _rain_lock_until = None
    return JSONResponse({"rain_delay_expires_at": _rain_lock_until.isoformat() + "Z" if _rain_lock_until else None})


# -- Compat routes mirroring older docs/clients -----------------------------


@app.get("/api/status", dependencies=[Depends(require_token)])
async def api_status_compat():
    return await get_status()  # type: ignore[return-value]


@app.get("/api/pins", dependencies=[Depends(require_token)])
async def api_pins_compat():
    return _pin_snapshot()


@app.post("/api/pin/{pin}/on", dependencies=[Depends(require_token)])
async def api_pin_on_compat(
    pin: int,
    payload: StartZoneRequest = Body(default=StartZoneRequest()),
):
    zone = _zone_for_pin(pin)
    return await start_zone(zone, payload)  # type: ignore[arg-type]


@app.post("/api/pin/{pin}/off", dependencies=[Depends(require_token)])
async def api_pin_off_compat(pin: int):
    zone = _zone_for_pin(pin)
    return await stop_zone(zone)  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------


@app.exception_handler(Exception)
async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:  # noqa: ARG001
    logger.exception("Unhandled error: %s", exc)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"error": "unexpected_error", "details": str(exc)},
    )
