### Tools and Technologies

| Layer | Tool / Technology |
|---|---|
| Game Engine | Godot 4 (GDScript) |
| LLM Serving | Ollama |
| Active Model | Gemma 4 E4B (`gemma4:e4b`) |
| LLM Pipeline | Python 3 scripts |
| Data Interchange | JSON files (`game_state.json`, `dialogue_<npc>.json`) |

**System requirements:** Ollama requires a CUDA-capable GPU with sufficient VRAM to load the model. The Ollama service exposes the model at `http://localhost:11434` and must be running before the pipeline is executed.

---

## Phase-by-Phase Roadmap

### Phase 1 -- Environment Setup ✅
- [x] Install and configure Ollama via official install script
- [x] Confirm GPU-accelerated inference is active
- [x] Pull and validate active model (currently Gemma 4 E4B)
- [x] Enable Ollama as a background service
- [x] Confirm model storage location and resolve any redundant downloads
- [x] Build standalone local test UI to validate Ollama streaming API, persona switching, and tokens/sec throughput
- [x] Confirm cross-origin access is configured to allow local tooling to connect to Ollama

### Phase 2 -- Godot 4 Foundations ✅
- [x] Install Godot 4 and configure project structure
- [x] Build player movement and basic scene (town + field)
- [x] Implement NPC placement and basic interaction triggers (proximity detection via Area2D, per-NPC dialogue JSON loading, name labels)
- [x] Implement monster spawning in the field (slime1 type, capped pool with respawn on kill)
- [x] Build basic combat system (directional attack animations, sword hitbox active on specific frames, kill signal pipeline to SceneManager)
- [x] Implement day counter and scene-to-scene transitions via SceneManager autoload
- [x] Build dialogue box UI with typewriter effect, branching response selection, and built-in scene-transition actions (ahead of Phase 6 schedule)

### Phase 3 -- Game State Architecture ✅
- [x] Define `game_state.json` schema (day number, monsters defeated per day, active bounties, NPC memory fields)
- [x] Write GDScript logic to serialize and write `game_state.json` at the start of each new day
- [x] Write GDScript logic to read `dialogue_<npc_name>.json` at scene load and store lines in memory
- [x] Validate JSON round-trip between Godot and the filesystem independently of the LLM pipeline

### Phase 4 -- LLM Pipeline Validation (Academic Core)
- [x] Write Python script to read `game_state.json` and construct per-NPC prompts
- [x] Implement per-NPC system prompts to enforce consistent personality across days
- [x] Send requests to Ollama `/api/chat` endpoint
- [x] Parse and validate LLM response structure
- [x] Write output to `dialogue_<npc_name>.json` with a defined schema
- [ ] Test pipeline in isolation with mocked game state inputs
- [ ] Benchmark pipeline latency (target: completes before player interaction is possible)

### Phase 5 -- Combat and Monsters
- [ ] Polish combat feel (hit detection, feedback, enemy AI)
- [x] Implement per-monster-type defeat tracking in game state
- [x] Ensure monster population state correctly feeds into `game_state.json` for the LLM pipeline

### Phase 6 -- Dialogue Delivery and Bounty Board UI
- [x] Build NPC dialogue UI (speech bubble or dialogue box) that reads from pre-rendered JSON
- [ ] Build bounty board UI that displays active bounties parsed from `dialogue_<npc_name>.json`
- [x] Implement day-start trigger to run Python pipeline before player control is restored
- [ ] Verify NPC memory continuity across multiple in-game days (end-to-end test)

### Phase 7 -- Polish and Demo Prep
- [ ] Conduct full offline end-to-end run (no internet, no API keys)
- [ ] Stress test pipeline with edge cases (no monsters killed, all bounties fulfilled, repeated days)
- [ ] Write and finalize project documentation
- [ ] Prepare and rehearse live demo
- [ ] Final review of scope, stability, and academic deliverables

---

*This project is evaluated on technical depth, written documentation, and a live offline demo.*
