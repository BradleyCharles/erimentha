"""
pipeline/nl_descriptors.py

Converts raw Godot game state values into natural language strings
for injection into LLM prompts.

Design principle:
  Raw numbers and booleans never reach the LLM directly.
  Every value passes through a descriptor function that returns
  a human-readable string. Multiple options per tier add variety
  so NPCs do not repeat the same phrasing across days.

  All functions use random.choice() over a list of equivalent
  phrasings -- same meaning, different words.
"""

import random


# ── Slime kills ───────────────────────────────────────────────────────────────

def describe_slime_kills(n: int) -> str:
    if n == 0:
        return random.choice([
            "No slimes were encountered in the field today.",
            "The Ashfield was quiet -- the hunter returned without engaging any slimes.",
            "It was an uneventful day in the field. No slimes cleared.",
        ])
    if n == 1:
        return random.choice([
            "A single slime was cleared from the field.",
            "Light activity -- only one slime encountered today.",
        ])
    if n <= 3:
        return random.choice([
            "A small number of slimes were cleared from the field.",
            "Light slime activity today -- only a handful encountered.",
            "The field was relatively calm. A few slimes were dealt with.",
        ])
    if n <= 7:
        return random.choice([
            "A moderate number of slimes were cleared today.",
            "Steady slime activity in the field -- a reasonable haul.",
            "The hunter worked through a fair number of slimes today.",
        ])
    if n <= 12:
        return random.choice([
            "Heavy slime activity today -- a significant number cleared from the field.",
            "The Ashfield was busy. The hunter cleared a large group of slimes.",
            "Slime numbers were high today. The hunter had a productive run.",
        ])
    if n <= 20:
        return random.choice([
            "The field was overrun. The hunter cleared slimes in large numbers today.",
            "An intense day in the Ashfield -- slimes were encountered everywhere.",
            "The hunter pushed deep and cleared a substantial slime infestation.",
        ])
    return random.choice([
        "Exceptional activity today -- the hunter cleared an extraordinary number of slimes.",
        "The Ashfield saw one of its heaviest slime surges. The hunter met it head on.",
        "A landmark day in the field. Slime numbers were the highest seen in recent memory.",
    ])


# ── Total field kills (all monster types) ────────────────────────────────────

def describe_field_activity(total_kills: int) -> str:
    if total_kills == 0:
        return random.choice([
            "The hunter did not engage any monsters today.",
            "Today was quiet -- no field activity to report.",
        ])
    if total_kills <= 3:
        return random.choice([
            "Light field activity today.",
            "A slow day in the Ashfield.",
        ])
    if total_kills <= 8:
        return random.choice([
            "Moderate field activity today.",
            "A productive if unremarkable day in the field.",
        ])
    if total_kills <= 15:
        return random.choice([
            "Heavy field activity today -- a strong run.",
            "The hunter had a busy day in the Ashfield.",
        ])
    return random.choice([
        "Exceptional field activity -- one of the more intense days on record.",
        "The Ashfield was relentless today. The hunter did not slow down.",
    ])


# ── Cumulative kill history ───────────────────────────────────────────────────

def describe_kill_history(history: list[dict], monster_type: str = "slime1") -> str:
    """
    Summarise the hunter's overall record with a given monster type
    across all recorded days.
    """
    total = sum(day.get(monster_type, 0) for day in history)

    if total == 0:
        return random.choice([
            "The hunter has not yet recorded any confirmed kills of this type.",
            "No prior kills on record for this monster type.",
        ])
    if total <= 5:
        return random.choice([
            "The hunter is just getting started -- a handful of confirmed kills so far.",
            "Early days. A small number of kills on record.",
        ])
    if total <= 15:
        return random.choice([
            "A growing record -- the hunter has cleared a respectable number.",
            "The hunter has established a solid track record in the field.",
        ])
    if total <= 40:
        return random.choice([
            "An experienced hunter by any measure -- a significant body of work in the field.",
            "The hunter has been active. The kill record speaks to real commitment.",
        ])
    return random.choice([
        "A veteran presence. The hunter's record is one of the strongest the guild has seen.",
        "The cumulative kill count puts this hunter among the most productive in the region.",
    ])


# ── Bounty progress ───────────────────────────────────────────────────────────

def describe_bounty_progress(kills: int, quota: int, quota_nl: str) -> str:
    if quota <= 0:
        return "There are no active bounties requiring kills at this time."

    ratio = kills / quota

    if kills == 0:
        return random.choice([
            f"The active bounty has not yet been started. {quota_nl}",
            f"No progress on the current bounty. {quota_nl}",
        ])
    if ratio < 0.33:
        return random.choice([
            f"The bounty is in its early stages -- the hunter has made a small start. {quota_nl}",
            f"Progress is underway but the bulk of the work remains. {quota_nl}",
        ])
    if ratio < 0.66:
        return random.choice([
            f"The bounty is roughly halfway complete.",
            f"Good progress on the active bounty -- about half done.",
        ])
    if ratio < 1.0:
        return random.choice([
            "The bounty is nearly fulfilled. A final push would complete it.",
            "The hunter is close to meeting the bounty quota.",
        ])
    return random.choice([
        "The active bounty has been fulfilled.",
        "The hunter has met the kill quota for the current bounty.",
        "Bounty complete. The quota has been reached.",
    ])


def describe_bounty_quota(quota: int) -> str:
    """
    Convert a raw quota number to a natural language description
    of scale, for use in bounty issuance dialogue.
    """
    if quota <= 3:
        return random.choice([
            "A small number of targets -- a quick job for a capable hunter.",
            "Light work. Just a few confirmed kills needed.",
        ])
    if quota <= 8:
        return random.choice([
            "A moderate bounty -- a solid day's work should cover it.",
            "A reasonable ask. Not trivial but well within a hunter's range.",
        ])
    if quota <= 15:
        return random.choice([
            "A large herd has been spotted. This will take a committed effort.",
            "Heavy numbers. The guild is asking for a thorough clearance.",
        ])
    return random.choice([
        "An exceptional infestation. The guild needs a serious hunter for this.",
        "This is a major push -- the numbers are among the highest the board has posted.",
    ])


# ── Day context ───────────────────────────────────────────────────────────────

def describe_day(day: int) -> str:
    if day == 1:
        return "It is the hunter's first day in the region."
    if day <= 3:
        return random.choice([
            f"Day {day}. The hunter is still finding their footing in the region.",
            f"Early days -- this is only day {day} since the hunter's arrival.",
        ])
    if day <= 7:
        return random.choice([
            f"Day {day}. The hunter has settled into a rhythm.",
            f"The hunter has been operating in the region for {day} days now.",
        ])
    if day <= 14:
        return random.choice([
            f"Day {day}. The hunter is a familiar face around town.",
            f"Two weeks in. The hunter has built a real presence in the region.",
        ])
    return random.choice([
        f"Day {day}. The hunter is a veteran of this region by now.",
        f"Well into their time here -- day {day}. The hunter knows this land.",
    ])


# ── First meeting ─────────────────────────────────────────────────────────────

def describe_first_meeting(has_met: bool, npc_name: str) -> str:
    if not has_met:
        return f"{npc_name} has not yet met this hunter."
    return random.choice([
        f"{npc_name} recognises the hunter from prior meetings.",
        f"The hunter is a known face to {npc_name}.",
        f"{npc_name} and the hunter have spoken before.",
    ])


# ── NPC-specific flags ────────────────────────────────────────────────────────

def describe_bounty_acceptance(accepted: bool) -> str:
    if not accepted:
        return "The hunter has not yet accepted a guild bounty."
    return random.choice([
        "The hunter has accepted at least one guild bounty.",
        "The hunter is known to the guild as an active bounty taker.",
    ])


def describe_bounty_completion(completed: bool) -> str:
    if not completed:
        return "No bounties have been fully completed yet."
    return random.choice([
        "The hunter has completed at least one guild bounty.",
        "The guild has at least one confirmed completion on record for this hunter.",
    ])


def describe_inn_sleep(has_slept: bool) -> str:
    if not has_slept:
        return "The hunter has not yet stayed at the inn."
    return random.choice([
        "The hunter has rested at the inn at least once.",
        "The hunter is a paying guest -- they have stayed at least one night.",
    ])


# ── Fact weight decay ─────────────────────────────────────────────────────────

RECENT_TTL_DAYS = 4   # configurable -- see config.py for override


def resolve_weight(fact: dict, current_day: int, ttl: int = RECENT_TTL_DAYS) -> str:
    """
    Evaluate the effective weight of a fact at prompt-build time.
    The weight stored in the file is the weight at write time.
    Staleness is evaluated live here rather than mutating the file.
    """
    stored = fact.get("weight", "core")
    if stored == "core":
        return "core"
    age = current_day - fact.get("added_day", current_day)
    if age > ttl:
        return "stale"
    return "recent"


# ── Fact context builder ──────────────────────────────────────────────────────

def build_fact_context(facts: list[dict], current_day: int) -> str:
    """
    Convert a list of fact objects into a formatted prompt section.
    Groups by effective weight and source. Stale facts are labeled
    as background only. LLM-sourced facts are labeled as subjective.
    """
    core_game, recent_game, core_llm, recent_llm, stale = [], [], [], [], []

    for fact in facts:
        weight = resolve_weight(fact, current_day)
        source = fact.get("source", "game")
        text   = fact.get("text", "")

        if weight == "stale":
            stale.append(text)
        elif source == "game":
            if weight == "core":
                core_game.append(text)
            else:
                recent_game.append(text)
        else:  # llm
            if weight == "core":
                core_llm.append(text)
            else:
                recent_llm.append(text)

    lines = []

    if core_game or recent_game:
        lines.append("[Verified facts -- treat as ground truth]")
        for t in core_game + recent_game:
            lines.append(f"  - {t}")

    if core_llm or recent_llm:
        lines.append("[Your own recollections -- subjective, may be incomplete]")
        for t in core_llm + recent_llm:
            lines.append(f"  - {t}")

    if stale:
        lines.append("[Background -- possibly outdated]")
        for t in stale:
            lines.append(f"  - {t}")

    return "\n".join(lines) if lines else "No prior history with this hunter."


# ── Rumor context builder ─────────────────────────────────────────────────────

def build_rumor_context(rumors: list[dict], current_day: int,
                        ttl: int = RECENT_TTL_DAYS) -> str:
    """
    Filter rumors to those that are still recent and format them
    as a prompt section. NPCs hear rumors but may not connect them
    to the hunter standing in front of them.
    """
    active = [
        r for r in rumors
        if (current_day - r.get("source_week", 0) * 7) <= ttl * 3
    ]
    if not active:
        return "No notable rumors are circulating at the moment."

    lines = ["[Rumors you have heard -- you do not know if they are true]"]
    for r in active:
        lines.append(f"  - {r['text']}")
    return "\n".join(lines)
