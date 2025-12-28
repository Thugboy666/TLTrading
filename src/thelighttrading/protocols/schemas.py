from __future__ import annotations
from typing import List, Optional
from pydantic import BaseModel, Field, field_validator


class IntentItem(BaseModel):
    ticker: str
    direction: str
    size: float


class ActionPacket(BaseModel):
    packet_version: str = "v1"
    id: str
    created_at: float
    expires_at: float
    nonce: str
    sequence: int
    device_id: str
    policy_hash: str
    intents: List[IntentItem] = Field(default_factory=list)
    hash: Optional[str] = None
    signature: Optional[str] = None
    public_key: Optional[str] = None

    @field_validator("intents", mode="before")
    @classmethod
    def _coerce_intents(cls, value):
        if value is None:
            return []
        return value


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
    run_id: str
    packet_id: str
    created_at: float
    status: str
    node_statuses: List[dict] = Field(default_factory=list)
    packet_hash: Optional[str] = None
    report_hash: Optional[str] = None
    signature: Optional[str] = None
    public_key: Optional[str] = None
