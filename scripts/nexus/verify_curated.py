"""Verify that all curated YAML files reference valid mods from mods.yaml."""

import yaml
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CURATED_DIR = REPO_ROOT / "data" / "curated"


def main():
    with open(CURATED_DIR / "mods.yaml", encoding="utf-8") as f:
        mod_refs = {m["ref"] for m in yaml.safe_load(f)}

    print(f"Total curated mods: {len(mod_refs)}")

    # Check tags
    with open(CURATED_DIR / "tags.yaml", encoding="utf-8") as f:
        tags = yaml.safe_load(f)
    for t in tags:
        for m in t["mods"]:
            assert m in mod_refs, f"Unknown mod in tag {t.get('slug')}: {m}"

    # Check dependencies
    with open(CURATED_DIR / "dependencies.yaml", encoding="utf-8") as f:
        deps = yaml.safe_load(f)
    for d in deps:
        assert d["mod"] in mod_refs, f"Unknown mod in dep: {d}"
        assert d["requires"] in mod_refs, f"Unknown requires in dep: {d}"

    # Check compat
    with open(CURATED_DIR / "compat.yaml", encoding="utf-8") as f:
        compat = yaml.safe_load(f)
    for c in compat:
        assert c["a"] in mod_refs, f"Unknown mod a in compat: {c}"
        assert c["b"] in mod_refs, f"Unknown mod b in compat: {c}"

    # Check reviews
    with open(CURATED_DIR / "reviews.yaml", encoding="utf-8") as f:
        reviews = yaml.safe_load(f)
    for r in reviews:
        assert r["mod"] in mod_refs, f"Unknown mod in review: {r}"

    # Check loadouts
    with open(CURATED_DIR / "loadouts.yaml", encoding="utf-8") as f:
        loadouts = yaml.safe_load(f)
    for l in loadouts:
        for m in l["mods"]:
            ref = m.split("@")[0]
            assert ref in mod_refs, f"Unknown mod in loadout {l.get('name')}: {m}"
        for m in l.get("disabled", []):
            ref = m.split("@")[0]
            assert ref in mod_refs, f"Unknown disabled mod in loadout {l.get('name')}: {m}"

    print("SUCCESS: Every ref in all curated YAML files resolves to a mod in mods.yaml!")


if __name__ == "__main__":
    main()
