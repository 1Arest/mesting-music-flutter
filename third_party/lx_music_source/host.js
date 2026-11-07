/* The WebView's main thread never evaluates third-party code. A disposable
 * Worker contains each pinned script, including its timers and private cache.
 * Terminating it also stops synchronous loops in an incompatible script.
 */
(() => {
  'use strict';
  let worker, blobUrl;
  const stop = () => {
    worker?.terminate(); worker = undefined;
    if (blobUrl) URL.revokeObjectURL(blobUrl);
    blobUrl = undefined;
  };
  Object.defineProperty(globalThis, 'MestingLxHost', { value: Object.freeze({
    start: (script, bridge, crypto, info) => {
      stop();
      const bootstrap = `self.MestingLx={postMessage:s=>postMessage(s)};
        self.__mestingScript=${JSON.stringify(script)};
        self.onmessage=e=>{const m=e.data;
          if(m.kind==='resolve')MestingLxRuntime.resolve(m.info,m.quality);
          else if(m.kind==='response')MestingLxRuntime.respond(m.id,m.error,m.response);
        };\n`;
      blobUrl = URL.createObjectURL(new Blob([bootstrap, crypto, '\n', bridge, '\n', script], { type: 'text/javascript' }));
      worker = new Worker(blobUrl);
      worker.onmessage = e => MestingLx.postMessage(e.data);
      worker.onerror = e => { e.preventDefault(); MestingLx.postMessage('{"kind":"failed"}'); };
    },
    resolve: (info, quality) => worker?.postMessage({ kind: 'resolve', info, quality }),
    respond: (id, error, response) => worker?.postMessage({ kind: 'response', id, error, response }),
    dispose: stop,
  }), writable: false });
})();
