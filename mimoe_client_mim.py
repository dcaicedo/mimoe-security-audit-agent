"""
mimOE AI Agent — CLIENT B: Via Mim
====================================

DIFFERENCE vs mimoe_client_direct.py
--------------------------------------
This client talks to the deployed mim, not directly to the LLM.
The agent logic (loop, tools, memory) lives in the MIM on mimOE.
This client is just a terminal UI — it sends messages and reads the response.

  mimoe_client_mim.py  →  /api/my-agent/v1/chat/completions  (mim)
                               │
                               └─► mim handles:  LLM + tools + loop
                                   tools: discoverLocal, getDeviceInfo,
                                          saveNote, getNote, listNotes, deleteNote

Use this when:
  - The mim is deployed (visible in mimOE Studio → mims → Standalone mims)
  - You want to use the real mimOE tools (device discovery, persistent notes)
  - You want the agent logic to run on the edge device, not on the client

APPROACH
--------
The mim exposes a /chat/completions endpoint that streams responses as
Server-Sent Events (SSE). Each SSE event is a JSON object with a "type" field:

  {"type": "tool_calls_start",    "tool_calls": [...]}   ← mim calling a tool
  {"type": "tool_calls_complete", "results":   [...]}   ← tool result
  {"type": "done",                "final_output": "..."}  ← final answer
  (raw model stream chunks also arrive for live token streaming)

FRAMEWORK CHOICE: requests library — raw HTTP + SSE parsing
Why: The mim endpoint is not OpenAI-compatible (it returns SSE, not JSON).
     The requests library with stream=True is the simplest way to consume SSE
     without pulling in a heavy framework.

HOW THE COMPONENTS CONNECT
---------------------------

  User input (terminal)
       │
       ▼
  mimoe_client_mim.py  ← sends messages, parses SSE stream
       │
       │  HTTP POST /api/my-agent/v1/chat/completions
       ▼
  my-agent mim  (localhost:8083)
       │  ← full agent loop runs here on mimOE
       │
       ├─► mimOE LLM  (/mimik-ai/openai/v1)
       ├─► discoverLocal  (/mimik-mesh/insight/v1)
       └─► persistent storage  (global.context.storage)
       │
       └── streams SSE events back to this client
"""

import json
import os
import requests

# ── Configuration ──────────────────────────────────────────────────────────────

MIM_BASE_URL = os.getenv("MIM_BASE_URL", "http://localhost:8083/api/my-agent/v1")
CHAT_URL     = f"{MIM_BASE_URL}/chat/completions"


# ── SSE parser ─────────────────────────────────────────────────────────────────

def parse_sse(response):
    """
    Yield parsed JSON objects from an SSE stream.
    SSE lines look like:  data: {"type": "done", ...}
    """
    for line in response.iter_lines():
        if not line:
            continue
        decoded = line.decode("utf-8") if isinstance(line, bytes) else line
        if decoded.startswith("data:"):
            payload = decoded[len("data:"):].strip()
            try:
                yield json.loads(payload)
            except json.JSONDecodeError:
                pass  # skip malformed chunks


# ── Send message to mim ────────────────────────────────────────────────────────

def send_message(history: list, session_id: str = None) -> str:
    """
    POST the conversation history to the mim and return the final answer.
    Prints tool calls as they happen so the user can see what the agent is doing.
    """
    headers = {"Content-Type": "application/json"}
    if session_id:
        headers["x-session-id"] = session_id

    body = {"messages": history}

    final_answer = ""
    text_chunks  = []

    with requests.post(CHAT_URL, json=body, headers=headers, stream=True, timeout=60) as resp:
        resp.raise_for_status()

        for event in parse_sse(resp):
            event_type = event.get("type", "")

            if event_type == "tool_calls_start":
                for tc in event.get("tool_calls", []):
                    print(f"  [tool] calling → {tc.get('function', {}).get('name', '?')}")

            elif event_type == "tool_calls_complete":
                for r in event.get("results", []):
                    print(f"  [tool] result  → {str(r.get('output', ''))[:80]}")

            elif event_type == "done":
                final_answer = event.get("final_output", "")

            else:
                # Raw model stream chunk — collect text as it arrives
                delta = (event.get("delta") or {}).get("text", "")
                if delta:
                    text_chunks.append(delta)

    # Prefer the explicit final_output; fall back to assembled stream chunks
    return final_answer or "".join(text_chunks)


# ── Main — terminal chat loop ──────────────────────────────────────────────────

def main():
    print("=" * 50)
    print("  mimOE Agent  [via mim]")
    print(f"  endpoint: {CHAT_URL}")
    print("  tools   : discoverLocal, getDeviceInfo,")
    print("            saveNote, getNote, listNotes, deleteNote")
    print("  type 'exit' to quit")
    print("=" * 50)
    print()

    # Conversation history — persists across all turns
    history    = []
    session_id = "cli-session-001"

    while True:
        try:
            user_input = input("You: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nBye.")
            break

        if not user_input or user_input.lower() in ("exit", "quit"):
            print("Bye.")
            break

        # Append user message
        history.append({"role": "user", "content": user_input})

        # Send to mim and get answer
        answer = send_message(history, session_id=session_id)

        # Append assistant reply so next turn has full context
        history.append({"role": "assistant", "content": answer})

        print(f"\nAgent: {answer}\n")


if __name__ == "__main__":
    main()
