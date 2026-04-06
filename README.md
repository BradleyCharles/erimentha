# Capstone RPG Project

> A 2D action RPG with a novel **pre-rendered LLM dialogue system** as its academic centerpiece.
> Designed to run fully offline.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Desirable Outcomes](#desirable-outcomes)
- [Architecture and Technical Stack](#architecture-and-technical-stack)
  - [System Diagram](#system-diagram)
  - [Tools and Technologies](#tools-and-technologies)
- [Phase-by-Phase Roadmap](#phase-by-phase-roadmap)

---

## Project Overview

This project is a small-scope 2D action RPG built in **Godot 4**, where a player hunts rare monsters in a field outside town and interacts with NPCs who issue bounties and remember past events.

The game's defining architectural feature is its **pre-rendered LLM dialogue system**: rather than generating NPC dialogue at runtime, a Python pipeline powered by a locally-hosted large language model (LLM) processes the current game state at the start of each in-game day and writes contextually aware, personality-consistent dialogue to JSON files. Godot then reads these files during play, keeping the in-game experience snappy and deterministic while still delivering AI-generated, world-aware NPC speech.

This approach is both the project's primary technical novelty and its main area of academic evaluation.

---

## Desirable Outcomes

### Academic Goals
- Demonstrate a working, well-documented proof-of-concept for pre-rendered LLM dialogue in a game context.
- Show technical depth through the design and implementation of the Python LLM pipeline, game state schema, and Godot integration.
- Deliver a live offline demo that runs reliably end-to-end without an internet connection.
- Produce thorough written documentation covering system architecture, design decisions, and results.

### Technical Goals
- NPCs issue dynamic bounties based on the current monster population in the field.
- NPCs maintain **memory of past days** — they acknowledge previously defeated monsters and adapt their dialogue accordingly.
- Each NPC has a **consistent, stable personality** across all generated dialogue, enforced via per-NPC system prompts.
- The LLM pipeline runs fully offline using a locally hosted model via **Ollama**, requiring no API keys or internet access.
- The Godot game engine and Python pipeline remain **loosely coupled** through a clean JSON file-based handoff, allowing each system to be developed and tested independently.
- All inference runs on consumer GPU hardware within an 8GB VRAM budget.

### Scope Constraints (by design)
- 2 to 3 NPCs
- 3 to 5 monster types
- Single playable area (a town and an adjacent monster field)

Keeping scope small is a deliberate choice, not a compromise. The LLM pipeline is the academic contribution; game complexity is minimized to protect development time and demo reliability.

---

## Architecture and Technical Stack

### System Diagram

```
┌─────────────────────────────────────────────────────┐
│                  START OF EACH IN-GAME DAY           │
│                                                      │
│   Godot 4 (GDScript)                                 │
│   └── Writes game_state.json                         │
│         (monsters killed, bounties, day count, etc.) │
└───────────────────────┬─────────────────────────────┘
                        │ file read
                        ▼
┌─────────────────────────────────────────────────────┐
│   Python LLM Pipeline                                │
│   └── Reads game_state.json                          │
│   └── Builds per-NPC prompts (with system prompt)    │
│   └── Sends request to Ollama (local HTTP API)       │
│   └── Parses response                                │
│   └── Writes dialogue_<npc_name>.json                │
└───────────────────────┬─────────────────────────────┘
                        │ file write
                        ▼
┌─────────────────────────────────────────────────────┐
│   Godot 4 (GDScript)                                 │
│   └── Reads dialogue_<npc_name>.json at game start   │
│   └── Serves pre-rendered lines during play          │
│   └── Displays bounty board content from JSON        │
└─────────────────────────────────────────────────────┘
```

### Tools and Technologies

| Layer | Tool / Technology |
|---|---|
| Game Engine | Godot 4 (GDScript) |
| LLM Serving | Ollama |
| Active Model | Qwen3 8B (`qwen3:8b`) |
| LLM Pipeline | Python 3 scripts |
| Data Interchange | JSON files (`game_state.json`, `dialogue_<npc>.json`) |

**Model configuration note:** Qwen3's extended thinking mode is disabled for this use case via `"think": false` in the Ollama API request body. This avoids unnecessary overhead in NPC dialogue generation and keeps pipeline latency low.

**System requirements:** Ollama requires a CUDA-capable GPU with sufficient VRAM to load the model (~6GB recommended for Qwen3 8B). The Ollama service exposes the model at `http://localhost:11434` and must be running before the pipeline is executed.

---

## Phase-by-Phase Roadmap

### Phase 1 -- Environment Setup ✅
- [x] Install and configure Ollama via official install script
- [x] Confirm GPU-accelerated inference is active
- [x] Pull and validate Qwen3 8B (`qwen3:8b`)
- [x] Enable Ollama as a background service
- [x] Confirm model storage location and resolve any redundant downloads
- [x] Build standalone local test UI to validate Ollama streaming API, persona switching, and tokens/sec throughput
- [x] Confirm cross-origin access is configured to allow local tooling to connect to Ollama

### Phase 2 -- Godot 4 Foundations
- [ ] Install Godot 4 and configure project structure
- [ ] Build player movement and basic scene (town + field)
- [ ] Implement NPC placement and basic interaction triggers
- [ ] Implement monster spawning (3 to 5 types) in the field
- [ ] Build basic combat system (player attacks, monster defeat)
- [ ] Implement day/night cycle and day counter

### Phase 3 -- Game State Architecture
- [ ] Define `game_state.json` schema (day number, monsters defeated per day, active bounties, NPC memory fields)
- [ ] Write GDScript logic to serialize and write `game_state.json` at the start of each new day
- [ ] Write GDScript logic to read `dialogue_<npc_name>.json` at scene load and store lines in memory
- [ ] Validate JSON round-trip between Godot and the filesystem independently of the LLM pipeline

### Phase 4 -- LLM Pipeline Validation (Academic Core)
- [ ] Write Python script to read `game_state.json` and construct per-NPC prompts
- [ ] Implement per-NPC system prompts to enforce consistent personality across days
- [ ] Send requests to Ollama `/api/chat` endpoint with `"think": false`
- [ ] Parse and validate LLM response structure
- [ ] Write output to `dialogue_<npc_name>.json` with a defined schema
- [ ] Test pipeline in isolation with mocked game state inputs
- [ ] Benchmark pipeline latency (target: completes before player interaction is possible)

### Phase 5 -- Combat and Monsters
- [ ] Polish combat feel (hit detection, feedback, enemy AI)
- [ ] Implement per-monster-type defeat tracking in game state
- [ ] Ensure monster population state correctly feeds into `game_state.json` for the LLM pipeline

### Phase 6 -- Dialogue Delivery and Bounty Board UI
- [ ] Build NPC dialogue UI (speech bubble or dialogue box) that reads from pre-rendered JSON
- [ ] Build bounty board UI that displays active bounties parsed from `dialogue_<npc_name>.json`
- [ ] Implement day-start trigger to run Python pipeline before player control is restored
- [ ] Verify NPC memory continuity across multiple in-game days (end-to-end test)

### Phase 7 -- Polish and Demo Prep
- [ ] Conduct full offline end-to-end run (no internet, no API keys)
- [ ] Stress test pipeline with edge cases (no monsters killed, all bounties fulfilled, repeated days)
- [ ] Write and finalize project documentation
- [ ] Prepare and rehearse live demo
- [ ] Final review of scope, stability, and academic deliverables

---

*This project is evaluated on technical depth, written documentation, and a live offline demo.*
