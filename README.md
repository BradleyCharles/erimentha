# Erimentha

# **AI-Powered NPC Dialogue System**

### *Dynamic, Real-Time NPC Conversations Using Local LLMs and a Rust Inference Backend*

## **Project Overview**

This project is a Unity-based game that integrates real-time AI dialogue for NPCs using small, fast local language models running through a **Rust inference backend**. Instead of relying on fixed dialogue trees, NPCs generate responses dynamically—reacting to the player, referencing the game world, and maintaining personality consistency.

The project blends modern lightweight LLMs (Phi-3.5-mini and Gemma-2-2B) with traditional game systems to create NPCs that feel alive while preserving developer control over tone, lore, and narrative boundaries.

Everything runs **locally**, offline, and at zero cost.

---

## **How AI Is Integrated Into the Game**

The AI component is responsible for only one part of the experience: **natural-language NPC dialogue**. Unity handles the world; the Rust backend handles the “brains.”

### **Flow of AI Interaction**

1. Player triggers dialogue in Unity
2. Unity sends a structured prompt to the Rust inference server
3. Rust runs the LLM locally using a high-performance wrapper around **llama.cpp**
4. The generated response is returned to Unity
5. Unity displays the NPC’s dialogue and updates characters’ emotional or quest states

The conversation model is given context such as:

* NPC personality
* Quest state
* Player reputation
* Local lore and restrictions
* Recent conversation history

This prevents the model from hallucinating world details and keeps NPCs consistent.

---

## **Technology Stack**

### **Game Engine**

**Unity**
Chosen for its flexibility, asset ecosystem, C# scripting, and ease of integrating external processes through HTTP, TCP sockets, or local IPC. Unity controls game logic, animations, triggers, and dialogue UI.

---

### **AI Models**

**Local LLMs**

* **Phi-3.5-mini** (fastest)
* **Gemma-2-2B** (higher-quality generation)

These models hit the performance sweet spot:

* Fit on consumer hardware
* Generate quickly enough for real-time gameplay
* Don’t require cloud APIs
* Are fine-tunable if needed later

---

### **Inference Backend**

**Rust** (core model runtime)

Rust handles:

* Running the model using a wrapper around **llama.cpp**
* Memory management and quantized model loading
* Streaming token generation
* Request throttling
* Prompt formatting
* Maintaining short-term conversational state
* Providing a clean HTTP or WebSocket API for Unity to consume

Why Rust?

* Extremely fast
* Complete control over memory
* Safe concurrent token streaming
* Ideal for embedding or extending inference logic
* Better long-term maintainability than scripting languages
* Works cleanly across Windows, Linux, macOS, and future console ports

---

### **Model Runtime**

The backend uses:

* **llama.cpp** compiled with Rust bindings (e.g., `llama-rs` or `llm` crate)
* Local quantized `.gguf` models
* Dynamic temperature/top-k/top-p settings
* Optional cache-based world memory

This gives you full control over the LLM pipeline.

---

### **Unity Integration Layer**

Unity communicates with the Rust server using:

* **C# HttpClient** or WebSockets for streaming dialogue
* A request/response protocol using structured JSON
* A dialogue controller that assembles:

  * NPC persona
  * Player query
  * World context
  * Current quest phase
  * Safety constraints (e.g., “Never break character”)

Unity handles the presentation and game-state changes; Rust handles the thinking.

---

## **System Architecture**

```
        ┌────────────────────┐
        │       Unity        │
        │  (Game Engine)     │
        │                    │
        │ - NPC Controllers  │
Player →│ - Event Triggers   │→ Prompt JSON
Input   │ - Dialogue UI      │
        └─────────┬──────────┘
                  │ HTTP/WebSocket
                  ▼
        ┌────────────────────┐
        │     Rust Backend   │
        │   (LLM Runtime)    │
        │                    │
        │ - llama.cpp via    │
        │   Rust bindings    │
        │ - Loads Phi/Gemma  │
        │ - Streams tokens   │→ Response JSON
        │ - Caches context   │
        └─────────┬──────────┘
                  │
                  ▼
        ┌────────────────────┐
        │   Unity Dialogue    │
        │   (NPC Replies)     │
        └────────────────────┘
```

---

## **Key Features**

* Completely local LLM inference (offline, free, private)
* High-speed Rust backend for deterministic resource control
* Real-time NPC conversations
* Personality-locked, lore-safe prompt templates
* Unity integration for event-driven dialog
* Scalable architecture capable of supporting many NPCs
* Swap-in model support for experimentation (e.g., Mistral, Llama 3.x, etc.)

---

## **Why Rust Instead of Ollama or Python?**

Rust gives you:

* Direct control over GPUs, memory, and parallelism
* Faster response time than Python in token generation
* Compiled binaries suitable for shipping with indie games
* Lightweight dependencies (no big runtime environments)
* Stability across platforms
* Ability to embed the inference engine into Unity later if desired

Ollama is easy to use, but Rust is purpose-built for performance and distribution.

Python is flexible, but introduces latency and deployment bloat.

Rust hits the goldilocks zone for your use case.

---

## **Future Enhancements**

* NPC relationship systems tied to AI dialogue
* Persona fine-tuning using LoRA adapters
* In-game memory embeddings
* Procedural dynamic quests
* Emotion-driven token weighting
* Model pruning for even faster real-time inference
* Local TTS/STT for fully voiced conversations

---

## **Summary**

This project combines Unity, Rust, and small-but-mighty LLMs to create a foundational system for AI-powered NPC dialogue. Everything runs locally, without cloud dependencies, giving you maximum control over performance, cost, and creativity.

If you want, I can also generate:
• A shorter README for GitHub landing pages
• A deep technical README for developers
• Setup instructions for the Rust backend
• Example Unity → Rust prompt JSON schema
• A Mermaid diagram for internal documentation

Just tell me what direction you want to expand next.
