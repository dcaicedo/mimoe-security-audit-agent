const Router = require('router');
const { tools, getMcpEndpoints } = require('./tools');
const agent = require('./agent');

let isHeaderSet = false;

const sendSSE = (res, data) => {
  if (!isHeaderSet) {
    res.statusCode = 200;
    res.setHeader('content-type', 'text/event-stream');
    res.setHeader('transfer-encoding', 'chunked');
    isHeaderSet = true;
  }
  res.write(`data: ${JSON.stringify(data)}\n\n`);
};

const app = Router();

app.post('/mcp', (req, res) => {
  tools.handleMcpRequest(req.body).then((response) => {
    if (response) {
      res.end(JSON.stringify(response));
    } else {
      res.statusCode = 204;
      res.end();
    }
  }).catch((error) => {
    res.statusCode = 500;
    res.end(JSON.stringify({ error }));
  });
});

app.get('/healthcheck', (req, res) => {
  const { info } = global.context;
  res.end(JSON.stringify({ status: 'ok', info }));
});

app.post('/chat/completions', async (req, res) => {
  try {
    const body = JSON.parse(req.body || '{}');
    const { messages, context } = body;
    // Pass full messages array to preserve conversation history
    // Falls back to a simple greeting if no messages provided
    const input = messages?.length > 0 ? messages : [{ role: 'user', content: 'hello' }];
    const sessionId = req.headers?.['x-session-id'];
    const result = await agent.run(input, { ...getMcpEndpoints(), context, sessionId });

    for await (const event of result) {
      sendSSE(res, event);
    }

    res.end();
  } catch (error) {
    console.error('Agent error:', error);
    if (isHeaderSet) {
      sendSSE(res, { error: { message: error.message, type: 'agent_error' } });
      res.end();
    } else {
      res.end(JSON.stringify({ error: { message: error.message, type: 'agent_error' } }));
    }
  }
});

mimikModule.exports = (context, req, res) => {
  global.context = context;
  global.http = global.context.http;
  isHeaderSet = false;
  app(req, res, (e) => {
    res.end(JSON.stringify({ code: e ? 400 : 404, message: e || 'Not Found' }));
  });
};
