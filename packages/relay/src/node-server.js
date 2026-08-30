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

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { serve } from '@hono/node-server';
import { serveStatic } from '@hono/node-server/serve-static';
import { createNodeWebSocket } from '@hono/node-ws';
import { contentSecurityPolicy, createApp, verifyGroupSecret } from './app.js';

function requestOrigin(c) {
  const url = new URL(c.req.url);
  const proto = (c.req.header('x-forwarded-proto') ?? url.protocol).split(',')[0].trim().replace(/:$/, '');
  const host = (c.req.header('x-forwarded-host') ?? c.req.header('host') ?? url.host).split(',')[0].trim();
  try {
    return new URL(`${proto}://${host}`).origin;
  } catch {
    return url.origin;
  }
}

function preferredLanguage(header = '', supported) {
  const supportedSet = new Set(supported);
  return header
    .split(',')
    .map((part, index) => {
      const [tag, ...parameters] = part.trim().toLowerCase().split(';');
      const qualityParameter = parameters.find((parameter) => parameter.trim().startsWith('q='));
      const quality = qualityParameter ? Number(qualityParameter.trim().slice(2)) : 1;
      return { language: tag.split('-')[0], quality, index };
    })
    .filter(({ language, quality }) => supportedSet.has(language) && Number.isFinite(quality) && quality > 0)
    .sort((a, b) => b.quality - a.quality || a.index - b.index)[0]?.language ?? supported[0];
}

function externalReferrerHostname(c) {
  const referrer = c.req.header('referer');
  if (!referrer) {
    return null;
  }
  try {
    const parsed = new URL(referrer);
    if (!['http:', 'https:'].includes(parsed.protocol)) {
      return null;
    }
    return parsed.origin === requestOrigin(c) ? undefined : parsed.hostname.toLowerCase();
  } catch {
    return null;
  }
}

export function startServer({
  storage,
  powSecret,
  port = 8090,
  staticDir,
  adminSecret,
  adminStorageBudgetBytes,
  pushServerUrl,
  feedbackProjectId,
  version,
  migrationTarget,
  migrationSource,
  readOnly,
  dev = false,
}) {
  const topics = new Map();

  const app = createApp({
    storage,
    powSecret,
    adminSecret,
    adminStorageBudgetBytes,
    pushServerUrl,
    feedbackProjectId,
    version,
    migrationTarget,
    migrationSource,
    readOnly,
    dev,
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
    // STATIC_DIR is one complete, immutable frontend deployment. Reading its
    // required entry and discovery files during startup aborts an incomplete
    // deploy.
    // The service worker and the HTML shell live at fixed names, so browsers
    // must revalidate them on every load or a deploy leaves clients on the
    // old build until heuristic caches expire. Extensionless responses include
    // both localized documents and SPA fallbacks, so they revalidate too.
    app.use('/*', async (c, next) => {
      await next();
      if (
        ['/sw.js', '/app.html', '/robots.txt', '/sitemap.xml'].includes(
          c.req.path,
        ) ||
        !/\.[^/]*$/.test(c.req.path)
      ) {
        c.header('Cache-Control', 'no-cache');
      }
    });
    app.use('/*', async (c, next) => {
      await next();
      const contentType = c.res.headers.get('content-type') ?? '';
      const fetchMode = c.req.header('sec-fetch-mode');
      const fetchDestination = c.req.header('sec-fetch-dest');
      const knownSubrequest =
        (fetchMode || fetchDestination) && fetchMode !== 'navigate' && fetchDestination !== 'document';
      if (
        c.req.method !== 'GET' ||
        c.res.status !== 200 ||
        !contentType.startsWith('text/html') ||
        knownSubrequest
      ) {
        return;
      }
      const hostname = externalReferrerHostname(c);
      if (hostname === undefined) {
        return;
      }
      const requestDay = new Date().toISOString().slice(0, 10);
      try {
        storage.recordLanding(requestDay, hostname);
      } catch (err) {
        // Traffic accounting must never make the static site unavailable.
        console.error('Failed to record landing', err);
      }
    });
    // Canonical, Open Graph, and crawler-discovery URLs must carry the
    // deployment's own origin, which only the serving process knows. A build
    // that already baked an origin passes through unchanged.
    const withRequestOrigin = (template, c) =>
      template.replaceAll('__CANONICAL_ORIGIN__', requestOrigin(c));
    const shellTemplate = readFileSync(join(staticDir, 'app.html'), 'utf8');
    // The build declares its localized pages in pages.json, so the routes and
    // the files come from the same build and cannot disagree. Each page reads
    // at startup: a manifest entry whose file is missing aborts the deploy
    // here rather than 404ing in production.
    // The feedback project id comes from the process, not the request, so the
    // localized pages carry it from startup. An unset id empties the
    // placeholder, which is what keeps the control hidden on a deployment
    // without the form.
    const { pages } = JSON.parse(readFileSync(join(staticDir, 'pages.json'), 'utf8'));
    const robotsTemplate = readFileSync(join(staticDir, 'robots.txt'), 'utf8');
    const sitemapTemplate = readFileSync(join(staticDir, 'sitemap.xml'), 'utf8');
    const shell = (c) => c.html(withRequestOrigin(shellTemplate, c));
    app.get('/app.html', shell);
    for (const page of pages) {
      if (page.negotiate) {
        const languages = Object.keys(page.paths);
        app.get(page.negotiate, (c) => {
          c.header('Vary', 'Accept-Language');
          return c.redirect(page.paths[preferredLanguage(c.req.header('accept-language'), languages)], 302);
        });
      }
      for (const [language, pagePath] of Object.entries(page.paths)) {
        const template = readFileSync(
          join(staticDir, ...pagePath.split('/').filter(Boolean), 'index.html'),
          'utf8',
        ).replaceAll('__FEEDBACK_PROJECT_ID__', feedbackProjectId ?? '');
        app.get(pagePath.slice(0, -1), (c) => c.redirect(pagePath, 301));
        app.get(`${pagePath}index.html`, (c) => c.redirect(pagePath, 301));
        app.get(pagePath, (c) => {
          c.header('Content-Language', language);
          return c.html(withRequestOrigin(template, c));
        });
      }
    }
    app.get('/robots.txt', (c) => c.text(withRequestOrigin(robotsTemplate, c)));
    app.get('/sitemap.xml', (c) =>
      c.body(withRequestOrigin(sitemapTemplate, c), 200, {
        'Content-Type': 'application/xml; charset=utf-8',
      }),
    );
    // The service worker precaches the shell with its response headers, so a
    // client keeps enforcing the CSP that was live when it installed. Stamping
    // the cache name with a digest of the settings that CSP is built from makes
    // a config change a script change, which is the one thing browsers already
    // watch for: they notice on the next update check and the app offers it as
    // an ordinary update.
    const swDigest = createHash('sha256')
      .update(contentSecurityPolicy({ pushServerUrl, feedbackProjectId, migrationTarget }))
      .digest('hex')
      .slice(0, 16);
    const swSource = readFileSync(join(staticDir, 'sw.js'), 'utf8').replaceAll(
      '__CONFIG_DIGEST__',
      swDigest,
    );
    app.get('/sw.js', (c) => c.body(swSource, 200, { 'Content-Type': 'text/javascript; charset=utf-8' }));
    app.use('/*', serveStatic({ root: staticDir }));
    // SPA fallback: client-side routes like /join/<id> must serve the app.
    // A language-prefixed path the manifest does not declare must 404 instead,
    // or a mistyped link gets indexed as a status-200 copy of the shell.
    const languagePrefixes = new Set(
      pages.flatMap((page) => Object.values(page.paths).map((pagePath) => pagePath.split('/')[1])),
    );
    app.get('*', (c, next) =>
      c.req.path.startsWith('/api/') ||
      /\.[^/]*$/.test(c.req.path) ||
      languagePrefixes.has(c.req.path.split('/')[1])
        ? c.notFound()
        : next(),
    );
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
