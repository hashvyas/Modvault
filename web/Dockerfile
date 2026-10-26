# Multi-stage Dockerfile for ModVault Next.js Standalone
# Stage 1: Dependencies
FROM node:24-slim AS deps
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

# Stage 2: Builder
FROM node:24-slim AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production
ENV TRANSFORMERS_CACHE=/app/.cache

# Build standalone Next.js application
RUN npm run build

# Pre-download Xenova/all-MiniLM-L6-v2 embedding model into /app/.cache
RUN npm run cache-model

# Ensure public folder exists
RUN mkdir -p /app/public

# Stage 3: Runner
FROM node:24-slim AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
ENV TRANSFORMERS_CACHE=/app/.cache

# Create dedicated non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Copy static assets and standalone bundle
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Copy pre-downloaded transformers model cache so first search has zero delay
COPY --from=builder --chown=nextjs:nodejs /app/.cache /app/.cache

USER nextjs

EXPOSE 3000

CMD ["node", "server.js"]
