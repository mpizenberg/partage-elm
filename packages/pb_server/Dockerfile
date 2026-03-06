# EXAMPLE docker compose file:
#
# version: "3.8"
#
# services:
#   pocketbase:
#     # Upgrade of adrianmusante/pocketbase:latest with my hooks on top
#     image: ghcr.io/mpizenberg/partage-elm/pocketbase:latest
#     restart: always
#     expose:
#       - 8090
#     volumes:
#       - pocketbase-data:/pocketbase-data
#     environment:
#       - POCKETBASE_ADMIN_EMAIL=${ADMIN_EMAIL}
#       - POCKETBASE_ADMIN_PASSWORD=${ADMIN_PASSWORD}
#       - POCKETBASE_ADMIN_UPSERT=true
#       - POCKETBASE_PORT_NUMBER=8090
#       - POW_SECRET=${POW_SECRET}
#       - POCKETBASE_WORKDIR=/pocketbase-data
#       - POCKETBASE_HOOK_DIR=/pocketbase/pb_hooks
#     healthcheck:
#       test: ["CMD", "wget", "-qO-", "http://localhost:8090/_/"]
#       interval: 30s
#       timeout: 10s
#       retries: 3
#
# volumes:
#   pocketbase-data: {}

FROM adrianmusante/pocketbase:latest

COPY bin/pb_hooks /pocketbase/pb_hooks
