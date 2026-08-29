# Self-host image: relay API + built frontend in one container, one volume.
# Build from the repo root, after building the frontend for same-origin use:
#   pnpm build:optimize
#   docker build -t partage-relay -f packages/relay/Dockerfile .
# Digest-pinned (multi-arch index) so builds are reproducible; re-pin
# deliberately when bumping Node, since the pin also freezes security patches.
FROM node:24-alpine@sha256:d32cdf619f63fe0471182d08996dd516c6275bb5fd31ae06e55a570bd9e1ad43
WORKDIR /app
COPY packages/relay/package.json packages/relay/pnpm-lock.yaml ./
RUN corepack enable pnpm && pnpm install --frozen-lockfile --prod
COPY packages/relay/src ./src
COPY dist ./static
ARG GIT_SHA=""
ENV RELAY_DB=/data/relay.db STATIC_DIR=./static PORT=8090 GIT_SHA=$GIT_SHA
EXPOSE 8090
VOLUME /data
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -q -T 3 -O /dev/null "http://127.0.0.1:${PORT}/health" || exit 1
CMD ["node", "src/server.js"]
