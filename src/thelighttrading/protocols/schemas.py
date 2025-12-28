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


class ExecutionReport(BaseModel):
    report_version: str = "v1"
    packet_id: str
    executed_at: float
    status: str
    details: dict
