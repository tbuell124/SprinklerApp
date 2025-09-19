# sprinkler/app.py
# Sprinkler Controller API (Tune for Ty's 16 wired GPIOs)
# - pigpio first (via pigpiod), fallback to RPi.GPIO
# - Controls only the 16 wired pins by default (override via .env)
# - Minimal state persisted to /srv/sprinkler-controller/state

import os
import json
import time
from pathlib import Path
from typing import Dict, List, Optional, Any, Set

from fastapi import FastAPI, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# -------------------------
# GPIO backends
# -------------------------
USE_PIGPIO = False
PI = None
pigpio = None
GPIO = None

try:
    import pigpio  # type: ignore
    PI = pigpio.pi()  # connects to local pigpiod
    if PI is not None and PI.connected:
        USE_PIGPIO = True
    else:
        PI = None
except Exception:
    pigpio = None
    PI = None
    USE_PIGPIO = False

if not USE_PIGPIO:
    try:
        import RPi.GPIO as GPIO  # type: ignore
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
    except Exception:
        GPIO = None  # no GPIO available (e.g., dev machine)

def effective_backend() -> str:
    return "pigpio" if USE_PIGPIO else ("RPi.GPIO" if GPIO else "none")

# -------------------------
# App + CORS
# -------------------------
app = FastAPI(title="Sprinkler Controller API", version="1.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # LAN app; safe at home. Lock down if exposing externally.
    allow_methods=["*"],
    allow_headers=["*"],
)

# -------------------------
# Pin policy (defaults to YOUR 16 pins)
# You can still override in .env:
#   SPRINKLER_GPIO_ALLOW=12,16,20,21,26,19,13,6,5,11,9,10,22,27,17,4
#   SPRINKLER_GPIO_DENY=2,3,14,15
# -------------------------
DEFAULT_ALLOW = "12,16,20,21,26,19,13,6,5,11,9,10,22,27,17,4"
ALLOW_ENV = os.getenv("SPRINKLER_GPIO_ALLOW", DEFAULT_ALLOW).strip()
DENY_ENV  = os.getenv("SPRINKLER_GPIO_DENY", "2,3,14,15").strip()  # avoid I2C/UART by default

def _parse_int_csv(s: str) -> Set[int]:
    out: Set[int] = set()
    if not s:
        return out
    for tok in s.split(","):
        tok = tok.strip()
        if not tok:
            continue
        try:
            out.add(int(tok))
        except ValueError:
            pass
    return out

ALLOW_SET: Set[int] = _parse_int_csv(ALLOW_ENV)
DENY_SET: Set[int]  = _parse_int_csv(DENY_ENV)

def is_allowed(pin: int) -> bool:
    return (pin in ALLOW_SET) and (pin not in DENY_SET)

