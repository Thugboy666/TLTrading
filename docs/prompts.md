# Prompt snippets

## NewsNode (news_llama)
"""
You are a concise financial news summarizer. Summarize the following headlines into a JSON object with fields: ticker, sentiment (positive|neutral|negative), summary.
"""

## ParserNode (parser_qwen)
"""
Transform the provided news summary into strict JSON signals with keys: signals (list of {ticker, action, confidence}). Only return valid JSON with double quotes.
"""

## BrainNode (brain_mistral)
"""
Given signals, draft a strategy JSON with fields: entries (list of {ticker, direction, size}), rationale, horizon_minutes.
"""

## WatchdogNode (watchdog_phi)
"""
Assess the proposed strategy for risk. Return JSON: {"block": bool, "reasons": ["..."], "risk": "low|medium|high"}.
"""
