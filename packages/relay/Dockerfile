# Self-host image: relay API + built frontend in one container, one volume.
# Build from the repo root, after building the frontend for same-origin use:
#   SERVER_URL= pnpm build:optimize
#   docker build -t partage-relay -f packages/relay/Dockerfile .
FROM node:24-alpine
WORKDIR /app
COPY packages/relay/package.json packages/relay/pnpm-lock.yaml ./
RUN corepack enable pnpm && pnpm install --frozen-lockfile --prod
COPY packages/relay/src ./src
COPY dist ./static
ENV RELAY_DB=/data/relay.db STATIC_DIR=./static PORT=8090
EXPOSE 8090
VOLUME /data
CMD ["node", "src/server.js"]
