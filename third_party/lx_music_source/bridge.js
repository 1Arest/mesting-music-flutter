/* Mesting's restricted LX custom-source protocol bridge.
 * Only the pinned script in this isolated document sees this object. Network
 * access is delegated to the bounded, anonymous Dart transport; CSP denies
 * fetch/XHR, resources, frames and navigation. No platform session is injected.
 */
(() => {
  'use strict';
  const pending = new Map();
  const timers = new Set();
  let next = 0, handler, initialized = false, disposed = false;
  const emit = value => {
    if (!disposed) MestingLx.postMessage(JSON.stringify(value));
  };
  const bytes = (value, encoding = 'utf8') => {
    if (value instanceof ArrayBuffer) return new Uint8Array(value);
    if (ArrayBuffer.isView(value)) return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    if (Array.isArray(value)) return Uint8Array.from(value);
    if (/^hex$/i.test(encoding)) return Uint8Array.from((String(value).match(/../g) || []), h => parseInt(h, 16));
    if (/^base64$/i.test(encoding)) return Uint8Array.from(atob(String(value)), c => c.charCodeAt(0));
    return new TextEncoder().encode(String(value));
  };
  const string = (value, encoding = 'utf8') => {
    const data = bytes(value);
    if (/^hex$/i.test(encoding)) return [...data].map(x => x.toString(16).padStart(2, '0')).join('');
    if (/^base64$/i.test(encoding)) {
      let text = '';
      for (const item of data) text += String.fromCharCode(item);
      return btoa(text);
    }
    return new TextDecoder().decode(data);
  };
  const words = value => CryptoJS.lib.WordArray.create(bytes(value));
  const asBytes = value => bytes(value.toString(CryptoJS.enc.Hex), 'hex');
  const events = Object.freeze({ request: 'request', inited: 'inited', updateAlert: 'updateAlert' });
  const request = (url, options, callback) => {
    if (typeof options === 'function') { callback = options; options = {}; }
    const id = ++next;
    if (disposed || id > 40) {
      queueMicrotask(() => callback?.(new Error('request_limit')));
      return () => {};
    }
    pending.set(id, callback);
    emit({ kind: 'request', id, url: String(url), options: options || {} });
    return () => { pending.delete(id); emit({ kind: 'abort', id }); };
  };
  // Updates are notifications only. The host never downloads/replaces scripts.
  const send = (event, data) => {
    if (event === events.inited && !initialized) {
      initialized = true;
      emit({ kind: 'ready', qualities: data?.sources?.wy?.qualitys || [] });
    }
    return Promise.resolve();
  };
  const crypto = {
    md5: value => CryptoJS.MD5(typeof value === 'string' ? value : words(value)).toString(),
    sha256: value => CryptoJS.SHA256(typeof value === 'string' ? value : words(value)).toString(),
    randomBytes: size => asBytes(CryptoJS.lib.WordArray.random(Math.min(size, 1024))),
    aesEncrypt: (value, mode, key, iv) => {
      const algorithm = String(mode).toLowerCase();
      return asBytes(CryptoJS.AES.encrypt(words(value), words(key), {
        mode: algorithm.endsWith('ecb') ? CryptoJS.mode.ECB : CryptoJS.mode.CBC,
        padding: CryptoJS.pad.Pkcs7,
        iv: iv == null ? undefined : words(iv),
      }).ciphertext);
    },
  };
  const lx = Object.freeze({
    EVENT_NAMES: events, env: 'mobile', version: '2.10.1', request, send,
    on: (event, callback) => { if (event === events.request) handler = callback; },
    utils: Object.freeze({ buffer: Object.freeze({ from: bytes, bufToString: string }), crypto: Object.freeze(crypto) }),
    currentScriptInfo: Object.freeze({ id: 'mesting-pinned', name: '', version: '', script: globalThis.__mestingScript || '' }),
  });
  Object.defineProperty(globalThis, 'lx', { value: lx, writable: false, configurable: false });
  // Sources sometimes log request parameters. Suppress all third-party console
  // output, including update advertisements; diagnostics are host enums only.
  const noop = () => {};
  for (const name of ['log', 'warn', 'error', 'info', 'debug', 'group', 'groupEnd', 'table', 'trace', 'clear']) console[name] = noop;
  const setTimer = globalThis.setTimeout.bind(globalThis);
  const clearTimer = globalThis.clearTimeout.bind(globalThis);
  globalThis.setTimeout = (callback, delay, ...args) => {
    if (disposed || timers.size >= 64) return 0;
    const id = setTimer(() => { timers.delete(id); if (!disposed) callback(...args); }, Math.max(0, delay || 0));
    timers.add(id);
    return id;
  };
  globalThis.clearTimeout = id => { timers.delete(id); clearTimer(id); };
  const intervals = new Set();
  const setInterval = globalThis.setInterval.bind(globalThis);
  const clearInterval = globalThis.clearInterval.bind(globalThis);
  globalThis.setInterval = (callback, delay, ...args) => {
    if (disposed || intervals.size >= 4) return 0;
    const id = setInterval(() => { if (!disposed) callback(...args); }, Math.max(1000, delay || 1000));
    intervals.add(id); return id;
  };
  globalThis.clearInterval = id => { intervals.delete(id); clearInterval(id); };
  Object.defineProperty(globalThis, 'MestingLxRuntime', { value: Object.freeze({
    respond: (id, error, response) => {
      const callback = pending.get(id);
      pending.delete(id);
      if (!callback || disposed) return;
      callback(error ? new Error('request_failed') : null, response, response?.body);
    },
    resolve: async (info, quality) => {
      if (!initialized || !handler || disposed) return emit({ kind: 'failed' });
      try {
        const result = await handler({ source: 'wy', action: 'musicUrl', info: { type: quality, musicInfo: info } });
        const url = typeof result === 'string' ? result : result?.url;
        emit({ kind: 'resolved', url: typeof url === 'string' ? url : '' });
      } catch (_) { emit({ kind: 'failed' }); }
    },
    dispose: () => {
      disposed = true; pending.clear(); handler = undefined;
      for (const id of timers) clearTimer(id);
      for (const id of intervals) clearInterval(id);
      timers.clear(); intervals.clear();
    },
  }), writable: false });
})();
