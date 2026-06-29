# mimOE AI Agent

A small AI agent built for the mimOE edge runtime. It has two layers:

1. **The mim** (`src/`) — a Node.js microservice deployed inside mimOE that runs the agent loop, exposes tools via MCP, and streams responses via SSE.
2. **Python clients** (`mimoe_client_*.py`) — terminal chat interfaces that connect to mimOE from the outside, demonstrating two different integration approaches.

All inference runs entirely on-device — no cloud calls.

---

## Approach

### Two ways to connect to mimOE

This project intentionally provides two Python clients to show the difference between connecting at the LLM layer vs. the agent layer:

| | `mimoe_client_direct.py` | `mimoe_client_mim.py` |
|---|---|---|
| Connects to | mimOE LLM directly | Deployed mim |
| Endpoint | `/mimik-ai/openai/v1` | `/api/my-agent/v1/chat/completions` |
| Agent logic | Runs in the Python client | Runs inside the mim on mimOE |
| Tools | `get_current_time`, `calculate` | `discoverLocal`, `getDeviceInfo`, `saveNote`, ... |
| Protocol | OpenAI JSON | SSE stream |
| Requires mim deployed | No | Yes |
| Framework | OpenAI Python SDK | `requests` + SSE parsing |

### Framework choices

**Mim (Node.js):** mimik's own `@mimik/agent-kit` and `@mimik/mcp-kit` — purpose-built for the mimOE runtime. They give zero-friction access to the local inference endpoint (port injected via `global.context`), a first-class MCP server for tool definitions, and native access to mimOE platform APIs (mesh discovery, persistent storage).

**Client A — Direct LLM (`mimoe_client_direct.py`):** OpenAI Python SDK with `base_url` pointing to `localhost:8083`. mimOE speaks the OpenAI chat completions protocol verbatim, so swapping cloud → local is a single config line. The agent loop, tool execution, and conversation history all live in the Python script.

**Client B — Via Mim (`mimoe_client_mim.py`):** `requests` library with `stream=True` to consume the SSE events the mim emits. The Python client is just a thin terminal UI — the mim handles the full agent loop including tool calls.

### How the components connect

```
─── Client A (Direct LLM) ───────────────────────────────────────────

  mimoe_client_direct.py
       │  HTTP POST /mimik-ai/openai/v1/chat/completions
       ▼
  mimOE LLM  (smollm2-360m / qwen3-1.7b)
       │
       └─ tool_calls? → execute locally (time, calculate) → loop
          final text?  → print to terminal


─── Client B (Via Mim) ──────────────────────────────────────────────

  mimoe_client_mim.py
       │  HTTP POST /api/my-agent/v1/chat/completions
       ▼
  my-agent mim  (src/index.js → src/agent.js)
       │
       ├──► mimOE LLM  (/mimik-ai/openai/v1)
       └──► MCP tools  (src/tools.js)
               - discoverLocal   (/mimik-mesh/insight/v1)
               - getDeviceInfo   (global.context.info)
               - saveNote / getNote / listNotes / deleteNote
                                 (global.context.storage)
       │
       └─ streams SSE events back → client prints to terminal


─── Mim internal loop (src/) ────────────────────────────────────────

  POST /chat/completions
       │
       ▼
  src/index.js  ← router, extracts messages / context / sessionId
       │
       ▼
  src/agent.js  ← @mimik/agent-kit Agent
       │           agentic loop: LLM → tool_calls → results → LLM → ...
       │
       ├──► mimOE LLM  (127.0.0.1:{httpPort}/mimik-ai/openai/v1)
       └──► src/tools.js  ← @mimik/mcp-kit MCP server
```

---

## Prerequisites

- [mimOE Studio](https://developer.mimik.com/mimOE-studio-early-access-download-v2) installed and running
- A model loaded in the Model View (e.g. **SmolLM2-360M** or **Qwen3-1.7B**)
- Node.js 18+ (for building and deploying the mim)
- Python 3.9+ (for running the clients)

---

## Quick start — Python clients

```bash
pip install -r requirements.txt

# Client A: talk directly to the mimOE LLM (no mim required)
python mimoe_client_direct.py

# Client B: talk to the deployed mim (mim must be running)
python mimoe_client_mim.py
```

Environment variables (optional — defaults work out of the box):

| Variable | Used by | Default |
|---|---|---|
| `MIMOE_ENDPOINT` | `mimoe_client_direct.py` | `http://localhost:8083/mimik-ai/openai/v1` |
| `INFERENCE_API_KEY` | `mimoe_client_direct.py` | `1234` |
| `INFERENCE_MODEL` | `mimoe_client_direct.py` | `smollm2-360m` |
| `MIM_BASE_URL` | `mimoe_client_mim.py` | `http://localhost:8083/api/my-agent/v1` |

---

## Deploy the mim

```bash
# First-time: install deps, build bundle, deploy
./scripts/init.sh
./scripts/deploy.sh --build

# Subsequent deploys (no rebuild needed)
./scripts/deploy.sh

# Tear down and redeploy from scratch
./scripts/deploy.sh --build --redeploy
```

The mim will appear under **Standalone mims** in mimOE Studio once deployed.

### Mim environment variables

Copy `.env` and fill in the keys from mimOE Studio:

| Variable | Where to find it | Default |
|---|---|---|
| `MCM_API_KEY` | mimOE Studio → Settings | required |
| `INFERENCE_API_KEY` | mimOE Studio → Model View → API | `1234` |
| `INFERENCE_MODEL` | Model name as shown in mimOE | `qwen3-1.7b` |
| `INSIGHT_API_KEY` | mimOE Studio → Settings | required |

Store keys in `~/.mimoe/mimoe-api-key.env`; the deploy script sources it automatically.

---

## Mim API

Base URL: `http://localhost:8083/api/my-agent/v1`

**Chat** — streams SSE events:
```
POST /chat/completions
Content-Type: application/json

{
  "messages": [{ "role": "user", "content": "What devices are on my network?" }],
  "context": { "userName": "David" },       ← optional: injected into system prompt
  "x-session-id": "session-001"             ← optional header: scoped memory
}
```

**MCP tool introspection:**
```
POST /mcp
{ "jsonrpc": "2.0", "id": 1, "method": "tools/list" }
```

**Healthcheck:**
```
GET /healthcheck
```

See `test/local.http` for ready-to-run examples (VS Code REST Client).

---

## Project structure

```
mimoe_client_direct.py   Python client — connects directly to mimOE LLM
mimoe_client_mim.py      Python client — connects to the deployed mim via SSE
requirements.txt         Python dependencies (openai, requests)
src/
  index.js    HTTP router — exposes /chat/completions, /mcp, /healthcheck
  agent.js    Agent loop — wires @mimik/agent-kit to the local inference endpoint
  tools.js    MCP tool definitions (device discovery, note storage)
  polyfills.js
scripts/
  init.sh          One-time setup (npm install, build, mimOE runtime)
  start-mimoe.sh   Start the local mimOE instance
  deploy.sh        Build, upload, and start the mim on mimOE
config/
  default.yml          Mim package config
  start-example.json   Environment variable template
test/
  local.http   REST Client requests for manual testing
```

---

## Technical decisions

**Why not LangChain / LlamaIndex for the mim?**
Both add abstraction layers between the code and the HTTP call. mimOE already exposes an OpenAI-compatible endpoint and provides its own agent and MCP SDKs with direct access to platform features (mesh discovery, on-device storage) that a generic framework cannot reach. Fewer dependencies, same result.

**Why MCP for tools?**
The Model Context Protocol gives the agent a clean, declarative way to expose tools. The same `/mcp` endpoint can be consumed by any MCP-compatible client. It also keeps tool logic isolated from agent orchestration logic.

**Why SSE for the chat endpoint?**
The agent loop can involve multiple LLM round-trips and tool executions. SSE lets callers see tool-call progress incrementally rather than waiting for the full loop to complete.

**Why two Python clients?**
To show the architectural choice explicitly: the agent logic can live in the client (direct LLM) or in the server (via mim). Both are valid. The mim approach moves the agent onto the edge device; the direct approach keeps it on the caller.
