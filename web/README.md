1. Copy `../.env.example` to `../.env` and set `APP_DATABASE_URL` and `JWT_SECRET` (32+ characters, e.g. `openssl rand -hex 32`).
2. Load the database with `python scripts/db_reset.py` and `npm --prefix scripts run embed` from the repo root.
3. Run `npm ci`, then `npm run dev` here (or `npm run build` and `npm run start`) and open http://localhost:3000.
