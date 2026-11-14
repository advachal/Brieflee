"""LLM providers for the knowledge service: Groq, Google Gemini or Anthropic Claude.

LLM_PROVIDER picks one ("groq", "gemini" or "claude"). Otherwise every
provider with a key is used in the order Groq, Gemini, Claude: when one fails
(for example its free daily quota is spent) the next is tried. With no key,
available() is False and the service falls back to rule-based answers and
keyword document matching. Keys are read from the environment only.
"""
import json
import os
import urllib.error
import urllib.request

GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.5-flash")
CLAUDE_MODEL = "claude-opus-5-5"
GROQ_MODEL = os.environ.get("GROQ_MODEL", "llama-3.3-70b-versatile")
# Free Groq accounts allow only a few thousand tokens a minute, so long
# documents are sent as their beginning and end (where the parties, counsel,
# prayer and operative part are).
GROQ_MAX_CHARS = int(os.environ.get("GROQ_MAX_CHARS", "20000"))

_LABELS = {"gemini": f"Gemini ({GEMINI_MODEL})", "claude": f"Claude ({CLAUDE_MODEL})", "groq": f"Groq ({GROQ_MODEL})"}
last_used: str | None = None


def providers() -> list[str]:
    p = (os.environ.get("LLM_PROVIDER") or "").lower()
    if p in _LABELS:
        return [p]
    out = []
    if os.environ.get("GROQ_API_KEY"):
        out.append("groq")
    if os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"):
        out.append("gemini")
    if os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN"):
        out.append("claude")
    return out


def provider() -> str | None:
    ps = providers()
    return ps[0] if ps else None


def available() -> bool:
    return bool(providers())


def label() -> str | None:
    ps = providers()
    return " then ".join(_LABELS[p] for p in ps) if ps else None


def used_label() -> str | None:
    """The provider that answered the last request."""
    return _LABELS.get(last_used) if last_used else label()


def _groq(system: str, user: str, schema: dict | None) -> str | None:
    system_in = system
    if len(user) > GROQ_MAX_CHARS:
        keep = GROQ_MAX_CHARS // 3
        user = user[: GROQ_MAX_CHARS - keep] + "\n\n[… middle of the document omitted …]\n\n" + user[-keep:]
    if schema is not None:
        system = (system + "\n\nReply with one JSON object only, matching this JSON schema exactly "
                  "(every required field present):\n" + json.dumps(schema))
    body = {"model": GROQ_MODEL, "temperature": 0.1, "max_tokens": 3000,
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]}
    if schema is not None:
        body["response_format"] = {"type": "json_object"}
    req = urllib.request.Request(
        "https://api.groq.com/openai/v1/chat/completions", data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {os.environ['GROQ_API_KEY']}", "Content-Type": "application/json",
                 "User-Agent": "brieflee-knowledge-service"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        # 413: request larger than the free per-minute token allowance. Retry once, shorter.
        if e.code == 413 and len(user) > 6000:
            return _groq(system_in, user[: len(user) // 2], schema)
        raise RuntimeError(f"Groq HTTP {e.code}: {e.read()[:300].decode('utf-8', 'replace')}") from None
    return data["choices"][0]["message"]["content"]


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


def _call(name: str, system: str, user: str, schema: dict | None) -> str | None:
    return {"groq": _groq, "gemini": _gemini, "claude": _claude}[name](system, user, schema)


def complete(system: str, user: str) -> str | None:
    global last_used
    error = None
    for p in providers():
        try:
            text = _call(p, system, user, None)
        except Exception as e:  # quota, network: try the next provider
            error = e
            continue
        if text:
            last_used = p
            return text.strip()
    if error:
        raise error
    return None


def complete_json(system: str, user: str, schema: dict) -> dict | None:
    global last_used
    error = None
    for p in providers():
        try:
            text = _call(p, system, user, schema)
        except Exception as e:
            error = e
            continue
        if not text:
            continue
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            continue
        if isinstance(data, dict):
            for k, v in (schema.get("properties") or {}).items():  # fill gaps a looser model left
                data.setdefault(k, [] if v.get("type") == "array" else "")
            last_used = p
            return data
    if error:
        raise error
    return None
