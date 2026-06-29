const { Agent } = require('@mimik/agent-kit');

const baseInstructions = 'You are a device assistant running on a local mimOE node.\n\n'
  + 'You have access to these tools:\n'
  + '- discoverLocal: Find devices on the local network\n'
  + '- getDeviceInfo: Get information about this device\n'
  + '- saveNote: Save a note (max 10 notes)\n'
  + '- getNote: Retrieve a note\n'
  + '- listNotes: List all saved notes\n'
  + '- deleteNote: Delete a note\n\n'
  + 'Your purpose is to help users with:\n'
  + '- Network device discovery\n'
  + '- Device information queries\n'
  + '- Managing notes (save, retrieve, list, delete)\n\n'
  + 'Stay focused on these capabilities. If users ask for unrelated tasks\n'
  + '(writing stories, general knowledge questions, etc.), politely explain\n'
  + 'that you are a device assistant and can only help with the tasks listed above.\n\n'
  + 'Be concise and helpful.';

// --- Helpers ---

function getLlmConfig(sessionId) {
  const { httpPort } = global.context.info;
  const {
    INFERENCE_API_KEY = '1234',
    INFERENCE_MODEL = 'qwen3-1.7b',
    INFERENCE_BASE_URI = '/mimik-ai/openai/v1/chat/completions',
  } = global.context.env;

  var config = {
    endpoint: 'http://127.0.0.1:' + httpPort + INFERENCE_BASE_URI,
    apiKey: 'Bearer ' + INFERENCE_API_KEY,
    model: INFERENCE_MODEL,
    max_tokens: 10000,
  };

  if (sessionId) {
    config.headers = { 'x-session-id': sessionId };
  }

  return config;
}

function autoApprove(toolCalls) {
  return { stopAfterExecution: false, approvals: toolCalls.map(function () {
    return true;
  }) };
}

// --- Main entry point ---

async function* run(userMessage, opt) {
  var llmConfig = getLlmConfig(opt && opt.sessionId);

  // Context retrieval - inject dynamic context into instructions
  var instructions = (opt && opt.context)
    ? baseInstructions + '\n\n## User Context\n' + JSON.stringify(opt.context)
    : baseInstructions;

  var agent = new Agent({
    name: 'MCP Assistant',
    instructions: instructions,
    httpClient: global.http,
    mcpEndpoints: (opt && opt.mcpEndpoints),
    llm: llmConfig,
  });

  var result = await agent.run(userMessage, { toolApproval: autoApprove });

  for await (var event of result) {
    if (event.type === 'raw_model_stream_event') {
      yield event.data.event;
    } else if (event.type === 'tool_calls_detected') {
      yield {
        type: 'tool_calls_start',
        tool_calls: event.data.toolCalls,
      };
    } else if (event.type === 'tool_results') {
      yield {
        type: 'tool_calls_complete',
        results: event.data.results,
      };
    } else if (event.type === 'conversation_complete') {
      yield {
        type: 'done',
        final_output: event.data.finalOutput,
      };
      break;
    }
  }
}

module.exports = { run };
