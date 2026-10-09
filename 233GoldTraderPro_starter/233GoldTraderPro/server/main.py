"""Development-only API skeleton. Does not connect to MT5 or place trades."""
from datetime import datetime, timezone
from enum import Enum
from typing import Literal
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="233 Gold Trader Pro API", version="0.1-demo")

class Broker(str, Enum):
    deriv = "Deriv"
    exness = "Exness"

class DemoSettings(BaseModel):
    broker: Broker = Broker.deriv
    symbol: str = "XAUUSD"
    lot_size: float = Field(default=0.01, gt=0, le=0.1)
    daily_loss_limit_usd: float = Field(default=2.0, gt=0, le=50)
    max_open_trades: int = Field(default=1, ge=1, le=5)
    mode: Literal["DEMO"] = "DEMO"

settings = DemoSettings()
state = {"connected": False, "running": False, "status": "NOT_CONNECTED", "updated_at": None}

@app.get("/health")
def health():
    return {"ok": True, "service": "233 Gold Trader Pro", "mode": "DEMO_ONLY", "time": datetime.now(timezone.utc).isoformat()}

@app.get("/v1/status")
def get_status():
    return {**state, "settings": settings.model_dump(), "notice": "Prototype only; MT5 bridge is not implemented."}

@app.get("/v1/settings")
def get_settings():
    return settings

@app.put("/v1/settings")
def update_settings(new_settings: DemoSettings):
    global settings
    if new_settings.symbol.upper() not in {"XAUUSD", "XAUUSD.M", "XAUUSDM", "GOLD"}:
        raise HTTPException(status_code=400, detail="Prototype is restricted to Gold symbol aliases.")
    settings = new_settings
    return {"saved": True, "settings": settings, "note": "Local prototype state only; no EA receives these settings yet."}

@app.post("/v1/start-demo")
def start_demo():
    raise HTTPException(status_code=501, detail="Trading start is disabled until authentication, MT5 bridge, demo-account verification, and server-side risk checks are implemented.")

@app.post("/v1/emergency-stop")
def emergency_stop():
    # No live trading process is connected in this prototype.
    state.update({"running": False, "status": "STOPPED_NO_BRIDGE", "updated_at": datetime.now(timezone.utc).isoformat()})
    return {"stopped": True, "note": "Prototype state only. No MT5 terminal is connected."}
