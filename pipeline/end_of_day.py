"""
pipeline/end_of_day.py

End-of-day pipeline step. Triggered by Godot via OS.create_process().

    python pipeline/end_of_day.py

What it does:
  1.  Clears old flag files
  2.  Loads game_state.json, world_registry.json, world_lore.json, rumors.json
  3.  For each named NPC in the current town:
      a.  Builds NL context from raw game state via nl_descriptors.py
      b.  Loads their variant file (character identity)
      c.  Assembles a structured prompt
      d.  Calls LLM to generate dialogue JSON
      e.  Validates and repairs the output if needed
      f.  Falls back to the previous day's dialogue file if all else fails
      g.  Writes dialogue/{npc_id}_day{N}.json
      h.  Generates an LLM recollection fact and appends it to game_state
  4.  Writes updated npc_facts back to game_state.json
  5.  Writes pipeline_ready.flag (success) or pipeline_crashed.flag (failure)

Flag files written at project root:
  pipeline_ready.flag    -- all dialogue generated, Godot may proceed
  pipeline_failed.flag   -- partial failure, fallbacks used, Godot may proceed
  pipeline_crashed.flag  -- unhandled exception, message inside the file
"""

import json
import logging
import sys
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from config import (
    PROJECT_ROOT,
    GENERATED_DIR,
    DIALOGUE_DIR,
    WORLD_LORE_FILE,
    WORLD_REG_FILE,
    GAME_STATE_FILE,
    RUMORS_FILE,
)
from ollama_client import call_ollama_json, call_ollama
from nl_descriptors import (
    describe_slime_kills,
    describe_field_activity,
    describe_kill_history,
    describe_bounty_progress,
    describe_day,
    describe_first_meeting,
    describe_bounty_acceptance,
    describe_bounty_completion,
    describe_inn_sleep,
    build_fact_context,
    build_rumor_context,
    RECENT_TTL_DAYS,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

# ── Flag file paths ───────────────────────────────────────────────────────────

FLAG_READY   = PROJECT_ROOT / "pipeline_ready.flag"
FLAG_FAILED  = PROJECT_ROOT / "pipeline_failed.flag"
FLAG_CRASHED = PROJECT_ROOT / "pipeline_crashed.flag"


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


def load_variant(variant_id: str) -> dict | None:
    path = GENERATED_DIR / f"{variant_id}.json"
    if not path.exists():
        # Try fallback
        from config import FALLBACKS_DIR
        role  = variant_id.rsplit("_", 1)[0]
        label = variant_id.rsplit("_", 1)[-1]
        path  = FALLBACKS_DIR / f"{role}_{label}.json"
    return load_json(path, f"variant {variant_id}")


def load_previous_dialogue(npc_id: str, day: int) -> dict | None:
    """
    Load the most recent existing dialogue file for this NPC.
    Walks backwards from day-1 looking for a valid file.
    """
    for d in range(day - 1, 0, -1):
        path = DIALOGUE_DIR / f"{npc_id}_day{d}.json"
        if path.exists():
            data = load_json(path, f"previous dialogue day {d}")
            if data:
                logger.info("Loaded previous dialogue: %s", path.name)
                return data
    return None


# ── Prompt assembly ───────────────────────────────────────────────────────────

DIALOGUE_SCHEMA_EXAMPLE = '''
{
  "nodes": {
    "greeting": {
      "text": "Your opening line to the hunter.",
      "responses": [
        {"text": "Player response 1", "next": "some_node"},
        {"text": "Player response 2", "next": "farewell"},
        {"text": "Player response 3", "next": null}
      ]
    },
    "some_node": {
      "text": "Your reply when the hunter picks response 1.",
      "responses": [
        {"text": "I see. Thanks.", "next": "farewell"}
      ]
    },
    "farewell": {
      "text": "Your closing line.",
      "responses": [
        {"text": "Goodbye.", "next": null}
      ]
    }
  }
}
'''.strip()

DIALOGUE_RULES = """
Rules you must follow:
- "greeting" node is required and is always the first node shown.
- "farewell" node is required. All responses in "farewell" must have "next": null.
- Every "next" value must be either null or the exact ID of another node in your JSON.
- Generate 4 to 7 nodes total.
- Player responses should be short (under 10 words).
- Your NPC lines should feel natural and in-character -- 1 to 3 sentences each.
- Do not mention game mechanics, JSON, or the word "node".
- Reference today's events where it feels natural.
- Respond ONLY with the JSON object. No explanation, no markdown, no preamble.
""".strip()


def build_prompt(
    variant: dict,
    world_lore: dict,
    game_state: dict,
    npc_id: str,
    town_id: str,
    rumors: list[dict],
) -> tuple[str, str]:
    """
    Build the (system_prompt, user_prompt) pair for dialogue generation.
    Returns a tuple of (system, prompt).
    """
    day     = game_state.get("meta", {}).get("day", 1)
    flags   = game_state.get("flags", {})
    kills   = game_state.get("world_state", {}).get("monsters_killed_today", {})
    history = game_state.get("world_state", {}).get("monsters_killed_history", [])
    facts   = game_state.get("npc_facts", {}).get(npc_id, {}).get("facts", [])

    role      = variant.get("role", "npc")
    name      = variant.get("name", "NPC")
    fragment  = variant.get("system_prompt_fragment", "")
    town_name = world_lore.get("towns", {}).get(town_id, {}).get("display_name", "the town")

    # ── System prompt ──────────────────────────────────────────────────────────
    system = (
        f"You are {name}, a {role} in the town of {town_name}.\n"
        f"{fragment}\n\n"
        "You are generating today's dialogue for a fantasy RPG. "
        "Stay in character at all times. "
        "Respond ONLY with valid JSON matching the schema you are given. "
        "No preamble, no explanation, no markdown fences."
    )

    # ── Context sections ───────────────────────────────────────────────────────
    world_facts  = world_lore.get("world", {}).get("lore_facts", [])
    town_facts   = world_lore.get("towns", {}).get(town_id, {}).get("lore_facts", [])
    lore_section = "\n".join(f"  - {f}" for f in world_facts + town_facts)

    slime_count   = kills.get("slime1", 0)
    total_kills   = sum(kills.values())
    field_nl      = describe_field_activity(total_kills)
    slime_nl      = describe_slime_kills(slime_count)
    history_nl    = describe_kill_history(history, "slime1")
    day_nl        = describe_day(day)

    met_flag   = flags.get(f"met_{npc_id.split('_')[0]}", False)
    meeting_nl = describe_first_meeting(met_flag, name)
    fact_ctx   = build_fact_context(facts, day)
    rumor_ctx  = build_rumor_context(rumors, day)

    # ── Role-specific context ──────────────────────────────────────────────────
    role_context = ""
    if role == "guild_commander":
        bounties = game_state.get("active_bounties", [])
        if bounties:
            b         = bounties[0]
            quota     = b.get("quota", 0)
            quota_nl  = b.get("quota_nl", "")
            progress  = b.get("kills_toward_quota", 0)
            completed = b.get("completed", False)
            role_context = (
                "\n[Bounty context]\n"
                f"  Active bounty: {quota_nl}\n"
                f"  {describe_bounty_progress(progress, quota, quota_nl)}\n"
                f"  Bounty accepted: {describe_bounty_acceptance(flags.get('first_bounty_accepted', False))}\n"
                f"  Bounty completed: {describe_bounty_completion(flags.get('first_bounty_completed', False))}"
            )
        else:
            role_context = "\n[Bounty context]\n  No active bounties at this time."

    elif role == "innkeeper":
        role_context = (
            "\n[Inn context]\n"
            f"  {describe_inn_sleep(flags.get('player_slept_at_inn', False))}"
        )

    # ── Assemble user prompt ───────────────────────────────────────────────────
    prompt = f"""Today is Day {day}. {day_nl}

[World lore]
{lore_section}

[Today's field report]
  {field_nl}
  {slime_nl}
  {history_nl}

[Your knowledge of this hunter]
  {meeting_nl}
{fact_ctx}

[Rumors in circulation]
{rumor_ctx}
{role_context}

Generate today's dialogue using this JSON schema:
{DIALOGUE_SCHEMA_EXAMPLE}

{DIALOGUE_RULES}"""

    return system, prompt


# ── Dialogue validation and repair ────────────────────────────────────────────

def validate_dialogue(data: dict) -> tuple[bool, str]:
    """
    Check that the generated dialogue matches the required schema.
    Returns (is_valid, error_message).
    """
    nodes = data.get("nodes")
    if not isinstance(nodes, dict):
        return False, "Missing 'nodes' dictionary."
    if "greeting" not in nodes:
        return False, "Missing required 'greeting' node."
    if "farewell" not in nodes:
        return False, "Missing required 'farewell' node."

    node_ids = set(nodes.keys())

    for node_id, node in nodes.items():
        if not isinstance(node.get("text"), str):
            return False, f"Node '{node_id}' missing 'text' string."
        responses = node.get("responses")
        if not isinstance(responses, list) or len(responses) == 0:
            return False, f"Node '{node_id}' missing 'responses' list."
        for r in responses:
            if not isinstance(r.get("text"), str):
                return False, f"Node '{node_id}' has a response missing 'text'."
            next_val = r.get("next")
            if next_val is not None and next_val not in node_ids:
                return False, (
                    f"Node '{node_id}' response points to unknown node '{next_val}'."
                )

    farewell_responses = nodes["farewell"].get("responses", [])
    if any(r.get("next") is not None for r in farewell_responses):
        return False, "Farewell node responses must all have 'next': null."

    return True, ""


def repair_dialogue(broken_output: str, error: str) -> dict | None:
    """
    Ask the LLM to fix a malformed dialogue JSON.
    Returns the repaired dict or None if repair fails.
    """
    logger.info("Attempting dialogue repair. Error: %s", error)
    repair_system = (
        "You are a JSON repair tool. You will be given a broken JSON string "
        "and an error description. Return only the corrected JSON object with no "
        "explanation, no preamble, and no markdown fences."
    )
    repair_prompt = (
        f"Fix this broken dialogue JSON.\n\n"
        f"Error: {error}\n\n"
        f"Broken JSON:\n{broken_output}\n\n"
        f"Schema rules:\n{DIALOGUE_RULES}\n\n"
        f"Return only the corrected JSON."
    )
    return call_ollama_json(prompt=repair_prompt, system=repair_system)


def post_process_dialogue(data: dict, npc_id: str, npc_name: str, day: int) -> dict:
    """
    Add deterministic metadata to validated dialogue:
    - Top-level npc_id, npc_name, day
    - Numeric key fields on each response
    - action: "end_day" on innkeeper sleep responses
    - action: "go_to_field" where appropriate
    """
    nodes = data["nodes"]

    for node_id, node in nodes.items():
        for i, response in enumerate(node.get("responses", [])):
            response["key"] = i + 1

            # Innkeeper sleep responses: add end_day action
            if (
                npc_id.startswith("mira") or npc_id.startswith("innkeeper")
            ) and any(
                word in response.get("text", "").lower()
                for word in ("rest", "sleep", "bed", "room", "night", "morning")
            ):
                if response.get("next") is None:
                    response["action"] = "end_day"

    return {
        "npc_id":   npc_id,
        "npc_name": npc_name,
        "day":      day,
        "nodes":    nodes,
    }


# ── LLM recollection fact generation ─────────────────────────────────────────

def generate_recollection(
    variant: dict,
    game_state: dict,
    npc_id: str,
) -> dict | None:
    """
    Ask the LLM to produce a single subjective recollection fact
    about the hunter from this NPC's perspective.
    This is the LLM's only write to npc_facts -- labeled source: "llm".
    """
    name      = variant.get("name", "The NPC")
    fragment  = variant.get("system_prompt_fragment", "")
    day       = game_state.get("meta", {}).get("day", 1)
    kills     = game_state.get("world_state", {}).get("monsters_killed_today", {})
    slime_nl  = describe_slime_kills(kills.get("slime1", 0))

    system = (
        f"You are {name}. {fragment} "
        "Respond ONLY with a JSON object. No preamble, no markdown."
    )
    prompt = (
        f"The hunter visited you today (Day {day}). {slime_nl} "
        "Write a single sentence capturing your subjective impression of the hunter "
        "from today's interaction. This is your personal recollection, not a fact report.\n\n"
        "Respond ONLY with: {\"recollection\": \"your one sentence here\"}"
    )

    result = call_ollama_json(prompt=prompt, system=system)
    if not result or "recollection" not in result:
        return None

    return {
        "text":      result["recollection"],
        "added_day": day,
        "weight":    "recent",
        "source":    "llm",
    }


# ── NPC processing ────────────────────────────────────────────────────────────

def process_npc(
    npc_id: str,
    npc_config: dict,
    game_state: dict,
    world_lore: dict,
    rumors: list[dict],
    town_id: str,
) -> dict | None:
    """
    Run the full dialogue generation pipeline for one NPC.
    Returns the new LLM recollection fact, or None.
    """
    day         = game_state.get("meta", {}).get("day", 1)
    variant_id  = npc_config.get("variant_id")
    npc_name    = npc_config.get("display_name", npc_id)

    logger.info("Processing NPC: %s (%s)", npc_name, variant_id)

    variant = load_variant(variant_id)
    if variant is None:
        logger.error("Could not load variant for %s. Skipping.", npc_id)
        return None

    # Build prompt
    system, prompt = build_prompt(
        variant, world_lore, game_state, npc_id, town_id, rumors
    )

    # Generate dialogue
    logger.info("Generating dialogue for %s...", npc_name)
    result = call_ollama_json(prompt=prompt, system=system)

    # Validate
    if result:
        valid, error = validate_dialogue(result)
        if not valid:
            logger.warning("Dialogue validation failed for %s: %s", npc_name, error)
            result = repair_dialogue(str(result), error)
            if result:
                valid, error = validate_dialogue(result)
                if not valid:
                    logger.warning("Repair failed for %s. Using fallback.", npc_name)
                    result = None

    # Fallback to previous day
    if result is None:
        logger.warning("Using previous dialogue for %s.", npc_name)
        result = load_previous_dialogue(npc_id, day)

    if result is None:
        logger.error("No dialogue available for %s.", npc_name)
        return None

    # Post-process and write
    processed = post_process_dialogue(result, npc_id, npc_name, day)
    out_path  = DIALOGUE_DIR / f"{npc_id}_day{day}.json"
    DIALOGUE_DIR.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(processed, indent=2))
    logger.info("Written: %s", out_path)

    # Generate recollection fact
    return generate_recollection(variant, game_state, npc_id)


# ── Game state update ─────────────────────────────────────────────────────────

def update_npc_facts(
    game_state: dict,
    npc_id: str,
    new_fact: dict | None,
    day: int,
) -> None:
    """
    Append a new LLM-generated recollection fact to the npc_facts
    section of game_state. Deduplicates by text content.
    game-sourced facts in this section are never modified here.
    """
    if new_fact is None:
        return

    npc_facts = game_state.setdefault("npc_facts", {})
    npc_entry = npc_facts.setdefault(npc_id, {"facts": []})
    facts     = npc_entry.setdefault("facts", [])

    # Deduplicate by text
    existing_texts = {f.get("text") for f in facts}
    if new_fact["text"] not in existing_texts:
        facts.append(new_fact)
        logger.info("Recollection added for %s: %s", npc_id, new_fact["text"][:60])


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    logger.info("End-of-day pipeline starting.")
    clear_flags()

    had_failures = False

    # Load required data
    game_state  = load_json(GAME_STATE_FILE,  "game_state.json")
    world_reg   = load_json(WORLD_REG_FILE,   "world_registry.json")
    world_lore  = load_json(WORLD_LORE_FILE,  "world_lore.json")

    if not game_state or not world_reg or not world_lore:
        write_flag(FLAG_CRASHED, "Missing required data files (game_state, world_registry, or world_lore).")
        return

    # Load rumors (optional -- empty list if missing)
    rumors_data = load_json(RUMORS_FILE, "rumors.json") or {}
    rumors      = rumors_data.get("rumors", [])

    day     = game_state.get("meta", {}).get("day", 1)
    town_id = "thornwall"   # Phase 3: single town. Phase 4: derive from game state.

    logger.info("Processing day %d, town: %s", day, town_id)

    town_data = world_reg.get("towns", {}).get(town_id, {})
    npcs      = town_data.get("npcs", {})

    if not npcs:
        write_flag(FLAG_CRASHED, f"No NPCs found in world_registry for town: {town_id}")
        return

    # Process each named NPC
    for role, npc_config in npcs.items():
        npc_id = npc_config.get("npc_id")
        if not npc_id:
            logger.warning("NPC role %s has no npc_id. Skipping.", role)
            had_failures = True
            continue

        new_fact = process_npc(
            npc_id    = npc_id,
            npc_config= npc_config,
            game_state= game_state,
            world_lore= world_lore,
            rumors    = rumors,
            town_id   = town_id,
        )

        if new_fact:
            update_npc_facts(game_state, npc_id, new_fact, day)
        else:
            had_failures = True

    # Write updated npc_facts back to game_state.json
    # Only the npc_facts section is touched -- Godot owns everything else.
    try:
        existing = json.loads(GAME_STATE_FILE.read_text())
        existing["npc_facts"] = game_state.get("npc_facts", {})
        GAME_STATE_FILE.write_text(json.dumps(existing, indent=2))
        logger.info("game_state.json npc_facts updated.")
    except Exception as exc:
        logger.error("Failed to update game_state.json: %s", exc)
        had_failures = True

    if had_failures:
        write_flag(FLAG_FAILED, "Pipeline completed with some failures. Fallback dialogue used where needed.")
    else:
        write_flag(FLAG_READY, "")

    logger.info("End-of-day pipeline complete.")


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
