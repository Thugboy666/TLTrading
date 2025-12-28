import json
import time
from pathlib import Path
from .news_node import NewsNode
from .parser_node import ParserNode
from .brain_node import BrainNode
from .watchdog_node import WatchdogNode
from .packet_node import PacketNode
from ..config.settings import get_settings


class Orchestrator:
    def __init__(self):
        self.news = NewsNode()
        self.parser = ParserNode()
        self.brain = BrainNode()
        self.watchdog = WatchdogNode()
        self.packet_node = PacketNode()

    def run_pipeline(self, headlines: str | None = None) -> dict:
        messages = [{"role": "user", "content": headlines or "Mock headlines"}]
        results = []

        news_result = self.news.run(messages)
        results.append(news_result)

        parser_result = self.parser.run([
            {"role": "system", "content": "Parse summary"},
            {"role": "user", "content": json.dumps(news_result.output)},
        ])
        results.append(parser_result)

        brain_result = self.brain.run([
            {"role": "system", "content": "Strategize"},
            {"role": "user", "content": json.dumps(parser_result.output)},
        ])
        results.append(brain_result)

        watchdog_result = self.watchdog.run([
            {"role": "system", "content": "Risk check"},
            {"role": "user", "content": json.dumps(brain_result.output)},
        ])
        results.append(watchdog_result)

        packet = self.packet_node.build_packet(watchdog_result.output, brain_result.output.get("entries", []))

        run_id = str(int(time.time()))
        run_record = {
            "run_id": run_id,
            "created_at": time.time(),
            "nodes": [
                {"id": r.node_id, "output": r.output, "ts": r.ts} for r in results
            ],
            "packet": packet.model_dump(),
        }

        state_dir = Path(get_settings().data_dir) / "state" / "runs"
        state_dir.mkdir(parents=True, exist_ok=True)
        with (state_dir / f"{run_id}.json").open("w", encoding="utf-8") as f:
            json.dump(run_record, f, indent=2)
        with (Path(get_settings().data_dir) / "state" / "last_run.txt").open("w", encoding="utf-8") as f:
            f.write(run_id)

        return run_record
