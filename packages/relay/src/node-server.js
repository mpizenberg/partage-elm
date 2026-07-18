/**
 * Node self-host adapter: the portable app plus WebSocket live updates and
 * optional static frontend serving, in one process.
 *
 * WebSocket auth uses an `?auth=<secret>` query parameter because the browser
 * WebSocket API cannot set an Authorization header. The secret only grants
 * relay access (it is a hash of the group key, not the key itself), so a
 * leaked URL never compromises encrypted content.
 */

import { serve } from '@hono/node-server';
import { serveStatic } from '@hono/node-server/serve-static';
import { createNodeWebSocket } from '@hono/node-ws';
import { createApp, verifyGroupSecret } from './app.js';

export function startServer({ storage, powSecret, port = 8090, staticDir }) {
  const topics = new Map();

  const app = createApp({
    storage,
    powSecret,
    onAppend(groupId, seq) {
      const sockets = topics.get(groupId);
      if (sockets) {
        const message = JSON.stringify({ seq });
        for (const ws of sockets) {
          ws.send(message);
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
    app.use('/*', serveStatic({ root: staticDir }));
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
