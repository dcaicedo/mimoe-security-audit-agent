// Targeted core-js polyfills for mimOE Duktape runtime.
// Only import the specific modules this mim actually needs.
// With useBuiltIns: false, Babel will NOT expand these into 800+ modules.
//
// Promise           — async/await (transpiled by Babel) + direct usage
// Array.find        — used by @mimik/edge-ms-helper (getRouting)
// Array.from        — used by Object.entries polyfill chain
// Array.includes    — used by swagger middleware (content-type detection)
// String.includes   — used by swagger middleware (content-type detection)
// String.startsWith — used by securityHandlers/bearer.js (auth header parsing)
// Object.assign     — used by @mimik/edge-ms-helper (edge-pollyfill.js)
// Object.entries    — used by processors (context info mapping)
// Object.values     — used by processors and helpers
// Map / Set         — used by swagger middleware internals
// Symbol.iterator   — used by for...of loops (transpiled by Babel)
// Symbol.asyncIterator — used by for-await-of in agent.js (async generator)
// Array.isArray     — used by tools.js (index parsing)
// JSON.stringify     — generally available but polyfill ensures consistency
// String.trim       — used in tools.js (HTML content extraction)
// RegExp            — used in tools.js (HTML stripping regexes)
require('core-js/modules/es.promise');
require('core-js/modules/es.promise.finally');
require('core-js/modules/es.array.find');
require('core-js/modules/es.array.from');
require('core-js/modules/es.array.includes');
require('core-js/modules/es.array.is-array');
require('core-js/modules/es.string.includes');
require('core-js/modules/es.string.starts-with');
require('core-js/modules/es.string.trim');
require('core-js/modules/es.object.assign');
require('core-js/modules/es.object.entries');
require('core-js/modules/es.object.values');
require('core-js/modules/es.map');
require('core-js/modules/es.set');
require('core-js/modules/es.symbol');
require('core-js/modules/es.symbol.iterator');
require('core-js/modules/es.symbol.async-iterator');
require('core-js/modules/es.regexp.exec');
require('core-js/modules/es.string.match');
require('core-js/modules/es.string.replace');
require('core-js/modules/es.json.stringify');
require('core-js/modules/es.array.iterator');
require('core-js/modules/es.string.iterator');
