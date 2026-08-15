FROM node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2 AS build

WORKDIR /app

# Sharp's locally-built addon lives outside the prebuilt package layout. Keep
# both supported musl library directories available so the same image recipe
# works on the x64 staging host and the arm64 production host.
ENV LD_LIBRARY_PATH=/app/node_modules/@img/sharp-libvips-linuxmusl-x64/lib:/app/node_modules/@img/sharp-libvips-linuxmusl-arm64/lib

RUN apk add --no-cache build-base python3

COPY package*.json ./
RUN npm ci && \
    SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm_config_nodedir=/usr/local npm explore sharp -- npm run build && \
    SHARP_ARCH="$(node -p "process.arch")" && \
    SHARP_VERSION="$(node -p "require('./node_modules/sharp/package.json').version")" && \
    case "$SHARP_ARCH" in x64|arm64) ;; *) echo "Unsupported Sharp build architecture: $SHARP_ARCH" >&2; exit 1 ;; esac && \
    test -f "node_modules/sharp/src/build/Release/sharp-linuxmusl-${SHARP_ARCH}-${SHARP_VERSION}.node"

COPY . .
# The local package prebuild hook intentionally runs the repository-owned
# worktree toolchain gate. This Docker context contains backend-nest only, and
# `npm ci`/Prisma generation above are its equivalent deterministic boundary.
# Run the explicit build script while suppressing only pre/post lifecycle hooks.
# The Docker context contains backend-nest only, so bypass the repository-root
# preverify hook for this Docker-only security command. Local/CI npm commands
# still run the repository-owned toolchain gate through package.json.
RUN npm run verify:dockerfile:sharp && npm run verify:security-deps --ignore-scripts && npx --no-install prisma generate && npm run build --ignore-scripts
RUN find dist -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.tsbuildinfo' \) -delete

FROM build AS production-deps

# Keep generated Prisma artifacts, then remove build/test tooling before the
# long-running API image is assembled.
RUN npm prune --omit=dev && \
    npm cache clean --force && \
    SHARP_ARCH="$(node -p "process.arch")" && \
    SHARP_VERSION="$(node -p "require('./node_modules/sharp/package.json').version")" && \
    SHARP_LIBVIPS_DIR="node_modules/@img/sharp-libvips-linuxmusl-${SHARP_ARCH}/lib" && \
    test -f "node_modules/sharp/src/build/Release/sharp-linuxmusl-${SHARP_ARCH}-${SHARP_VERSION}.node" && \
    test -f "${SHARP_LIBVIPS_DIR}/libvips-cpp.so.8.18.3" && \
    node -e "const sharp=require('sharp'); (async()=>{ const png=await sharp({create:{width:2,height:2,channels:3,background:'#1238c8'}}).png().toBuffer(); const metadata=await sharp(png).metadata(); if(metadata.format!=='png'||metadata.width!==2||metadata.height!==2) throw new Error('Sharp runtime PNG control failed'); console.log(JSON.stringify({sharp:sharp.versions.sharp,vips:sharp.versions.vips,sourceBuild:'ok',pngControl:'ok'})); })().catch((error)=>{ console.error(error); process.exit(1); });"

FROM node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2 AS ops

WORKDIR /app
ENV NODE_ENV=production \
    LD_LIBRARY_PATH=/app/node_modules/@img/sharp-libvips-linuxmusl-x64/lib:/app/node_modules/@img/sharp-libvips-linuxmusl-arm64/lib

RUN apk add --no-cache fontconfig ttf-dejavu

COPY --from=build --chown=node:node /app/package*.json ./
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/prisma ./prisma
COPY --from=build --chown=node:node /app/prisma.config.ts ./prisma.config.ts
COPY --from=build --chown=node:node /app/scripts ./scripts

# This target is used only by one-shot migration/maintenance jobs. It keeps
# Prisma CLI and operational scripts out of the long-running API container.
USER node
CMD ["npx", "--no-install", "prisma", "migrate", "deploy"]

FROM node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2 AS runtime

WORKDIR /app
ENV NODE_ENV=production \
    LD_LIBRARY_PATH=/app/node_modules/@img/sharp-libvips-linuxmusl-x64/lib:/app/node_modules/@img/sharp-libvips-linuxmusl-arm64/lib

RUN apk add --no-cache fontconfig ttf-dejavu

COPY --from=production-deps --chown=node:node /app/package*.json ./
COPY --from=production-deps --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist

USER node
EXPOSE 3000
CMD ["node", "dist/src/main.js"]
