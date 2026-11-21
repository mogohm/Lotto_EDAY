# LOTTO DAY V3 — single image: NestJS API + Flutter web (served same-origin) + Prisma migrations/seed.
# ---------- 1) Flutter web build
FROM debian:bookworm-slim AS web
ARG FLUTTER_VERSION=3.50.1
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
  | tar -xJ -C /opt && git config --global --add safe.directory /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics --enable-web >/dev/null && flutter precache --web >/dev/null
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY lib ./lib
COPY web ./web
COPY analysis_options.yaml ./
RUN flutter build web --release --no-web-resources-cdn

# ---------- 2) API build
FROM node:22-bookworm-slim AS api
RUN apt-get update && apt-get install -y --no-install-recommends openssl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY backend/package.json backend/package-lock.json ./
RUN npm ci --ignore-scripts && npx prisma --version >/dev/null
COPY backend/prisma ./prisma
RUN npx prisma generate
COPY backend/tsconfig.json backend/tsconfig.build.json backend/nest-cli.json ./
COPY backend/src ./src
RUN npm run build && npm prune --omit=dev --ignore-scripts

# ---------- 3) runtime
FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8080 WEB_DIR=/app/public
COPY --from=api /app/node_modules ./node_modules
COPY --from=api /app/dist ./dist
COPY --from=api /app/prisma ./prisma
COPY --from=api /app/package.json ./package.json
COPY --from=web /src/build/web ./public
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/api/v1/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
# migrate → idempotent seed → serve
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/seed.js && node dist/main.js"]
