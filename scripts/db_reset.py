"""Drop and rebuild the ModVault database from database/run_all.sql.

Usage (from any folder):
    python scripts/db_reset.py               # rebuild
    python scripts/db_reset.py --with-tests  # rebuild, then run database/tests/run_tests.sql

DATABASE_URL comes from the environment when set (CI), otherwise from .env in the repo root.
Standard library only. Drops all data in schema public.
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DATABASE_DIR = REPO_ROOT / "database"
WINDOWS_PG_BIN = Path(r"C:\Program Files\PostgreSQL\18\bin")


def fail(message):
    print(f"db_reset: {message}", file=sys.stderr)
    sys.exit(1)


def read_database_url():
    url = os.environ.get("DATABASE_URL", "").strip()
    if url:
        return url
    env_file = REPO_ROOT / ".env"
    if env_file.is_file():
        for line in env_file.read_text(encoding="utf-8-sig").splitlines():
            key, sep, value = line.strip().partition("=")
            if sep and key.strip() == "DATABASE_URL":
                url = value.strip().strip('"').strip("'")
                if url:
                    return url
    fail("DATABASE_URL is not set. Copy .env.example to .env in the repo root, or set the environment variable.")


def find_tool(name):
    found = shutil.which(name)
    if found:
        return found
    for candidate in (WINDOWS_PG_BIN / f"{name}.exe", WINDOWS_PG_BIN / name):
        if candidate.is_file():
            return str(candidate)
    fail(f"{name} not found on PATH or in {WINDOWS_PG_BIN}.")


def run(args, env, what):
    print(f"db_reset: {what}", flush=True)
    result = subprocess.run(args, env=env)
    if result.returncode != 0:
        fail(f"{what} failed with exit code {result.returncode}.")


def main():
    parser = argparse.ArgumentParser(description="Drop and rebuild the ModVault database.")
    parser.add_argument("--with-tests", action="store_true", help="also run database/tests/run_tests.sql")
    args = parser.parse_args()

    url = read_database_url()
    psql = find_tool("psql")
    pg_isready = find_tool("pg_isready")

    env = dict(os.environ, PGCLIENTENCODING="UTF8")
    psql_base = [psql, "-X", "-v", "ON_ERROR_STOP=1", "-d", url]

    run([pg_isready, "-d", url], env, "checking server with pg_isready")
    run(psql_base + ["-c", "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"], env, "dropping and recreating schema public")
    run(psql_base + ["-f", str(DATABASE_DIR / "run_all.sql")], env, "running database/run_all.sql")

    if args.with_tests:
        tests = DATABASE_DIR / "tests" / "run_tests.sql"
        if not tests.is_file():
            fail(f"{tests} does not exist yet.")
        run(psql_base + ["-f", str(tests)], env, "running database/tests/run_tests.sql")

    print("db_reset: done")


if __name__ == "__main__":
    main()
