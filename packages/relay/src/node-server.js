/**
 * Node HTTP server with WebSocket live updates and optional static frontend
 * serving in one process.
 *
 * WebSocket auth uses an `?auth=<secret>` query parameter because the browser
 * WebSocket API cannot set an Authorization header. The secret only grants
 * relay access (it is a hash of the group key, not the key itself), so a
 * leaked URL never compromises encrypted content. Accepted tradeoff: the URL,
 * secret included, lands in reverse-proxy access logs; authenticating via a
 * first message instead was judged not worth holding unauthenticated sockets.
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { serve } from '@hono/node-server';
import { serveStatic } from '@hono/node-server/serve-static';
import { createNodeWebSocket } from '@hono/node-ws';
import { createApp, verifyGroupSecret } from './app.js';

export function startServer({ storage, powSecret, port = 8090, staticDir, adminSecret, adminStorageBudgetBytes, pushServerUrl, feedbackProjectId, version }) {
  const topics = new Map();

  const app = createApp({
    storage,
    powSecret,
    adminSecret,
    adminStorageBudgetBytes,
    pushServerUrl,
    feedbackProjectId,
    version,
    onAppend(groupId, seq) {
      const sockets = topics.get(groupId);
      if (sockets) {
        const message = JSON.stringify({ seq });
        for (const ws of sockets) {
          // A dead socket must not abort a committed append nor skip the
          // remaining subscribers, so each send fails in isolation.
          try {
            ws.send(message);
          } catch {
            // Socket already closed; the next fetch will pull the missed seq.
          }
        }
      }
    },
  });

  const { injectWebSocket, upgradeWebSocket } = createNodeWebSocket({ app });

  app.get(
    '/api/groups/:id/ws',
    async (c, next) => {
      const result = await verifyGroupSecret(storage, c.req.param('id'), c.req.query('auth') ?? '');
      if (result === 'not_found') {
        return c.json({ error: 'Group not found' }, 404);
      }
      if (result === 'unauthorized') {
        return c.json({ error: 'Invalid credentials' }, 401);
      }
      await next();
    },
    upgradeWebSocket((c) => {
      const groupId = c.req.param('id');
      return {
        onOpen(_event, ws) {
          let sockets = topics.get(groupId);
          if (!sockets) {
            sockets = new Set();
            topics.set(groupId, sockets);
          }
          sockets.add(ws);
        },
        onClose(_event, ws) {
          const sockets = topics.get(groupId);
          if (sockets) {
            sockets.delete(ws);
            if (sockets.size === 0) {
              topics.delete(groupId);
            }
          }
        },
      };
    }),
  );

  if (staticDir) {
    // The service worker and the HTML shell live at fixed names, so browsers
    // must revalidate them on every load or a deploy leaves clients on the
    // old build until heuristic caches expire. Extensionless paths are the
    // SPA fallback, which also serves the shell.
    app.use('/*', async (c, next) => {
      await next();
      if (c.req.path === '/sw.js' || c.req.path === '/index.html' || !/\.[^/]*$/.test(c.req.path)) {
        c.header('Cache-Control', 'no-cache');
      }
    });
    // The shell's canonical/Open Graph tags must carry the deployment's own
    // origin, which only the serving process knows: substitute the build-time
    // placeholder with each request's origin (the proxy's forwarded proto,
    // else plain http). A build that already baked an origin passes through
    // unchanged.
    const shellTemplate = readFileSync(join(staticDir, 'index.html'), 'utf8');
    const shell = (c) => {
      const proto = (c.req.header('x-forwarded-proto') ?? 'http').split(',')[0].trim();
      const origin = `${proto}://${c.req.header('host') ?? ''}`;
      return c.html(shellTemplate.replaceAll('__CANONICAL_ORIGIN__', origin));
    };
    app.get('/', shell);
    app.get('/index.html', shell);
    app.use('/*', serveStatic({ root: staticDir }));
    // SPA fallback: client-side routes like /join/<id> must serve the app.
    app.get('*', (c, next) => (c.req.path.startsWith('/api/') ? c.notFound() : next()));
    app.get('*', shell);
  }

  return new Promise((resolve) => {
    const server = serve({ fetch: app.fetch, port }, (info) => {
      resolve({
        server,
        port: info.port,
        url: `http://127.0.0.1:${info.port}`,
        close: () =>
          new Promise((done) => {
            server.close(done);
            server.closeAllConnections();
          }),
      });
    });
    injectWebSocket(server);
  });
}
