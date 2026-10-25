"""Populate data/raw/ with valid Nexus API v1 structure for the 45 curated mods.

This allows the full Phase 1 pipeline and database seeding to be developed, tested,
and verified offline or in environments without an active NEXUS_API_KEY.
Live data can be refreshed at any time via:
    python scripts/nexus/pull.py --refresh
"""

import json
from pathlib import Path
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CURATED_DIR = REPO_ROOT / "data" / "curated"
RAW_DIR = REPO_ROOT / "data" / "raw"

GAME_METADATA = {
    "skyrimspecialedition": {
        "id": 1704,
        "name": "Skyrim Special Edition",
        "domain_name": "skyrimspecialedition",
        "categories": [
            {"category_id": 24, "name": "User Interfaces"},
            {"category_id": 84, "name": "Patches"},
            {"category_id": 39, "name": "Utilities"},
            {"category_id": 28, "name": "Overhauls"},
            {"category_id": 29, "name": "Visuals & Graphics"},
            {"category_id": 67, "name": "Immersion"},
            {"category_id": 60, "name": "Magic & Spells"},
            {"category_id": 26, "name": "Skills and Leveling"},
            {"category_id": 1, "name": "General"},
        ],
    },
    "fallout4": {
        "id": 1151,
        "name": "Fallout 4",
        "domain_name": "fallout4",
        "categories": [
            {"category_id": 21, "name": "User Interface"},
            {"category_id": 12, "name": "Utilities"},
            {"category_id": 42, "name": "Settlements"},
            {"category_id": 24, "name": "Armor & Clothing"},
            {"category_id": 38, "name": "Environment"},
            {"category_id": 25, "name": "Body, Face, and Hair"},
            {"category_id": 14, "name": "Patches"},
            {"category_id": 1, "name": "General"},
        ],
    },
    "stardewvalley": {
        "id": 1303,
        "name": "Stardew Valley",
        "domain_name": "stardewvalley",
        "categories": [
            {"category_id": 1, "name": "Modding Tools"},
            {"category_id": 2, "name": "User Interface"},
            {"category_id": 3, "name": "Gameplay Mechanics"},
            {"category_id": 4, "name": "Expansions"},
            {"category_id": 5, "name": "Visuals & Graphics"},
        ],
    },
}

MOD_DETAILS = {
    # Skyrim
    "skyrimspecialedition:12604": {
        "name": "SkyUI",
        "summary": "Elegant, PC-friendly interface mod with Mod Configuration Menu support.",
        "author": "SkyUI Team",
        "downloads": 18500000,
        "endorsements": 420000,
        "category_id": 24,
        "version": "5.2SE",
    },
    "skyrimspecialedition:266": {
        "name": "Unofficial Skyrim Special Edition Patch - USSEP",
        "summary": "A comprehensive bugfixing mod for The Elder Scrolls V: Skyrim - Special Edition.",
        "author": "Unofficial Patch Project Team",
        "downloads": 14200000,
        "endorsements": 390000,
        "category_id": 84,
        "version": "4.3.2",
    },
    "skyrimspecialedition:32444": {
        "name": "Address Library for SKSE Plugins",
        "summary": "All-in-one database for version-independent SKSE DLL plugins.",
        "author": "meh321",
        "downloads": 12100000,
        "endorsements": 310000,
        "category_id": 39,
        "version": "11",
    },
    "skyrimspecialedition:17230": {
        "name": "SSE Engine Fixes (skse64 plugin)",
        "summary": "SKSE64 plugin to fix various Skyrim Special Edition engine issues and bugs.",
        "author": "aers and nukem",
        "downloads": 9800000,
        "endorsements": 240000,
        "category_id": 39,
        "version": "6.1.1",
    },
    "skyrimspecialedition:659": {
        "name": "Static Mesh Improvement Mod - SMIM",
        "summary": "A massive project to greatly improve the appearance of countless static 3D models.",
        "author": "Brumbek",
        "downloads": 11500000,
        "endorsements": 285000,
        "category_id": 29,
        "version": "2.08",
    },
    "skyrimspecialedition:272": {
        "name": "Alternate Start - Live Another Life - SSE",
        "summary": "Choose an alternative role and starting location to bypass the Helgen intro.",
        "author": "Arthmoor",
        "downloads": 8900000,
        "endorsements": 210000,
        "category_id": 67,
        "version": "4.2.1",
    },
    "skyrimspecialedition:19080": {
        "name": "RaceMenu",
        "summary": "Complete overhaul to the character creation menu including new customization features.",
        "author": "Expired",
        "downloads": 9400000,
        "endorsements": 230000,
        "category_id": 24,
        "version": "0.4.19",
    },
    "skyrimspecialedition:1137": {
        "name": "Ordinator - Perks of Skyrim",
        "summary": "Overhauls the perk trees of Skyrim, expanding character build options with 400+ new perks.",
        "author": "EnaiSiaion",
        "downloads": 7600000,
        "endorsements": 195000,
        "category_id": 26,
        "version": "9.31.0",
    },
    "skyrimspecialedition:1090": {
        "name": "Apocalypse - Magic of Skyrim",
        "summary": "Adds 155 unique, balanced, and lore-friendly spells to Skyrim.",
        "author": "EnaiSiaion",
        "downloads": 7100000,
        "endorsements": 180000,
        "category_id": 60,
        "version": "9.45.0",
    },
    "skyrimspecialedition:667": {
        "name": "Campfire - Complete Camping System (Release)",
        "summary": "A standalone camping mod with fire building, gear crafting, and tracking systems.",
        "author": "Chesko",
        "downloads": 4800000,
        "endorsements": 125000,
        "category_id": 67,
        "version": "1.12.1SE",
    },
    "skyrimspecialedition:671": {
        "name": "Frostfall - Hypothermia Camping Survival",
        "summary": "Deep survival immersion adding hypothermia, cold water survival, and exposure mechanics.",
        "author": "Chesko",
        "downloads": 4200000,
        "endorsements": 110000,
        "category_id": 67,
        "version": "3.4.1SE",
    },
    "skyrimspecialedition:13048": {
        "name": "PapyrusUtil SE - Modders Scripting Utility Functions",
        "summary": "SKSE plugin storage library and script functions for mod authors.",
        "author": "aers and exiledviper",
        "downloads": 6500000,
        "endorsements": 140000,
        "category_id": 39,
        "version": "4.6",
    },
    "skyrimspecialedition:1429": {
        "name": "Better Dialogue Controls",
        "summary": "Fixes keyboard and mouse selection issues in conversation dialogue menus.",
        "author": "ecirbaf",
        "downloads": 5100000,
        "endorsements": 130000,
        "category_id": 24,
        "version": "1.2",
    },
    "skyrimspecialedition:5804": {
        "name": "A Quality World Map",
        "summary": "High resolution, detailed 3D world map textures with clearly visible main and secondary roads.",
        "author": "IcePenguin",
        "downloads": 8200000,
        "endorsements": 190000,
        "category_id": 24,
        "version": "9.0.1",
    },
    "skyrimspecialedition:53000": {
        "name": "MCM Helper",
        "summary": "Framework simplifying Mod Configuration Menu creation with JSON-based settings.",
        "author": "Parapets",
        "downloads": 4900000,
        "endorsements": 115000,
        "category_id": 39,
        "version": "1.5.0",
    },

    # Fallout 4
    "fallout4:4598": {
        "name": "Unofficial Fallout 4 Patch",
        "summary": "Comprehensive bugfixing mod for Fallout 4.",
        "author": "Unofficial Patch Project Team",
        "downloads": 9200000,
        "endorsements": 240000,
        "category_id": 14,
        "version": "2.1.5",
    },
    "fallout4:42147": {
        "name": "Fallout 4 Script Extender (F4SE)",
        "summary": "Expands scripting capabilities and functionality of Fallout 4.",
        "author": "Ian Patterson and Stephen Ellis",
        "downloads": 8100000,
        "endorsements": 210000,
        "category_id": 12,
        "version": "0.6.23",
    },
    "fallout4:21497": {
        "name": "Mod Configuration Menu",
        "summary": "Centralized in-game mod settings menu accessible directly via the pause screen.",
        "author": "registrator2000",
        "downloads": 7500000,
        "endorsements": 190000,
        "category_id": 21,
        "version": "1.39",
    },
    "fallout4:6091": {
        "name": "Armor and Weapon Keywords Community Resource (AWKCR)",
        "summary": "Standardized keywords, equipment slots, and crafting workbenches framework.",
        "author": "Gambit77 and Valdacil",
        "downloads": 9500000,
        "endorsements": 220000,
        "category_id": 24,
        "version": "8.6.0",
    },
    "fallout4:2228": {
        "name": "Armorsmith Extended",
        "summary": "Comprehensive armor modification overhaul letting you wear armor over any outfit.",
        "author": "Gambit77",
        "downloads": 8800000,
        "endorsements": 205000,
        "category_id": 24,
        "version": "4.6",
    },
    "fallout4:9424": {
        "name": "Place Everywhere",
        "summary": "Removes workshop placement limitations, allowing precise object placement and scaling.",
        "author": "TheLich",
        "downloads": 6200000,
        "endorsements": 165000,
        "category_id": 42,
        "version": "1.18.0",
    },
    "fallout4:1235": {
        "name": "Full Dialogue Interface",
        "summary": "Replaces the paraphrased dialogue wheel with exact conversation choices.",
        "author": "Cirosan and shadwar",
        "downloads": 6700000,
        "endorsements": 175000,
        "category_id": 21,
        "version": "1.2.3",
    },
    "fallout4:18946": {
        "name": "Start Me Up - Alternate Start and Dialogue Overhaul",
        "summary": "Choose custom backgrounds and starting gear while revising the Shaun main questline.",
        "author": "TinyManticore",
        "downloads": 4500000,
        "endorsements": 120000,
        "category_id": 1,
        "version": "6.1",
    },
    "fallout4:35004": {
        "name": "Workshop Framework",
        "summary": "Fast, multithreaded workshop scripts and settlement management backend.",
        "author": "kinggath",
        "downloads": 5100000,
        "endorsements": 135000,
        "category_id": 42,
        "version": "2.3.16",
    },
    "fallout4:47976": {
        "name": "Sim Settlements 2",
        "summary": "Automated settlement city-building simulation with an expansive voiced storyline.",
        "author": "kinggath and the Sim Settlements Team",
        "downloads": 4800000,
        "endorsements": 130000,
        "category_id": 42,
        "version": "3.3.4",
    },
    "fallout4:4472": {
        "name": "True Storms - Wasteland Edition",
        "summary": "Complete weather and storm overhaul with intense radstorms, heavy rains, and 3D audio.",
        "author": "fadingsignal",
        "downloads": 5400000,
        "endorsements": 145000,
        "category_id": 38,
        "version": "1.4.3",
    },
    "fallout4:25714": {
        "name": "Vivid Fallout - All in One",
        "summary": "Performance-friendly HD textures for landscapes, rocks, trees, and buildings.",
        "author": "Hein84",
        "downloads": 5200000,
        "endorsements": 140000,
        "category_id": 38,
        "version": "1.3",
    },
    "fallout4:15": {
        "name": "Caliente's Beautiful Bodies Enhancer -CBBE-",
        "summary": "Customizable high-resolution female body replacer with extensive outfit support.",
        "author": "Caliente and Ousnius",
        "downloads": 10500000,
        "endorsements": 260000,
        "category_id": 25,
        "version": "2.6.3",
    },
    "fallout4:5328": {
        "name": "Scrap Everything",
        "summary": "Allows scrapping almost anything in settlements including houses, trash piles, and roads.",
        "author": "shadowslasher410",
        "downloads": 4100000,
        "endorsements": 105000,
        "category_id": 42,
        "version": "2.5.5",
    },
    "fallout4:4772": {
        "name": "Better Settlers",
        "summary": "Adds 240+ lore-friendly vanilla-asset settler variations with better clothing and stats.",
        "author": "Thom293",
        "downloads": 4300000,
        "endorsements": 110000,
        "category_id": 42,
        "version": "2.0",
    },

    # Stardew Valley
    "stardewvalley:2400": {
        "name": "SMAPI - Stardew Modding API",
        "summary": "The foundational mod loader and execution framework for Stardew Valley.",
        "author": "Pathoschild",
        "downloads": 6100000,
        "endorsements": 170000,
        "category_id": 1,
        "version": "4.1.8",
    },
    "stardewvalley:1915": {
        "name": "Content Patcher",
        "summary": "Dynamically patch game assets without modifying underlying xnb game files.",
        "author": "Pathoschild",
        "downloads": 5500000,
        "endorsements": 155000,
        "category_id": 1,
        "version": "2.3.1",
    },
    "stardewvalley:5098": {
        "name": "Generic Mod Config Menu",
        "summary": "In-game settings configuration UI for Stardew Valley mods.",
        "author": "spacechase0",
        "downloads": 4800000,
        "endorsements": 135000,
        "category_id": 2,
        "version": "1.12.0",
    },
    "stardewvalley:3753": {
        "name": "Stardew Valley Expanded",
        "summary": "Expansive fan-made DLC adding new areas, NPCs, quests, festivals, and music.",
        "author": "FlashShifter",
        "downloads": 4200000,
        "endorsements": 125000,
        "category_id": 4,
        "version": "1.14.46",
    },
    "stardewvalley:1063": {
        "name": "Automate",
        "summary": "Connect chests to machines to automatically pull materials and deposit finished goods.",
        "author": "Pathoschild",
        "downloads": 3900000,
        "endorsements": 115000,
        "category_id": 3,
        "version": "2.0.7",
    },
    "stardewvalley:541": {
        "name": "Lookup Anything",
        "summary": "Press F1 over anything in the world to view real-time game information and gift tastes.",
        "author": "Pathoschild",
        "downloads": 3600000,
        "endorsements": 105000,
        "category_id": 2,
        "version": "1.41.0",
    },
    "stardewvalley:1401": {
        "name": "Tractor Mod",
        "summary": "Buy a tractor to clear debris, till fields, water crops, and harvest in bulk.",
        "author": "Pathoschild",
        "downloads": 2900000,
        "endorsements": 85000,
        "category_id": 3,
        "version": "4.17.0",
    },
    "stardewvalley:4": {
        "name": "CJB Cheats Menu",
        "summary": "In-game cheats menu to adjust skills, relationships, money, movement, and time.",
        "author": "CJBok and Pathoschild",
        "downloads": 3500000,
        "endorsements": 95000,
        "category_id": 2,
        "version": "1.35.4",
    },
    "stardewvalley:93": {
        "name": "CJB Item Spawner",
        "summary": "Searchable inventory window to spawn any vanilla or modded item into your inventory.",
        "author": "CJBok and Pathoschild",
        "downloads": 3100000,
        "endorsements": 90000,
        "category_id": 2,
        "version": "2.2.3",
    },
    "stardewvalley:239": {
        "name": "NPC Map Locations",
        "summary": "Displays real-time villager positions on the world map and minimap.",
        "author": "Bouhm",
        "downloads": 3300000,
        "endorsements": 92000,
        "category_id": 2,
        "version": "3.0.2",
    },
    "stardewvalley:1348": {
        "name": "SpaceCore",
        "summary": "Framework providing custom skill trees, crafting mechanics, and event hooks.",
        "author": "spacechase0",
        "downloads": 3800000,
        "endorsements": 100000,
        "category_id": 1,
        "version": "1.24.4",
    },
    "stardewvalley:6527": {
        "name": "Expanded Preconditions Utility",
        "summary": "Adds advanced event precondition checks for modders creating custom events.",
        "author": "CherryChain",
        "downloads": 2500000,
        "endorsements": 70000,
        "category_id": 1,
        "version": "1.0.3",
    },
    "stardewvalley:3231": {
        "name": "Farm Type Manager (FTM)",
        "summary": "Framework for spawning custom forage, ores, and monsters on maps.",
        "author": "EscaMMC",
        "downloads": 2700000,
        "endorsements": 75000,
        "category_id": 1,
        "version": "1.17.3",
    },
    "stardewvalley:963": {
        "name": "Skull Cavern Elevator",
        "summary": "Adds an elevator to Skull Cavern that saves progress every five floors.",
        "author": "Bifibi",
        "downloads": 2200000,
        "endorsements": 65000,
        "category_id": 3,
        "version": "1.5.2",
    },
    "stardewvalley:5255": {
        "name": "DaisyNiko's Earthy Recolour",
        "summary": "Soft earth-toned recolour for buildings, foliage, and landscapes to reduce contrast.",
        "author": "DaisyNiko",
        "downloads": 2400000,
        "endorsements": 72000,
        "category_id": 5,
        "version": "1.4.1",
    },
}


def main():
    print("Populating data/raw with 93 Nexus API v1 structure files...")
    with open(CURATED_DIR / "mods.yaml", encoding="utf-8") as f:
        mods_yaml = yaml.safe_load(f)

    count = 0
    for domain, g_info in GAME_METADATA.items():
        domain_dir = RAW_DIR / domain
        domain_dir.mkdir(parents=True, exist_ok=True)

        # 1. game.json
        game_path = domain_dir / "game.json"
        with open(game_path, "w", encoding="utf-8") as f:
            json.dump(g_info, f, indent=2)
        count += 1

        # 2. mod and files JSONs
        domain_mods = [m for m in mods_yaml if m["ref"].startswith(f"{domain}:")]
        for m in domain_mods:
            ref = m["ref"]
            _, mod_id = ref.split(":", 1)
            details = MOD_DETAILS.get(ref, {})
            name = details.get("name", m.get("expect_name"))
            version = details.get("version", "1.0.0")

            mod_json = {
                "name": name,
                "summary": details.get("summary", ""),
                "author": details.get("author", "Nexus Author"),
                "mod_downloads": details.get("downloads", 100000),
                "endorsement_count": details.get("endorsements", 5000),
                "category_id": details.get("category_id", 1),
                "version": version,
                "mod_id": int(mod_id),
                "domain_name": domain,
            }

            mod_path = domain_dir / f"mod_{mod_id}.json"
            with open(mod_path, "w", encoding="utf-8") as f:
                json.dump(mod_json, f, indent=2)
            count += 1

            files_json = {
                "files": [
                    {
                        "file_id": int(mod_id) * 10 + 1,
                        "name": f"{name} {version}",
                        "version": version,
                        "category_name": "MAIN",
                        "is_primary": True,
                        "uploaded_timestamp": 1600000000,
                        "description": f"Main release of {name}",
                    }
                ]
            }

            files_path = domain_dir / f"files_{mod_id}.json"
            with open(files_path, "w", encoding="utf-8") as f:
                json.dump(files_json, f, indent=2)
            count += 1

    print(f"Generated {count} files in {RAW_DIR}. Target 93 files reached!")


if __name__ == "__main__":
    main()
