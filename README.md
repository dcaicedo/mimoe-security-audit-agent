# mimOE AI Agent

A small AI agent deployed as a **mim** (microservice) on [mimOE](https://developer.mimik.com/mimOE-studio-early-access-download-v2), using the local on-device inference endpoint exposed by mimOE Studio. All inference runs entirely on-device — no cloud calls.

---

## Approach

### Framework choice: mimik's own BYO-Framework SDKs

Rather than bringing in LangChain or LlamaIndex, I chose the most direct path: mimik's own `@mimik/agent-kit` and `@mimik/mcp-kit` npm packages. These are purpose-built for the mimOE runtime and gave me:

- A zero-friction connection to the local OpenAI-compatible inference endpoint (no URL hacking, the port is injected via `global.context.info.httpPort`)
- A first-class MCP (Model Context Protocol) server for defining tools the agent can call
- Native access to mimOE platform APIs (device discovery, persistent storage) through `global.context`

The result is a self-contained mim with no external dependencies at runtime.

### How the components connect

```
User Request (HTTP POST /chat/completions)
        │
        ▼
  src/index.js  ← mimOE router, extracts messages/context/sessionId
        │
        ▼
  src/agent.js  ← @mimik/agent-kit Agent
        │         Reads httpPort from global.context to build the
        │         local inference URL dynamically
        │
        ├──► mimOE local inference endpoint
        │    http://127.0.0.1:{httpPort}/mimik-ai/openai/v1/chat/completions
        │    (OpenAI-compatible, runs on-device via mimOE Studio)
        │
        └──► src/tools.js  ← @mimik/mcp-kit MCP server
                            Tools the LLM can call:
                            - discoverLocal   (mimOE mesh insight API)
                            - getDeviceInfo   (global.context.info)
                            - saveNote        (global.context.storage)
                            - getNote
                            - listNotes
                            - deleteNote
```

The agent runs a standard agentic loop: the LLM generates a response, if it includes tool calls the MCP server executes them and feeds results back, and this repeats until the LLM produces a final answer. Events stream back to the caller via SSE.

---

## Prerequisites

- [mimOE Studio](https://developer.mimik.com/mimOE-studio-early-access-download-v2) installed and running
- A model loaded in the Model View (e.g. **Qwen3-1.7B** or SmolLM2)
- Node.js 18+

### Model setup (if Qwen3 is not pre-installed)

The agent defaults to `qwen3-1.7b`. If it is not already in mimOE Studio, provision it via the mimOE model store API (see `test/local.http` for the exact requests, or use the Model View in mimOE Studio).

---

## Environment variables

Copy `.env` and fill in the keys shown in mimOE Studio:

| Variable | Where to find it | Default |
|---|---|---|
| `MCM_API_KEY` | mimOE Studio → Settings | required |
| `INFERENCE_API_KEY` | mimOE Studio → Model View → API | `1234` |
| `INFERENCE_MODEL` | Model name as shown in mimOE | `qwen3-1.7b` |
| `INSIGHT_API_KEY` | mimOE Studio → Settings | required |

Store keys in `~/.mimoe/mimoe-api-key.env` or a project-local `.mimoe/mimoe-api-key.env`; the deploy script sources both automatically.

---

## Deploy

```bash
# First-time: build the mim bundle, then deploy
./scripts/deploy.sh --build

# Subsequent deploys (code already bundled)
./scripts/deploy.sh

# Tear down and redeploy from scratch
./scripts/deploy.sh --build --redeploy
```

The script uploads the mim image to mimOE, starts it, and prints the base URL when ready.

---

## API

Base URL: `http://localhost:8083/api/my-agent/v1`

### Chat

```
POST /chat/completions
Content-Type: application/json

{
  "messages": [
    { "role": "user", "content": "What devices are on my network?" }
  ]
}
```

Response streams as Server-Sent Events. Optional fields:

- `context` — arbitrary JSON injected into the agent's system prompt as user context
- `x-session-id` header — passed to the inference endpoint for session-scoped memory

### MCP tool introspection

```
POST /mcp
Content-Type: application/json

{ "jsonrpc": "2.0", "id": 1, "method": "tools/list" }
```

### Healthcheck

```
GET /healthcheck
```

See `test/local.http` for a full set of ready-to-run request examples (works with the VS Code REST Client extension).

---

## Project structure

```
src/
  agent.js    Agent loop — wires @mimik/agent-kit to the local inference endpoint
  tools.js    MCP tool definitions (device discovery, note storage)
  index.js    HTTP router — exposes /chat/completions, /mcp, /healthcheck
scripts/
  deploy.sh   Build, upload, and start the mim on mimOE
  init.sh     One-time setup helper
config/
  start-example.json  Environment variable template for the mim
test/
  local.http  REST Client requests for manual testing
```

---

## Technical decisions

**Why not LangChain / LlamaIndex?**
Both frameworks add abstraction layers that sit between your code and the HTTP call. Since mimOE already exposes a standard OpenAI-compatible endpoint and provides its own agent and MCP SDKs, adding a third-party orchestration layer would have meant more dependencies with no practical gain. The mimik SDKs give direct, typed access to platform features (mesh discovery, on-device storage) that a generic framework cannot.

**Why MCP for tools?**
The Model Context Protocol gives the agent a clean, declarative way to expose tools, and the same `/mcp` endpoint can be consumed by any MCP-compatible client (e.g. Claude Desktop, other agents on the mesh). It also keeps tool logic isolated from agent orchestration logic.

**Why SSE for the chat endpoint?**
The agent loop can involve multiple LLM round-trips and tool executions. Streaming SSE events lets callers render partial responses and tool-call progress incrementally rather than waiting for the full agentic loop to complete.
