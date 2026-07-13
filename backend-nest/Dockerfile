FROM node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2 AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npx prisma generate && npm run build
RUN find dist -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.tsbuildinfo' \) -delete

FROM build AS production-deps

# Keep generated Prisma artifacts, then remove build/test tooling before the
# long-running API image is assembled.
RUN npm prune --omit=dev && npm cache clean --force

FROM node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2 AS ops

WORKDIR /app
ENV NODE_ENV=production

RUN apk add --no-cache fontconfig ttf-dejavu

COPY --from=build --chown=node:node /app/package*.json ./
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/prisma ./prisma
COPY --from=build --chown=node:node /app/prisma.config.ts ./prisma.config.ts
COPY --from=build --chown=node:node /app/scripts ./scripts

# This target is used only by one-shot migration/maintenance jobs. It keeps
# Prisma CLI and operational scripts out of the long-running API container.
USER node
CMD ["npx", "prisma", "migrate", "deploy"]

FROM node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2 AS runtime

WORKDIR /app
ENV NODE_ENV=production

RUN apk add --no-cache fontconfig ttf-dejavu

COPY --from=production-deps --chown=node:node /app/package*.json ./
COPY --from=production-deps --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist

USER node
EXPOSE 3000
CMD ["node", "dist/src/main.js"]
