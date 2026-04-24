"""
pipeline/ollama_client.py

Thin wrapper around the Ollama /api/generate endpoint.

Responsibilities:
  - POST a prompt to Ollama
  - Strip Gemma 4 thinking blocks (<think>...</think>) from the raw response
  - Extract a JSON object from the cleaned text
  - Retry up to MAX_RETRIES times on failure
  - Return None if all retries fail so the caller can use a fallback

Gemma 4 note:
  Thinking cannot be disabled via the API. The model wraps its reasoning in
  <think>...</think> tags before producing its final answer. We strip these
  before any further processing.
"""

import re
import json
import time
import logging
import requests

from config import OLLAMA_URL, OLLAMA_MODEL, MAX_RETRIES, RETRY_DELAY

logger = logging.getLogger(__name__)


# ── Thinking strip ────────────────────────────────────────────────────────────

def strip_thinking(text: str) -> str:
    """
    Remove Gemma 4 <think>...</think> blocks from raw model output.
    Handles multi-line blocks and leading/trailing whitespace after removal.
    """
    cleaned = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL)
    return cleaned.strip()


# ── JSON extraction ───────────────────────────────────────────────────────────

def extract_json(text: str) -> dict | list | None:
    """
    Extract a JSON object or array from model output.

    Handles two common model output patterns:
      1. Bare JSON:           { "name": "Gareth", ... }
      2. Markdown code block: ```json\n{ ... }\n```

    Returns the parsed object/array, or None if parsing fails.
    """
    # Strip markdown fences if present
    fenced = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    candidate = fenced.group(1).strip() if fenced else text.strip()

    # Find the first { or [ and take everything from there
    match = re.search(r"(\{|\[)", candidate)
    if not match:
        logger.warning("No JSON object or array found in model output.")
        return None

    start = match.start()
    candidate = candidate[start:]

    try:
        return json.loads(candidate)
    except json.JSONDecodeError as exc:
        logger.warning("JSON parse failed: %s", exc)
        return None


# ── Core call ─────────────────────────────────────────────────────────────────

def call_ollama(prompt: str, system: str = "", model: str = OLLAMA_MODEL) -> str | None:
    """
    Send a prompt to Ollama and return the cleaned response text.

    Returns None if the request fails after MAX_RETRIES attempts.
    The returned text has thinking blocks stripped but is otherwise raw --
    callers are responsible for further parsing (e.g. extract_json).
    """
    payload = {
        "model":  model,
        "prompt": prompt,
        "stream": False,
    }
    if system:
        payload["system"] = system

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            response = requests.post(OLLAMA_URL, json=payload, timeout=120)
            response.raise_for_status()
            raw = response.json().get("response", "")
            return strip_thinking(raw)
        except requests.RequestException as exc:
            logger.warning("Ollama call attempt %d/%d failed: %s", attempt, MAX_RETRIES, exc)
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_DELAY)

    logger.error("All %d Ollama attempts failed.", MAX_RETRIES)
    return None


# ── JSON call convenience wrapper ─────────────────────────────────────────────

def call_ollama_json(
    prompt: str,
    system: str = "",
    model: str = OLLAMA_MODEL,
) -> dict | list | None:
    """
    Call Ollama and attempt to parse the response as JSON.

    Retries the full call up to MAX_RETRIES times. Returns None if all
    attempts fail or if no valid JSON can be extracted.
    """
    for attempt in range(1, MAX_RETRIES + 1):
        raw = call_ollama(prompt, system=system, model=model)
        if raw is None:
            # call_ollama already exhausted its retries; no point continuing
            return None

        parsed = extract_json(raw)
        if parsed is not None:
            return parsed

        logger.warning(
            "JSON extraction failed on attempt %d/%d. Raw output:\n%s",
            attempt, MAX_RETRIES, raw[:500],
        )
        if attempt < MAX_RETRIES:
            time.sleep(RETRY_DELAY)

    logger.error("JSON extraction failed after %d attempts.", MAX_RETRIES)
    return None
