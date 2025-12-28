from __future__ import annotations
from typing import List, Optional
from pydantic import BaseModel, Field


class ActionPacket(BaseModel):
    packet_version: str = "v1"
    id: str
    created_at: float
    expires_at: float
    nonce: str
    sequence: int
    device_id: str
    policy_hash: str
    intents: List[dict] = Field(default_factory=list)
    hash: Optional[str] = None
    signature: Optional[str] = None
    public_key: Optional[str] = None


class NewsBrief(BaseModel):
    ticker: str
    sentiment: str
    summary: str


class SignalItem(BaseModel):
    ticker: str
    action: str
    confidence: float


class Signals(BaseModel):
    signals: List[SignalItem] = Field(default_factory=list)


class StrategyEntry(BaseModel):
    ticker: str
    direction: str
    size: float


class Strategy(BaseModel):
    entries: List[StrategyEntry] = Field(default_factory=list)
    rationale: str
    horizon_minutes: int


class WatchdogDecision(BaseModel):
    block: bool
    reasons: List[str] = Field(default_factory=list)
    risk: str


class ExecutionReport(BaseModel):
    report_version: str = "v1"
    packet_id: str
    executed_at: float
    status: str
    details: dict
