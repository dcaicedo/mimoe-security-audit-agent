"""
mimOE AI Agent — CLIENT A: Direct LLM
======================================

DIFFERENCE vs mimoe_client_mim.py
-----------------------------------
This client talks directly to the mimOE LLM inference endpoint.
The agent logic (loop, tools, memory) lives HERE in Python.

  mimoe_client_direct.py  →  /mimik-ai/openai/v1  (LLM only)

Use this when:
  - You want full control over the agent loop
  - The mim is not deployed
  - You want to add your own custom tools

APPROACH
--------
mimOE exposes a local, OpenAI-compatible inference endpoint.
The simplest agent is therefore one that points the standard
OpenAI Python SDK at that local URL — no LangChain, no LlamaIndex,
no cloud dependencies.

FRAMEWORK CHOICE: OpenAI Python SDK (v1.x) — raw API calls
Why: mimOE speaks the OpenAI chat completions protocol verbatim.
     Swapping cloud → local is a single config line (base_url).
     Adding a framework on top would mean more dependencies for
     the same result.

HOW THE COMPONENTS CONNECT
---------------------------

  User input (terminal)
       │
       ▼
  mimoe_client_direct.py  ← agent loop + tools + conversation history
       │
       │  HTTP POST /chat/completions  (OpenAI-compatible)
       ▼
  mimOE LLM  (localhost:8083/mimik-ai/openai/v1)
       │
       ├─ tool_calls?  → run tool locally → feed result back → repeat
       └─ final text?  → append to history → print → next turn
"""

import json
import os
from datetime import datetime
from openai import OpenAI

# ── Configuration ─────────────────────────────────────────────────────────────
# Reads from environment variables; falls back to the project defaults in .env

BASE_URL = os.getenv("MIMOE_ENDPOINT", "http://localhost:8083/mimik-ai/openai/v1")
API_KEY  = os.getenv("INFERENCE_API_KEY", "1234")
MODEL    = os.getenv("INFERENCE_MODEL", "smollm2-360m")

# One line to switch from cloud OpenAI to local mimOE
client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

# ── Tool definitions ───────────────────────────────────────────────────────────
# Described in OpenAI function-calling format so the LLM can decide when to use them.

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "get_current_time",
            "description": "Returns the current local date and time.",
            "parameters": {"type": "object", "properties": {}, "required": []},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "calculate",
            "description": "Evaluates a simple arithmetic expression and returns the result.",
            "parameters": {
                "type": "object",
                "properties": {
                    "expression": {
                        "type": "string",
                        "description": "A math expression, e.g. '2 + 2' or '(10 * 3) / 5'",
                    }
                },
                "required": ["expression"],
            },
        },
    },
]


def run_tool(name: str, args: dict) -> str:
    """Execute a tool call locally and return the result as a string."""
    if name == "get_current_time":
        return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    if name == "calculate":
        try:
            # Restrict eval to math only — no builtins, no globals
            result = eval(args["expression"], {"__builtins__": {}}, {})
            return str(result)
        except Exception as e:
            return f"Error evaluating expression: {e}"

    return f"Unknown tool: {name}"


# ── Agent loop ─────────────────────────────────────────────────────────────────

def run_agent(history: list) -> str:
    """
    Agentic loop — receives the full conversation history and returns the reply.

    1. Send full history to mimOE LLM
    2. If LLM returns tool_calls → run them, append results, repeat
    3. If LLM returns plain text → return it (caller appends to history)
    """
    while True:
        response = client.chat.completions.create(
            model=MODEL,
            messages=history,
            tools=TOOLS,
            tool_choice="auto",
        )

        reply = response.choices[0].message

        # No tool calls → final answer
        if not reply.tool_calls:
            return reply.content

        # Tool calls detected → execute, append results, loop again
        history.append(reply)

        for tc in reply.tool_calls:
            args   = json.loads(tc.function.arguments)
            result = run_tool(tc.function.name, args)

            print(f"  [tool] {tc.function.name}({args}) → {result}")

            history.append({
                "role":         "tool",
                "tool_call_id": tc.id,
                "content":      result,
            })


# ── Main — terminal chat loop ──────────────────────────────────────────────────

def main():
    print("=" * 50)
    print("  mimOE Agent")
    print(f"  model   : {MODEL}")
    print(f"  endpoint: {BASE_URL}")
    print("  tools   : get_current_time, calculate")
    print("  type 'exit' to quit")
    print("=" * 50)
    print()

    # Conversation history — persists across all turns
    history = [
        {
            "role": "system",
            "content": (
                "You are a helpful assistant running on a local mimOE device. "
                "You have two tools available: get_current_time and calculate. "
                "Use them when the user's question requires it. "
                "Be concise."
            ),
        }
    ]

    while True:
        # Get user input
        try:
            user_input = input("You: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nBye.")
            break

        if not user_input or user_input.lower() in ("exit", "quit"):
            print("Bye.")
            break

        # Append user message to history
        history.append({"role": "user", "content": user_input})

        # Run agent with full history
        answer = run_agent(history)

        # Append assistant reply to history so next turn remembers it
        history.append({"role": "assistant", "content": answer})

        print(f"\nAgent: {answer}\n")


if __name__ == "__main__":
    main()
