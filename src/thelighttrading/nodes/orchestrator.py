import importlib
import json
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List

from .graph import GraphSpec, NodeSpec, default_graph_spec
from .registry import NodeRegistry
from ..config.settings import get_settings
from ..inputs.news_ingest import read_headlines_from_file
from ..observability.metrics import metrics
from ..policy import evaluate_strategy, PolicyDecision
from ..protocols.reporting import build_execution_report, persist_report
from ..protocols.schemas import Strategy


class Orchestrator:
    def __init__(self, graph_spec: GraphSpec | None = None):
        self.graph_spec = graph_spec or default_graph_spec()
        self.nodes = self._initialize_nodes(self.graph_spec.nodes)

    def _initialize_nodes(self, nodes: Dict[str, NodeSpec]):
        instances = {}
        for node_id, spec in nodes.items():
            node_cls = None
            if spec.node_type:
                node_cls = NodeRegistry.get(spec.node_type)
            if not node_cls and spec.class_path:
                module_path, class_name = spec.class_path.rsplit(".", 1)
                module = importlib.import_module(module_path)
                node_cls = getattr(module, class_name)
            if not node_cls:
                raise ValueError(f"Node {node_id} not found in registry or class path")
            instance = node_cls()
            if hasattr(instance, "profile") and spec.profile:
                instance.profile = spec.profile
            instances[node_id] = instance
        return instances

    def _topological_order(self) -> List[str]:
        edges = list(self.graph_spec.edges)
        incoming = {node_id: 0 for node_id in self.graph_spec.nodes}
        adjacency: Dict[str, List[str]] = {node_id: [] for node_id in self.graph_spec.nodes}
        for src, dst in edges:
            adjacency[src].append(dst)
            incoming[dst] += 1

        queue = [nid for nid, deg in incoming.items() if deg == 0]
        order: List[str] = []
        while queue:
            current = queue.pop(0)
            order.append(current)
            for neighbor in adjacency[current]:
                incoming[neighbor] -= 1
                if incoming[neighbor] == 0:
                    queue.append(neighbor)
        return order

    def _resolve_headlines(self, headlines: str | list[str] | None, headlines_path: str | None = None) -> list[str]:
        if headlines_path:
            inputs_dir = Path(get_settings().data_dir) / "inputs"
            requested = (inputs_dir / headlines_path).resolve()
            if inputs_dir.resolve() not in requested.parents and requested != inputs_dir.resolve():
                raise ValueError("invalid_headlines_path")
            if inputs_dir.resolve() != requested.parent and inputs_dir.resolve() != requested:
                raise ValueError("invalid_headlines_path")
            return read_headlines_from_file(requested)

        if isinstance(headlines, list):
            return [str(h).strip() for h in headlines if str(h).strip()][:50]
        if isinstance(headlines, str) and headlines:
            return [headlines]

        inputs_dir = Path(get_settings().data_dir) / "inputs"
        default_path = inputs_dir / "headlines.txt"
        return read_headlines_from_file(default_path)

    def _build_messages(self, node_id: str, outputs: Dict[str, dict], headlines: list[str] | None):
        if node_id == "news":
            content = "\n".join(headlines or []) or "Mock headlines"
            return [{"role": "user", "content": content}]
        if node_id == "parser":
            return [
                {"role": "system", "content": "Parse summary"},
                {"role": "user", "content": json.dumps(outputs.get("news", {}))},
            ]
        if node_id == "brain":
            return [
                {"role": "system", "content": "Strategize"},
                {"role": "user", "content": json.dumps(outputs.get("parser", {}))},
            ]
        if node_id == "watchdog":
            return [
                {"role": "system", "content": "Risk check"},
                {"role": "user", "content": json.dumps(outputs.get("brain", {}))},
            ]
        return []

    def _policy_record(self, error: bool, policy_decision: PolicyDecision | None) -> dict:
        ts = time.time()
        status = "ok" if not error and policy_decision else "skipped"
        decision_payload = policy_decision.__dict__ if policy_decision else {"allow": False, "reasons": ["not_evaluated"]}
        return {
            "id": "policy",
            "name": "PolicyEngine",
            "status": status,
            "ts_start": ts,
            "ts_end": ts,
            "output": decision_payload,
        }

    def _new_run_id(self) -> str:
        ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        short_uuid = uuid.uuid4().hex[:8]
        return f"run_{ts}_{short_uuid}"

    def run_pipeline(self, headlines: str | list[str] | None = None, headlines_path: str | None = None) -> dict:
        run_id = self._new_run_id()
        created_at = time.time()
        outputs: Dict[str, dict] = {}
        run_nodes: List[dict] = []
        status_summary = "ok"
        policy_decision: PolicyDecision | None = None
        metrics.runs_total += 1

        resolved_headlines = self._resolve_headlines(headlines, headlines_path)

        order = self._topological_order()
        stop_due_to_error = False

        for node_id in order:
            spec = self.graph_spec.nodes[node_id]
            if not spec.enabled:
                ts = time.time()
                run_nodes.append(
                    {
                        "id": node_id,
                        "name": getattr(self.nodes[node_id], "name", node_id),
                        "status": "skipped",
                        "ts_start": ts,
                        "ts_end": ts,
                        "output": {},
                    }
                )
                outputs[node_id] = {}
                if node_id == "brain":
                    run_nodes.append(self._policy_record(True, None))
                continue

            if stop_due_to_error:
                ts = time.time()
                run_nodes.append(
                    {
                        "id": node_id,
                        "name": getattr(self.nodes[node_id], "name", node_id),
                        "status": "skipped",
                        "ts_start": ts,
                        "ts_end": ts,
                        "output": {},
                    }
                )
                outputs[node_id] = {}
                if node_id == "brain":
                    run_nodes.append(self._policy_record(True, None))
                continue

            try:
                if node_id == "packet":
                    brain_entries = outputs.get("brain", {}).get("entries", [])
                    watchdog_output = outputs.get("watchdog", {})
                    packet_result = self.nodes[node_id].run(watchdog_output, brain_entries, policy_decision or PolicyDecision(False, ["no_policy"]))
                    outputs[node_id] = packet_result.output
                    run_nodes.append(
                        {
                            "id": node_id,
                            "name": self.nodes[node_id].name,
                            "status": "ok",
                            "ts_start": packet_result.ts_start,
                            "ts_end": packet_result.ts_end,
                            "output": packet_result.output,
                        }
                    )
                else:
                    messages = self._build_messages(node_id, outputs, resolved_headlines)
                    result = self.nodes[node_id].run(messages)
                    metrics.llm_calls_total += 1
                    outputs[node_id] = result.output
                    run_nodes.append(
                        {
                            "id": node_id,
                            "name": self.nodes[node_id].name,
                            "status": "ok",
                            "ts_start": result.ts_start,
                            "ts_end": result.ts_end,
                            "output": result.output,
                        }
                    )

                    if node_id == "brain":
                        policy_ts_start = time.time()
                        try:
                            strategy = Strategy.model_validate(result.output)
                            policy_decision = evaluate_strategy(strategy)
                            policy_status = "ok"
                        except Exception as exc:  # noqa: BLE001
                            policy_decision = PolicyDecision(False, [f"error:{exc}"])
                            policy_status = "error"
                            status_summary = "error"
                        policy_ts_end = time.time()
                        run_nodes.append(
                            {
                                "id": "policy",
                                "name": "PolicyEngine",
                                "status": policy_status,
                                "ts_start": policy_ts_start,
                                "ts_end": policy_ts_end,
                                "output": policy_decision.__dict__,
                            }
                        )
                if node_id == "watchdog" and outputs.get("watchdog", {}).get("block"):
                    status_summary = status_summary or "ok"
            except Exception as exc:  # noqa: BLE001
                ts = time.time()
                status_summary = "error"
                stop_due_to_error = True
                outputs[node_id] = {}
                run_nodes.append(
                    {
                        "id": node_id,
                        "name": getattr(self.nodes[node_id], "name", node_id),
                        "status": "error",
                        "ts_start": ts,
                        "ts_end": time.time(),
                        "output": {},
                        "error": str(exc),
                    }
                )
                if node_id == "brain":
                    run_nodes.append(self._policy_record(True, None))

        packet_output = outputs.get("packet", {})
        if status_summary != "error":
            blocked = (outputs.get("watchdog", {}) or {}).get("block") or (policy_decision and not policy_decision.allow)
            status_summary = "blocked" if blocked else status_summary

        run_record = {
            "run_id": run_id,
            "created_at": created_at,
            "graph_version": self.graph_spec.version,
            "status": status_summary,
            "nodes": run_nodes,
            "packet": packet_output,
            "policy_decision": policy_decision.__dict__ if policy_decision else None,
        }

        if status_summary == "ok":
            metrics.runs_ok += 1
        if status_summary == "blocked":
            metrics.runs_blocked += 1

        data_root = Path(get_settings().data_dir)
        state_dir = data_root / "state" / "runs"
        state_dir.mkdir(parents=True, exist_ok=True)
        with (state_dir / f"{run_id}.json").open("w", encoding="utf-8") as f:
            json.dump(run_record, f, indent=2)
        state_root = data_root / "state"
        state_root.mkdir(parents=True, exist_ok=True)
        with (state_root / "last_run.txt").open("w", encoding="utf-8") as f:
            f.write(run_id)

        report = build_execution_report(run_record)
        persist_report(run_id, report)

        with (state_root / "last_packet.json").open("w", encoding="utf-8") as f:
            json.dump(packet_output, f, indent=2)
        with (state_root / "last_report.json").open("w", encoding="utf-8") as f:
            json.dump(report.model_dump(), f, indent=2)
        with (state_root / "last_run.json").open("w", encoding="utf-8") as f:
            json.dump(run_record, f, indent=2)

        return run_record
