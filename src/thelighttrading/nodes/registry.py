from __future__ import annotations

from typing import Callable, Dict, Type, List

node_registry: Dict[str, Type] = {}


class NodeRegistry:
    @staticmethod
    def register(node_type: str, cls: Type) -> None:
        node_registry[node_type] = cls

    @staticmethod
    def get(node_type: str):
        return node_registry.get(node_type)

    @staticmethod
    def list_registered() -> List[str]:
        return sorted(node_registry.keys())


def register_node(node_type: str) -> Callable:
    def decorator(cls: Type):
        NodeRegistry.register(node_type, cls)
        setattr(cls, "node_type", node_type)
        return cls

    return decorator
