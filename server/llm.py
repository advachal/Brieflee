"""LLM providers for the knowledge service: Groq, Google Gemini or Anthropic Claude.

LLM_PROVIDER picks one ("groq", "gemini" or "claude"). Otherwise every
provider with a key is used in the order Groq, Gemini, Claude: when one fails
(for example its free daily quota is spent) the next is tried. With no key,
available() is False and the service falls back to rule-based answers and
keyword document matching. Keys are read from the environment only.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.5-flash")
CLAUDE_MODEL = "claude-opus-5-5"
GROQ_MODEL = os.environ.get("GROQ_MODEL", "openai/gpt-oss-120b")
# Groq retires models often; when the chosen one is gone, the best available
# from this list (else any chat model on the account) is used instead.
GROQ_PREFERRED = ["openai/gpt-oss-120b", "moonshotai/kimi-k2-instruct-0905", "moonshotai/kimi-k2-instruct",
                  "meta-llama/llama-4-maverick-17b-128e-instruct", "llama-3.3-70b-versatile", "qwen/qwen3-32b",
                  "openai/gpt-oss-20b", "meta-llama/llama-4-scout-17b-16e-instruct", "llama-3.1-8b-instant"]
# Free Groq accounts allow only a few thousand tokens a minute, so long
# documents are sent as their beginning and end (where the parties, counsel,
# prayer and operative part are).
GROQ_MAX_CHARS = int(os.environ.get("GROQ_MAX_CHARS", "16000"))

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


def _groq(system: str, user: str, schema: dict | None, json_mode: bool = True, tries: int = 3) -> str | None:
    text = user
    if len(text) > GROQ_MAX_CHARS:
        keep = GROQ_MAX_CHARS // 3
        text = text[: GROQ_MAX_CHARS - keep] + "\n\n[… middle of the document omitted …]\n\n" + text[-keep:]
    sys_msg = system
    if schema is not None:
        sys_msg = (system + "\n\nReply with one JSON object only, matching this JSON schema exactly "
                   "(every required field present):\n" + json.dumps(schema))
    body = {"model": GROQ_MODEL, "temperature": 0.1, "max_tokens": 4000,
            "messages": [{"role": "system", "content": sys_msg}, {"role": "user", "content": text}]}
    if "gpt-oss" in GROQ_MODEL:
        body["reasoning_effort"] = "low"  # leaves the token budget for the answer
    if schema is not None and json_mode:
        body["response_format"] = {"type": "json_object"}
    req = urllib.request.Request(
        "https://api.groq.com/openai/v1/chat/completions", data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {os.environ['GROQ_API_KEY']}", "Content-Type": "application/json",
                 "User-Agent": "brieflee-knowledge-service"})
    try:
        with urllib.request.urlopen(req, timeout=120, context=_ssl_context()) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read()[:400].decode("utf-8", "replace")
        log(f"Groq HTTP {e.code}: {detail}")
        if e.code == 404 and "model" in detail and tries > 1 and _pick_groq_model():
            return _groq(system, user, schema, json_mode, tries - 1)
        if tries > 1:
            # Too large for the free per-minute token allowance: send less.
            if (e.code == 413 or (e.code == 429 and "Requested" in detail)) and len(text) > 6000:
                return _groq(system, text[: len(text) // 2], schema, json_mode, tries - 1)
            # Per-minute limit reached: wait briefly once.
            if e.code == 429:
                wait = float(e.headers.get("retry-after") or 0)
                if 0 < wait <= 30:
                    time.sleep(wait)
                    return _groq(system, user, schema, json_mode, tries - 1)
            # The model's JSON failed Groq's check: ask again without JSON mode.
            if e.code == 400 and "json" in detail.lower() and json_mode:
                return _groq(system, user, schema, False, tries - 1)
        raise RuntimeError(f"Groq HTTP {e.code}: {detail[:200]}") from None
    return data["choices"][0]["message"]["content"]


def _pick_groq_model() -> bool:
    """Switches GROQ_MODEL to the best model this key can use. True if changed."""
    global GROQ_MODEL
    req = urllib.request.Request("https://api.groq.com/openai/v1/models", headers={
        "Authorization": f"Bearer {os.environ['GROQ_API_KEY']}", "User-Agent": "brieflee-knowledge-service"})
    try:
        with urllib.request.urlopen(req, timeout=30, context=_ssl_context()) as r:
            ids = [m["id"] for m in json.load(r).get("data", []) if m.get("active", True)]
    except Exception as e:
        log(f"Groq model list failed: {e}")
        return False
    chat = [i for i in ids if not any(x in i.lower() for x in ("whisper", "guard", "tts", "orpheus", "playai", "distil"))]
    pick = next((m for m in GROQ_PREFERRED if m in chat), chat[0] if chat else None)
    if not pick or pick == GROQ_MODEL:
        return False
    log(f"Groq model {GROQ_MODEL} unavailable; using {pick}")
    GROQ_MODEL = pick
    _LABELS["groq"] = f"Groq ({pick})"
    return True


def _ssl_context():
    """Certificates from certifi when installed: the standalone Python that uv
    installs on macOS may not find the system certificates."""
    import ssl
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


recent_errors: list[str] = []


def log(msg: str) -> None:
    recent_errors.append(time.strftime("%H:%M:%S ") + msg[:300])
    del recent_errors[:-8]
    print(f"[llm] {msg}", file=sys.stderr, flush=True)


def _parse_json(text: str):
    text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        a, b = text.find("{"), text.rfind("}")
        if a >= 0 and b > a:
            try:
                return json.loads(text[a:b + 1])
            except json.JSONDecodeError:
                pass
    return None


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
            log(f"{p} failed: {type(e).__name__}: {e}")
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
            log(f"{p} failed: {type(e).__name__}: {e}")
            error = e
            continue
        if not text:
            continue
        data = _parse_json(text)
        if isinstance(data, dict):
            for k, v in (schema.get("properties") or {}).items():  # fill gaps a looser model left
                data.setdefault(k, [] if v.get("type") == "array" else "")
            last_used = p
            return data
    if error:
        raise error
    return None
