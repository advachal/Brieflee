"""LLM provider for the knowledge service: Google Gemini or Anthropic Claude.

Chosen by LLM_PROVIDER ("gemini" or "claude"); when unset, whichever key is
present is used (GEMINI_API_KEY first, then ANTHROPIC_API_KEY). With no key,
available() is False and the service falls back to rule-based answers and
keyword document matching. Keys are read from the environment only.
"""
import json
import os

GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.5-flash")
CLAUDE_MODEL = "claude-opus-5-5"


def provider() -> str | None:
    p = (os.environ.get("LLM_PROVIDER") or "").lower()
    if p in ("gemini", "claude"):
        return p
    if os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"):
        return "gemini"
    if os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN"):
        return "claude"
    return None


def available() -> bool:
    return provider() is not None


def label() -> str | None:
    p = provider()
    return {"gemini": f"Gemini ({GEMINI_MODEL})", "claude": f"Claude ({CLAUDE_MODEL})"}.get(p) if p else None


def _gemini(system: str, user: str, schema: dict | None) -> str | None:
    from google import genai
    from google.genai import types

    client = genai.Client(api_key=os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"))
    config = types.GenerateContentConfig(system_instruction=system)
    if schema is not None:
        config.response_mime_type = "application/json"
        config.response_json_schema = schema
    resp = client.models.generate_content(model=GEMINI_MODEL, contents=user, config=config)
    return resp.text


def _claude(system: str, user: str, schema: dict | None) -> str | None:
    import anthropic

    output_config: dict = {"effort": "medium"}
    if schema is not None:
        output_config["format"] = {"type": "json_schema", "schema": schema}
    response = anthropic.Anthropic().beta.messages.create(
        model=CLAUDE_MODEL,
        max_tokens=16000,
        output_config=output_config,
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        system=system,
        messages=[{"role": "user", "content": user}],
    )
    if response.stop_reason in ("refusal", "max_tokens"):
        return None
    return "".join(b.text for b in response.content if b.type == "text")


def complete(system: str, user: str) -> str | None:
    p = provider()
    if p is None:
        return None
    text = (_gemini if p == "gemini" else _claude)(system, user, None)
    return text.strip() if text else None


def complete_json(system: str, user: str, schema: dict) -> dict | None:
    p = provider()
    if p is None:
        return None
    text = (_gemini if p == "gemini" else _claude)(system, user, schema)
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None
