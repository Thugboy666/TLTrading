from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Tuple


@dataclass
class NodeSpec:
    id: str
    profile: str
    node_type: str | None = None
    class_path: str | None = None
    inputs_from: List[str] = field(default_factory=list)
    enabled: bool = True


@dataclass
class GraphSpec:
    nodes: Dict[str, NodeSpec]
    edges: List[Tuple[str, str]]
    version: str = "v1"


def default_graph_spec() -> GraphSpec:
    nodes = {
        "news": NodeSpec(
            id="news",
            node_type="news",
            class_path="thelighttrading.nodes.news_node.NewsNode",
            profile="news_llama",
            inputs_from=[],
        ),
        "parser": NodeSpec(
            id="parser",
            node_type="parser",
            class_path="thelighttrading.nodes.parser_node.ParserNode",
            profile="parser_qwen",
            inputs_from=["news"],
        ),
        "brain": NodeSpec(
            id="brain",
            node_type="brain",
            class_path="thelighttrading.nodes.brain_node.BrainNode",
            profile="brain_mistral",
            inputs_from=["parser"],
        ),
        "watchdog": NodeSpec(
            id="watchdog",
            node_type="watchdog",
            class_path="thelighttrading.nodes.watchdog_node.WatchdogNode",
            profile="watchdog_phi",
            inputs_from=["brain"],
        ),
        "packet": NodeSpec(
            id="packet",
            node_type="packet",
            class_path="thelighttrading.nodes.packet_node.PacketNode",
            profile="packet",
            inputs_from=["watchdog", "brain"],
        ),
    }

    edges = [
        ("news", "parser"),
        ("parser", "brain"),
        ("brain", "watchdog"),
        ("watchdog", "packet"),
        ("brain", "packet"),
    ]

    return GraphSpec(nodes=nodes, edges=edges, version="v1")
