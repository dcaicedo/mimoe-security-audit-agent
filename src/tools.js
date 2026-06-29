const { McpServer, z } = require('@mimik/mcp-kit');

const server = new McpServer({
  name: 'device-tools',
  version: '1.0.0',
});

function requestAction(opt) {
  return new Promise((resolve, reject) => {
    global.http.request({
      url: opt.url,
      type: opt.method,
      headers: opt.headers,
      authorization: opt.authorization,
      data: opt.jsonBody && JSON.stringify(opt.jsonBody),
      success: (result) => resolve(result),
      error: (err) => {
        if (err instanceof Error) {
          reject(err);
        } else {
          reject(new Error(err.content || err.message));
        }
      },
    });
  });
}

// Discover nearby devices on the local network
server.tool('discoverLocal', 'Discover devices on the local network', {}, async () => {
  const { httpPort } = global.context.info;
  const { INSIGHT_API_KEY } = global.context.env;
  try {
    const res = await requestAction({
      url: `http://127.0.0.1:${httpPort}/mimik-mesh/insight/v1/nodes?type=linkLocal`,
      headers: { Authorization: `Bearer ${INSIGHT_API_KEY}` },
    });

    return {
      content: [{ type: 'text', text: res.data }],
    };
  } catch (err) {
    return {
      content: [{ type: 'text', text: `Discovery failed: ${err.message}` }],
    };
  }
});

// Get info about this device
server.tool('getDeviceInfo', 'Get information about this device', {}, async () => {
  const { info } = global.context;
  return {
    content: [{ type: 'text', text: JSON.stringify(info, null, 2) }],
  };
});

const NOTES_INDEX_KEY = '_notes_index';
const MAX_NOTES = 10;

// Save a note to persistent storage (max 10 notes)
server.tool('saveNote', 'Save a note to persistent storage (max 10 notes)', {
  key: z.string().describe('Note identifier'),
  value: z.string().describe('Note content'),
}, async (args) => {
  const indexJson = await global.context.storage.getItem(NOTES_INDEX_KEY);
  const index = indexJson ? JSON.parse(indexJson) : [];

  if (!index.includes(args.key)) {
    if (index.length >= MAX_NOTES) {
      return {
        content: [{ type: 'text', text: `Cannot save: maximum ${MAX_NOTES} notes reached. Delete a note first.` }],
      };
    }
    index.push(args.key);
    await global.context.storage.setItem(NOTES_INDEX_KEY, JSON.stringify(index));
  }

  await global.context.storage.setItem(args.key, args.value);
  return {
    content: [{ type: 'text', text: `Saved note "${args.key}" (${index.length}/${MAX_NOTES})` }],
  };
});

// Get a note from persistent storage
server.tool('getNote', 'Retrieve a note from persistent storage', {
  key: z.string().describe('Note identifier'),
}, async (args) => {
  const value = await global.context.storage.getItem(args.key);
  if (value) {
    return {
      content: [{ type: 'text', text: value }],
    };
  }
  return {
    content: [{ type: 'text', text: `Note "${args.key}" not found` }],
  };
});

// List all saved notes
server.tool('listNotes', 'List all saved notes', {}, async () => {
  const indexJson = await global.context.storage.getItem(NOTES_INDEX_KEY);
  const index = indexJson ? JSON.parse(indexJson) : [];

  if (index.length === 0) {
    return {
      content: [{ type: 'text', text: 'No notes saved (0/10 slots)' }],
    };
  }

  const keyList = index.map((k) => `- ${k}`).join('\n');
  const text = `Saved note keys (use with getNote):\n${keyList}\n\n(${index.length}/${MAX_NOTES} slots)`;

  return {
    content: [{ type: 'text', text }],
  };
});

// Delete a note from persistent storage
server.tool('deleteNote', 'Delete a note from persistent storage', {
  key: z.string().describe('Note identifier'),
}, async (args) => {
  const indexJson = await global.context.storage.getItem(NOTES_INDEX_KEY);
  const index = indexJson ? JSON.parse(indexJson) : [];

  if (!index.includes(args.key)) {
    return {
      content: [{ type: 'text', text: `Note "${args.key}" not found` }],
    };
  }

  const newIndex = index.filter((k) => k !== args.key);
  await global.context.storage.setItem(NOTES_INDEX_KEY, JSON.stringify(newIndex));
  await global.context.storage.removeItem(args.key);

  return {
    content: [{ type: 'text', text: `Deleted note "${args.key}"` }],
  };
});

function getMcpEndpoints() {
  const { info } = global.context;
  const { httpPort, apiRoot } = info;

  const mcpEndpoints = [{
    name: 'device-tools',
    url: `http://127.0.0.1:${httpPort}${apiRoot}/mcp`,
  }];

  return { mcpEndpoints };
}

module.exports = {
  tools: server,
  getMcpEndpoints,
};
