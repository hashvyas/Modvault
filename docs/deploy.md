# ModVault Deployment Guide: Neon PostgreSQL 18 + Render

This document provides instructions for deploying ModVault to production using **Neon** (PostgreSQL 18 with `pgvector`) and **Render** (containerized Next.js 15 standalone build).

---

## Architecture Overview

```
                      +---------------------------------------+
                      |            Render Web Service         |
                      |   (Docker: Next.js 15 Standalone)     |
                      |  Pre-cached Xenova/all-MiniLM-L6-v2   |
                      +-------------------+-------------------+
                                          |
                                          | APP_DATABASE_URL
                                          | (modvault_app role, RLS enforced)
                                          v
                      +---------------------------------------+
                      |             Neon Database             |
                      |           PostgreSQL 18               |
                      |   Extensions: pgvector, pgcrypto      |
                      +---------------------------------------+
```

---

## 1. Neon Database Setup (PostgreSQL 18)

### Step 1.1: Create Project & Database
1. Log into your [Neon Console](https://console.neon.tech/).
2. Click **Create Project**:
   - **Name**: `modvault-prod`
   - **Postgres Version**: `PostgreSQL 18`
   - **Region**: Choose the region closest to your Render service (e.g. `US East (N. Virginia)` / `us-east-1`).
3. Under **Databases**, create a database named `modvault`.

### Step 1.2: Run Database Schema and Seeds
In your local terminal or via Neon SQL Editor with the administrative connection string:

```bash
# 1. Run migrations, types, procedures, triggers, views, and seed data
psql "$NEON_ADMIN_DATABASE_URL" -f database/run_all.sql

# 2. Verify all seed assertions and compatibility rules
psql "$NEON_ADMIN_DATABASE_URL" -f database/seed_expectations.sql
```

Confirm that the output reports:
```text
seed_expectations: all assertions passed successfully.
```

### Step 1.3: Set the Application Role Password
Change the password for the least-privilege `modvault_app` role:

```sql
ALTER ROLE modvault_app WITH PASSWORD 'your-strong-production-password-here';
```

Assemble the `APP_DATABASE_URL` string:
```text
postgresql://modvault_app:your-strong-production-password-here@ep-xyz.us-east-1.aws.neon.tech/modvault?sslmode=require
```

### Step 1.4: Run Vector Embeddings Pipeline
Populate the 384-dimensional vector embeddings for all 45 curated mods against the Neon database:

```bash
DATABASE_URL="$NEON_ADMIN_DATABASE_URL" npm --prefix scripts run embed
```

Verify that zero null embeddings remain:
```sql
SELECT count(*) FROM mods WHERE embedding IS NULL;
-- Expected output: 0
```

---

## 2. Render Deployment (Next.js 15 Web Service)

Render builds and runs the container using `web/Dockerfile`. Docker does not need to be installed on your local machine.

### Step 2.1: Multi-Stage Dockerfile Overview
The application uses a 3-stage Docker build:
1. **`deps`**: Runs `npm ci` cleanly with locked dependencies.
2. **`builder`**: Builds the standalone Next.js bundle via `npm run build` and runs `npm run cache-model`, pre-downloading `Xenova/all-MiniLM-L6-v2` into `/app/.cache`.
3. **`runner`**: Lightweight Debian Bookworm Slim runtime running as non-root `nextjs` (UID 1001), copying `.next/standalone`, `.next/static`, and the pre-warmed `/app/.cache`.

### Step 2.2: Configure Render Web Service
1. Log into [Render Dashboard](https://dashboard.render.com/).
2. Click **New +** -> **Web Service**.
3. Connect your Git repository (`ModVault`).
4. Configure service settings:
   - **Name**: `modvault-web`
   - **Language**: `Docker`
   - **Root Directory**: `web`
   - **Dockerfile Path**: `Dockerfile` (or `web/Dockerfile` if Root Directory is left blank)
   - **Region**: Same as your Neon database region (e.g., `Oregon (US West)` or `Ohio (US East)`)
   - **Instance Type**: `Starter` (512 MB – 1 GB RAM recommended for ONNX model inference)

### Step 2.3: Environment Variables
Configure the following environment variables in the Render dashboard:

| Variable | Description | Example / Format |
|---|---|---|
| `APP_DATABASE_URL` | Pooled Neon connection string using `modvault_app` | `postgresql://modvault_app:...@ep-...neon.tech/modvault?sslmode=require` |
| `JWT_SECRET` | 64-character random hex string for authentication tokens | `openssl rand -hex 32` |
| `NODE_ENV` | Environment mode | `production` |
| `PORT` | Listening HTTP port | `3000` |
| `TRANSFORMERS_CACHE` | Directory for ONNX embedding model weights | `/app/.cache` |

5. Click **Create Web Service**. Render will build the container, cache the embedding model weights, and spin up the service.

---

## 3. Embedding Model Pre-Caching Verification

Because `npm run cache-model` executes during image build, the model weights for `Xenova/all-MiniLM-L6-v2` are stored directly in `/app/.cache`.
- On cold start or first hybrid search request (`/search?q=...`), the server loads the ONNX runtime session directly from the container filesystem in `< 100ms`, with **zero external Hugging Face network latency**.

---

## 4. End-to-End Verification (Demo Script)

Once deployed, verify the live deployment by performing the demo script steps:
1. **Hybrid Search**: Go to `/search?q=make+the+menus+look+better`. Verify a Skyrim UI mod appears with the `Meaning` badge.
2. **Broken Loadout Diagnostics**: Open `/loadouts/[broken-id]`. Confirm score is `15`, status badge is `broken`, and diagnostic errors appear.
3. **Load Order & Dependency Auto-Fix**: Add missing dependency (`SkyUI`), click **Auto-sort**. Confirm the score increases and error status resolves.
4. **Curator Compatibility Heatmap**: Sign in as `curator`, navigate to `/games/skyrimspecialedition/compat`. Mark two mods incompatible. Verify loadout turns `broken`.
5. **Admin Audit Log**: Sign in as `admin`, navigate to `/admin`. Open the curator's audit entry to review the side-by-side JSON diff.
6. **Row-Level Security Enforcement**: As `modder2`, verify `modder1`'s private loadout is hidden from list views and returns HTTP 404 on direct URL navigation.

---

## 5. UI Screenshots Reference

All pages have been validated and captured during the test suite execution. Screenshots are stored in [`docs/screenshots/`](file:///C:/Modvault/docs/screenshots):

| Screenshot | Description | Preview Path |
|---|---|---|
| `home.png` | Homepage featuring game cards, platform stats, and leaderboards | `docs/screenshots/home.png` |
| `game-skyrim.png` | Skyrim SE catalog page with tag filtering, sorting, and pagination | `docs/screenshots/game-skyrim.png` |
| `01-search-meaning.png` | Hybrid search results displaying reciprocal-rank-fusion `Meaning` badge | `docs/screenshots/01-search-meaning.png` |
| `mod-detail.png` | Mod detail page showing versions, React Flow dependency graph, and compatibility | `docs/screenshots/mod-detail.png` |
| `mod-publish.png` | Mod publication portal with automated vector embedding pipeline | `docs/screenshots/mod-publish.png` |
| `loadouts.png` | Loadouts manager dashboard with health badges | `docs/screenshots/loadouts.png` |
| `02-broken-loadout.png` | Loadout editor diagnostics panel highlighting dependency violations | `docs/screenshots/02-broken-loadout.png` |
| `03-fixed-loadout.png` | Loadout editor after automated topological sort and dependency resolution | `docs/screenshots/03-fixed-loadout.png` |
| `04-curator-heatmap.png` | Matrix heatmap for curators with conflict detail modal | `docs/screenshots/04-curator-heatmap.png` |
| `05-admin-audit-diff.png` | Administrative audit log with visual before/after row diff | `docs/screenshots/05-admin-audit-diff.png` |
| `06-private-loadout-hidden.png` | RLS isolation test verifying 404 response on unauthorized private loadouts | `docs/screenshots/06-private-loadout-hidden.png` |
| `admin.png` | Administrative dashboard for user roles and report recalculations | `docs/screenshots/admin.png` |
