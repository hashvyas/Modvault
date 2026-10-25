"""Nexus Mods API pull script.

Caches games, mod metadata, and files list from the Nexus Mods v1 API
into data/raw/{domain}/ to generate seed.sql.

Usage:
    python scripts/nexus/pull.py [--games skyrimspecialedition fallout4 stardewvalley] [--refresh]
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path
import requests
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CURATED_DIR = REPO_ROOT / "data" / "curated"
RAW_DIR = REPO_ROOT / "data" / "raw"
BASE_URL = "https://api.nexusmods.com"


def load_env():
    """Load NEXUS_API_KEY from os.environ or .env file."""
    api_key = os.environ.get("NEXUS_API_KEY", "").strip()
    if api_key:
        return api_key
    env_file = REPO_ROOT / ".env"
    if env_file.is_file():
        for line in env_file.read_text(encoding="utf-8-sig").splitlines():
            key, sep, val = line.strip().partition("=")
            if sep and key.strip() == "NEXUS_API_KEY":
                val = val.strip().strip('"').strip("'")
                if val:
                    return val
    return ""


def make_request(session, url, headers, max_retries=3):
    """Perform a GET request with retry on 429/5xx and hourly limit checks."""
    if not headers.get("apikey"):
        print("ERROR: NEXUS_API_KEY is not set. Please set it in .env or your environment to make API requests.", file=sys.stderr)
        sys.exit(1)
    for attempt in range(1, max_retries + 1):
        try:
            resp = session.get(url, headers=headers, timeout=30)
            # Check rate limit
            hourly_remaining = resp.headers.get("X-RL-Hourly-Remaining")
            if hourly_remaining is not None:
                try:
                    rem = int(hourly_remaining)
                    if rem < 20:
                        print(f"ERROR: X-RL-Hourly-Remaining ({rem}) is below 20. Stopping.", file=sys.stderr)
                        sys.exit(1)
                except ValueError:
                    pass

            if resp.status_code == 429 or 500 <= resp.status_code < 600:
                if attempt == max_retries:
                    resp.raise_for_status()
                sleep_time = attempt * 2
                print(f"Received HTTP {resp.status_code} for {url}. Backing off {sleep_time}s (attempt {attempt}/{max_retries})...")
                time.sleep(sleep_time)
                continue

            resp.raise_for_status()
            time.sleep(1.0)  # Politeness interval between API calls
            return resp.json()
        except requests.RequestException as e:
            if attempt == max_retries:
                raise
            sleep_time = attempt * 2
            print(f"Request error: {e}. Backing off {sleep_time}s (attempt {attempt}/{max_retries})...")
            time.sleep(sleep_time)

    raise RuntimeError(f"Failed to fetch {url} after {max_retries} attempts.")


def main():
    parser = argparse.ArgumentParser(description="Pull mod data from Nexus Mods API")
    parser.add_argument("--games", nargs="+", help="Game domains to pull (e.g. skyrimspecialedition fallout4 stardewvalley)")
    parser.add_argument("--refresh", action="store_true", help="Force refresh of already cached files")
    args = parser.parse_args()

    api_key = load_env()
    headers = {
        "apikey": api_key,
        "Application-Name": "modvault",
        "Application-Version": "0.1.0",
        "Accept": "application/json",
    }

    # Load games.yaml
    games_file = CURATED_DIR / "games.yaml"
    if not games_file.is_file():
        print(f"ERROR: {games_file} does not exist.", file=sys.stderr)
        sys.exit(1)

    with open(games_file, "r", encoding="utf-8") as f:
        all_games = yaml.safe_load(f)

    target_domains = set(args.games) if args.games else {g["domain"] for g in all_games}

    # Load mods.yaml
    mods_file = CURATED_DIR / "mods.yaml"
    if not mods_file.is_file():
        print(f"ERROR: {mods_file} does not exist.", file=sys.stderr)
        sys.exit(1)

    with open(mods_file, "r", encoding="utf-8") as f:
        all_mods = yaml.safe_load(f)

    session = requests.Session()
    total_cached = 0

    for game in all_games:
        domain = game["domain"]
        if domain not in target_domains:
            continue

        game_dir = RAW_DIR / domain
        game_dir.mkdir(parents=True, exist_ok=True)

        # 1. Game metadata
        game_json_file = game_dir / "game.json"
        if args.refresh or not game_json_file.is_file():
            print(f"Fetching game metadata for {domain}...")
            url = f"{BASE_URL}/v1/games/{domain}.json"
            data = make_request(session, url, headers)
            with open(game_json_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            print(f"Saved {game_json_file}")
        else:
            print(f"Using cached {game_json_file}")
        total_cached += 1

        # 2. Mods for this game
        game_mods = [m for m in all_mods if m["ref"].startswith(f"{domain}:")]
        print(f"Processing {len(game_mods)} mods for {domain}...")

        for m in game_mods:
            _, mod_id = m["ref"].split(":", 1)
            expect_name = m.get("expect_name", "")

            # Mod info
            mod_file = game_dir / f"mod_{mod_id}.json"
            if args.refresh or not mod_file.is_file():
                print(f"  Fetching mod {mod_id}...")
                url = f"{BASE_URL}/v1/games/{domain}/mods/{mod_id}.json"
                mod_data = make_request(session, url, headers)
                with open(mod_file, "w", encoding="utf-8") as f:
                    json.dump(mod_data, f, indent=2, ensure_ascii=False)
            else:
                with open(mod_file, "r", encoding="utf-8") as f:
                    mod_data = json.load(f)
            total_cached += 1

            # Validate expect_name
            actual_name = mod_data.get("name", "")
            if expect_name and expect_name.lower() not in actual_name.lower():
                print(
                    f"ERROR: Mod name mismatch for {domain}:{mod_id}!\n"
                    f"  Expected '{expect_name}' in actual name '{actual_name}'.",
                    file=sys.stderr,
                )
                sys.exit(1)

            # Files list
            files_file = game_dir / f"files_{mod_id}.json"
            if args.refresh or not files_file.is_file():
                print(f"  Fetching files for mod {mod_id}...")
                url = f"{BASE_URL}/v1/games/{domain}/mods/{mod_id}/files.json"
                files_data = make_request(session, url, headers)
                with open(files_file, "w", encoding="utf-8") as f:
                    json.dump(files_data, f, indent=2, ensure_ascii=False)
            total_cached += 1

    print(f"\nPull completed successfully. {total_cached} files verified.")


if __name__ == "__main__":
    main()
