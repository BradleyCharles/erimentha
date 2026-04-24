"""
pipeline/chronicle.py

Chronicle and rumor generation pipeline step.
Triggered by Godot via OS.create_process() on day 7 or Ctrl+R.

    python pipeline/chronicle.py

What it does:
  1.  Clears old chronicle flag files
  2.  Loads game_state.json, world_lore.json, and the most recent
      chronicle (narrative field only -- for continuity without
      growing the full context window)
  3.  Builds a NL summary of the current week from kill history
  4.  Generates: narrative, key_events, player_deeds via LLM
  5.  Writes chronicles/week_N.json
  6.  For each player deed, generates one rumor.
      75 % chance the rumor names the player.
      25 % chance it is traceable but anonymous.
  7.  Prunes rumor list to MAX_RUMORS=10, dropping oldest first
  8.  Writes rumors.json
  9.  Writes pipeline_chronicle_ready.flag on success,
      pipeline_chronicle_crashed.flag on unhandled exception.

Flag files (project root):
  pipeline_chronicle_ready.flag
  pipeline_chronicle_failed.flag
  pipeline_chronicle_crashed.flag
"""

import json
import logging
import math
import random
import sys
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from config import (
    PROJECT_ROOT,
    GAME_STATE_FILE,
    WORLD_LORE_FILE,
    WORLD_REG_FILE,
    RUMORS_FILE,
    CHRONICLES_DIR,
)
from ollama_client import call_ollama_json
from nl_descriptors import (
    describe_slime_kills,
    describe_field_activity,
    describe_kill_history,
    describe_day,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

MAX_RUMORS        = 10
NAMED_RUMOR_CHANCE = 0.75   # probability each rumor uses the player's name


# ── Flag file paths ───────────────────────────────────────────────────────────

FLAG_READY   = PROJECT_ROOT / "pipeline_chronicle_ready.flag"
FLAG_FAILED  = PROJECT_ROOT / "pipeline_chronicle_failed.flag"
FLAG_CRASHED = PROJECT_ROOT / "pipeline_chronicle_crashed.flag"


def clear_flags() -> None:
    for f in (FLAG_READY, FLAG_FAILED, FLAG_CRASHED):
        f.unlink(missing_ok=True)


def write_flag(flag: Path, message: str = "") -> None:
    flag.write_text(message)
    logger.info("Flag written: %s", flag.name)


# ── Data loading ──────────────────────────────────────────────────────────────

def load_json(path: Path, label: str) -> dict | None:
    if not path.exists():
        logger.warning("%s not found: %s", label, path)
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        logger.error("Failed to parse %s: %s", label, exc)
        return None


def load_previous_chronicle_narrative(week: int) -> str:
    """
    Load only the narrative field from the most recent previous chronicle.
    This gives the LLM continuity without growing the full context window.
    """
    for w in range(week - 1, 0, -1):
        path = CHRONICLES_DIR / f"week_{w}.json"
        if path.exists():
            data = load_json(path, f"chronicle week {w}")
            if data and "narrative" in data:
                logger.info("Loaded previous chronicle narrative from week %d", w)
                return data["narrative"]
    return ""


def current_week(day: int) -> int:
    return math.ceil(day / 7)


def days_in_week(week: int, history: list[dict]) -> list[dict]:
    """
    Slice history to only the days belonging to the given week.
    History is stored as a list indexed from day 1, so week 1 = indices 0-6.
    """
    start = (week - 1) * 7
    end   = week * 7
    return history[start:end]


# ── NL week summary ───────────────────────────────────────────────────────────

def build_week_summary_nl(
    week_history: list[dict],
    week: int,
    player_name: str,
    flags: dict,
) -> str:
    """
    Convert a week of raw kill history into a NL summary paragraph
    for the chronicle generation prompt.
    """
    total_slime = sum(d.get("slime1", 0) for d in week_history)
    total_all   = sum(sum(d.values()) for d in week_history)
    days_active = sum(1 for d in week_history if sum(d.values()) > 0)
    days_quiet  = len(week_history) - days_active

    lines = [
        f"Hunter: {player_name}",
        f"Week {week} -- {len(week_history)} days recorded.",
        f"Overall field activity: {describe_field_activity(total_all)}",
        f"Slime clearance across the week: {describe_slime_kills(total_slime)}",
        f"Active hunting days: {days_active}.  Quiet days: {days_quiet}.",
    ]

    # Flag highlights
    if flags.get("first_bounty_completed"):
        lines.append("The hunter fulfilled at least one guild bounty this week.")
    if flags.get("player_slept_at_inn"):
        lines.append("The hunter rested at the inn at least once.")
    if flags.get("met_gareth") and not flags.get("met_gareth_prior_week", False):
        lines.append("The hunter met the blacksmith for the first time this week.")
    if flags.get("aldric_warned_about_east"):
        lines.append("The guild commander warned the hunter about activity in the eastern reach.")

    # Per-day highlights
    for i, day_kills in enumerate(week_history):
        day_total = sum(day_kills.values())
        if day_total >= 10:
            lines.append(
                f"Day {i + 1} of the week was particularly intense: "
                f"{describe_field_activity(day_total)}"
            )
        elif day_total == 0 and i > 0:
            lines.append(f"Day {i + 1} of the week: no field activity recorded.")

    return "\n".join(lines)


# ── Chronicle generation ──────────────────────────────────────────────────────

CHRONICLE_SYSTEM = (
    "You are a guild historian chronicling the deeds of a monster hunter "
    "in a fantasy world. Write in the style of a guild record or tavern tale -- "
    "factual but vivid, third person, past tense. "
    "Respond ONLY with valid JSON. No preamble, no explanation, no markdown fences."
)

CHRONICLE_SCHEMA = """
{
  "narrative": "2-3 sentence narrative summary of the week in the historian's voice",
  "key_events": [
    {
      "day": 1,
      "description": "one sentence describing a notable event",
      "player_involved": true
    }
  ],
  "player_deeds": [
    {
      "deed": "short deed description suitable for a rumor",
      "magnitude": "minor"
    }
  ]
}
""".strip()

MAGNITUDE_GUIDE = (
    "Magnitudes: minor (routine work), notable (above average, worth mentioning), "
    "legendary (exceptional, will be talked about for weeks)."
)


def generate_chronicle(
    week: int,
    week_summary_nl: str,
    previous_narrative: str,
    world_name: str,
) -> dict | None:
    continuity = (
        f"Previous week summary (for narrative continuity):\n\"{previous_narrative}\"\n\n"
        if previous_narrative
        else "This is the first week of the hunter's recorded history.\n\n"
    )

    prompt = (
        f"{continuity}"
        f"Events of week {week} in {world_name}:\n"
        f"{week_summary_nl}\n\n"
        f"Generate a chronicle entry. {MAGNITUDE_GUIDE}\n\n"
        f"Include 1-3 key_events and 1-3 player_deeds based on what actually happened.\n"
        f"If the week was quiet, reflect that in the narrative.\n\n"
        f"Respond ONLY with this JSON structure:\n{CHRONICLE_SCHEMA}"
    )

    logger.info("Generating chronicle for week %d...", week)
    result = call_ollama_json(prompt=prompt, system=CHRONICLE_SYSTEM)

    if result and "narrative" in result:
        logger.info("Chronicle generated: %s", result["narrative"][:80])
        return result

    logger.warning("Chronicle generation failed.")
    return None


def fallback_chronicle(week: int, week_summary_nl: str) -> dict:
    """Minimal deterministic fallback if LLM fails."""
    return {
        "narrative": (
            f"Week {week} passed in the region. "
            "The hunter continued their work in the Ashfield without notable incident."
        ),
        "key_events": [],
        "player_deeds": [],
    }


def write_chronicle(week: int, data: dict, days_covered: list[int], day: int) -> None:
    CHRONICLES_DIR.mkdir(parents=True, exist_ok=True)
    output = {
        "schema_version": "1.0",
        "week":           week,
        "days_covered":   days_covered,
        "generated_day":  day,
        **data,
    }
    path = CHRONICLES_DIR / f"week_{week}.json"
    path.write_text(json.dumps(output, indent=2))
    logger.info("Written: %s", path)


# ── Rumor generation ──────────────────────────────────────────────────────────

RUMOR_SYSTEM = (
    "You are generating tavern rumors for a fantasy RPG. "
    "Rumors are short, slightly embellished, and spread by word of mouth. "
    "Write as if overheard at an inn. Past tense. 1-2 sentences. "
    "Respond ONLY with valid JSON. No preamble, no markdown."
)


def generate_rumor(
    deed: str,
    magnitude: str,
    player_name: str,
    player_named: bool,
    week: int,
) -> dict | None:
    name_instruction = (
        f"Use the hunter's name ({player_name}) naturally in the rumor."
        if player_named
        else (
            f"Do NOT use the hunter's name ({player_name}). "
            "Refer to them vaguely -- 'a hunter', 'a stranger', 'someone from the guild'."
        )
    )

    embellishment = {
        "minor":     "Keep it grounded -- routine work, not dramatic.",
        "notable":   "Add a small embellishment -- the kind of detail that grows in retelling.",
        "legendary": "Embellish it significantly -- this is the kind of story people repeat.",
    }.get(magnitude, "")

    prompt = (
        f"A monster hunter performed this deed: {deed}\n"
        f"Magnitude: {magnitude}. {embellishment}\n\n"
        f"{name_instruction}\n\n"
        f"Respond ONLY with: {{\"text\": \"the rumor\"}}"
    )

    result = call_ollama_json(prompt=prompt, system=RUMOR_SYSTEM)
    if not result or "text" not in result:
        logger.warning("Rumor generation failed for deed: %s", deed[:50])
        return None

    rumor_id = f"rumor_w{week}_{random.randint(1000, 9999)}"
    return {
        "id":                   rumor_id,
        "text":                 result["text"],
        "traceable_to_player":  True,
        "player_named":         player_named,
        "source_week":          week,
        "weight":               "recent",
    }


def generate_rumors_for_deeds(
    deeds: list[dict],
    player_name: str,
    week: int,
) -> list[dict]:
    """
    Generate one rumor per deed.
    75 % chance the rumor names the player; 25 % traceable but anonymous.
    The split is determined in Python before the LLM call so it is
    deterministic and the LLM receives an explicit instruction.
    """
    rumors = []
    for deed_entry in deeds:
        deed      = deed_entry.get("deed", "")
        magnitude = deed_entry.get("magnitude", "minor")
        if not deed:
            continue

        player_named = random.random() < NAMED_RUMOR_CHANCE
        rumor = generate_rumor(deed, magnitude, player_name, player_named, week)
        if rumor:
            rumors.append(rumor)
            label = "named" if player_named else "anonymous"
            logger.info("Rumor generated (%s): %s", label, rumor["text"][:60])

    return rumors


# ── Rumor list management ─────────────────────────────────────────────────────

def load_existing_rumors() -> list[dict]:
    if not RUMORS_FILE.exists():
        return []
    data = load_json(RUMORS_FILE, "rumors.json")
    return data.get("rumors", []) if data else []


def prune_and_append(existing: list[dict], new_rumors: list[dict]) -> list[dict]:
    """
    Append new rumors and prune to MAX_RUMORS by dropping oldest first.
    Oldest is determined by source_week.
    """
    combined = existing + new_rumors
    combined.sort(key=lambda r: r.get("source_week", 0))
    if len(combined) > MAX_RUMORS:
        dropped  = combined[: len(combined) - MAX_RUMORS]
        combined = combined[len(combined) - MAX_RUMORS :]
        logger.info("Pruned %d old rumor(s).", len(dropped))
    return combined


def write_rumors(rumors: list[dict], week: int) -> None:
    output = {
        "schema_version":    "1.0",
        "last_updated_week": week,
        "rumors":            rumors,
    }
    RUMORS_FILE.write_text(json.dumps(output, indent=2))
    logger.info("Written: %s  (%d rumors)", RUMORS_FILE, len(rumors))


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    logger.info("Chronicle pipeline starting.")
    clear_flags()

    had_failures = False

    # Load required data
    game_state = load_json(GAME_STATE_FILE, "game_state.json")
    world_lore = load_json(WORLD_LORE_FILE, "world_lore.json")

    if not game_state or not world_lore:
        write_flag(FLAG_CRASHED, "Missing required data files (game_state or world_lore).")
        return

    day          = game_state.get("meta", {}).get("day", 1)
    player_name  = game_state.get("player_name", "the hunter")
    flags        = game_state.get("flags", {})
    full_history = game_state.get("world_state", {}).get("monsters_killed_history", [])
    world_name   = world_lore.get("world", {}).get("name", "the region")
    week         = current_week(day)

    logger.info("Generating chronicle for week %d (day %d), player: %s", week, day, player_name)

    # Slice history to this week only
    week_history  = days_in_week(week, full_history)
    days_covered  = list(range((week - 1) * 7 + 1, (week - 1) * 7 + len(week_history) + 1))

    # Previous narrative for continuity (single field, not full file)
    prev_narrative = load_previous_chronicle_narrative(week)

    # Build NL week summary
    week_summary_nl = build_week_summary_nl(week_history, week, player_name, flags)
    logger.info("Week summary built:\n%s", week_summary_nl)

    # Generate chronicle
    chronicle_data = generate_chronicle(week, week_summary_nl, prev_narrative, world_name)
    if chronicle_data is None:
        logger.warning("Chronicle generation failed. Using fallback.")
        chronicle_data = fallback_chronicle(week, week_summary_nl)
        had_failures   = True

    write_chronicle(week, chronicle_data, days_covered, day)

    # Generate rumors from player deeds
    deeds = chronicle_data.get("player_deeds", [])
    if deeds:
        new_rumors    = generate_rumors_for_deeds(deeds, player_name, week)
        existing      = load_existing_rumors()
        final_rumors  = prune_and_append(existing, new_rumors)
        write_rumors(final_rumors, week)
    else:
        logger.info("No player deeds recorded this week -- no new rumors generated.")

    if had_failures:
        write_flag(FLAG_FAILED, "Chronicle generated with fallback content.")
    else:
        write_flag(FLAG_READY, "")

    logger.info("Chronicle pipeline complete.")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        tb = traceback.format_exc()
        logger.critical("Unhandled exception:\n%s", tb)
        try:
            FLAG_CRASHED.write_text(tb)
        except Exception:
            pass
        sys.exit(1)
