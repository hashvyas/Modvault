"""Draw docs/er-diagram.png from the live database schema.

Usage (from any folder, after python scripts/db_reset.py):
    python scripts/er_diagram.py

Tables, columns, primary keys and foreign keys are read from the PostgreSQL
catalog, so the picture always matches the schema that run_all.sql built.
Only the box positions are fixed (LAYOUT below). Needs matplotlib.
"""

import os
import subprocess
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from db_reset import REPO_ROOT, fail, find_tool, read_database_url

OUTPUT = REPO_ROOT / "docs" / "er-diagram.png"

# GitHub dark palette.
BG, BOX, HEADER, BORDER = "#0d1117", "#161b22", "#21262d", "#30363d"
TEXT, MUTED, PK, FK, EDGE = "#e6edf3", "#8b949e", "#d29922", "#58a6ff", "#6e7681"

# (column, row) grid slot per table. Columns are 0..3 left to right, rows top to bottom.
LAYOUT = {
    "users": (0, 0), "games": (1, 0), "tags": (3, 0),
    "loadouts": (0, 1), "mods": (1, 1), "mod_tags": (3, 1),
    "loadout_mods": (0, 2), "mod_versions": (2, 0), "reviews": (2, 1),
    "audit_log": (0, 3), "compatibility_matrix": (1, 3), "mod_dependencies": (2, 3),
}
COL_W, BOX_W, ROW_H, HEAD_H, GAP = 5.4, 4.6, 0.36, 0.5, 0.9

SHORT_TYPES = {
    "character varying": "varchar", "timestamp with time zone": "timestamptz",
    "character": "char", "integer": "int", "boolean": "bool", "smallint": "int2",
}

COLUMNS_SQL = """
SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull,
       EXISTS (SELECT 1 FROM pg_constraint p
               WHERE p.conrelid = c.oid AND p.contype = 'p' AND a.attnum = ANY (p.conkey)),
       coalesce((SELECT f.confrelid::regclass::text FROM pg_constraint f
                 WHERE f.conrelid = c.oid AND f.contype = 'f' AND f.conkey = ARRAY[a.attnum]), '')
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
JOIN   pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE  n.nspname = 'public' AND c.relkind = 'r'
ORDER  BY c.relname, a.attnum
"""


def short_type(t):
    for long, short in SHORT_TYPES.items():
        if t == long or t.startswith(long + "("):
            return short + t[len(long):]
    return t


def read_schema():
    psql = find_tool("psql")
    env = dict(os.environ, PGCLIENTENCODING="UTF8")
    result = subprocess.run([psql, "-X", "-At", "-F", "\t", "-d", read_database_url(), "-c", COLUMNS_SQL],
                            env=env, capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        fail(f"reading the schema failed: {result.stderr.strip()}")
    tables = {}
    for line in result.stdout.splitlines():
        table, col, typ, notnull, is_pk, fk = line.split("\t")
        tables.setdefault(table, []).append(
            {"name": col, "type": short_type(typ), "notnull": notnull == "t", "pk": is_pk == "t", "fk": fk})
    missing = set(tables) ^ set(LAYOUT)
    if missing:
        fail(f"LAYOUT and the database disagree on these tables: {sorted(missing)}")
    return tables


def box_geometry(tables):
    """Top-left corner, width, height of each table box. Rows stack by the tallest box above."""
    heights = {t: HEAD_H + ROW_H * len(cols) + 0.15 for t, cols in tables.items()}
    geo, col_y = {}, {}
    for table, (col, row) in sorted(LAYOUT.items(), key=lambda kv: (kv[1][1], kv[1][0])):
        y = col_y.get(col, 0.0)
        geo[table] = (col * COL_W, -y, BOX_W, heights[table])
        col_y[col] = y + heights[table] + GAP
    return geo


def draw(tables):
    geo = box_geometry(tables)
    width = max(x + w for x, y, w, h in geo.values()) + 0.4
    depth = max(h - y for x, y, w, h in geo.values()) + 1.4
    fig, ax = plt.subplots(figsize=(width * 0.82, depth * 0.82), dpi=150)
    fig.patch.set_facecolor(BG)
    ax.set_facecolor(BG)
    ax.set_xlim(-1.3, width)  # room for the same-column arrows that loop out on the left
    ax.set_ylim(-depth + 0.4, 1.4)
    ax.axis("off")

    ax.text(-0.2, 1.05, "ModVault schema", color=TEXT, fontsize=18, fontweight="bold", va="center")
    legend = [(f"{len(tables)} tables", MUTED, 1.6), ("PK primary key", PK, 2.4), ("FK foreign key", FK, 2.4),
              ("PF primary + foreign key", FK, 3.8), ("* NOT NULL", MUTED, 1.9),
              ("arrow: referencing column -> referenced table", MUTED, 0)]
    lx = -0.2
    for label, color, step in legend:
        ax.text(lx, 0.62, label, color=color, fontsize=10, va="center")
        lx += step

    row_y = {}
    for table, cols in tables.items():
        x, y, w, h = geo[table]
        ax.add_patch(FancyBboxPatch((x, y - h), w, h, boxstyle="round,pad=0,rounding_size=0.12",
                                    facecolor=BOX, edgecolor=BORDER, linewidth=1.2, zorder=2))
        ax.add_patch(FancyBboxPatch((x, y - HEAD_H), w, HEAD_H, boxstyle="round,pad=0,rounding_size=0.12",
                                    facecolor=HEADER, edgecolor=BORDER, linewidth=1.2, zorder=3))
        ax.text(x + 0.18, y - HEAD_H / 2, table, color=TEXT, fontsize=11, fontweight="bold",
                va="center", zorder=4)
        for i, c in enumerate(cols):
            cy = y - HEAD_H - ROW_H * (i + 0.5) - 0.05
            row_y[(table, c["name"])] = cy
            # PF: part of the primary key and a foreign key (mod_tags).
            tag = ("PF" if c["fk"] else "PK") if c["pk"] else ("FK" if c["fk"] else "")
            ax.text(x + 0.15, cy, tag, color=FK if c["fk"] else PK, fontsize=7.5, fontweight="bold",
                    va="center", zorder=4, family="monospace")
            ax.text(x + 0.62, cy, c["name"] + ("*" if c["notnull"] and not c["pk"] else ""),
                    color=TEXT, fontsize=8.5, va="center", zorder=4, family="monospace")
            ax.text(x + w - 0.15, cy, c["type"], color=MUTED, fontsize=7.5, va="center", ha="right",
                    zorder=4, family="monospace")

    for table, cols in tables.items():
        for c in cols:
            if not c["fk"]:
                continue
            sx, sy, sw, _ = geo[table]
            tx, ty, tw, _ = geo[c["fk"]]
            start_y = row_y[(table, c["name"])]
            end_y = ty - HEAD_H / 2
            if tx > sx + sw:            # target to the right
                start, end, rad = (sx + sw, start_y), (tx, end_y), 0.15
            elif tx + tw < sx:          # target to the left
                start, end, rad = (sx, start_y), (tx + tw, end_y), 0.15
            else:                       # same column: loop out on the left side, bulging ~0.8 units
                bulge = 0.8 / max(abs(start_y - end_y), 0.1)
                start, end, rad = (sx, start_y), (tx, end_y), -bulge if ty > sy else bulge
            ax.add_patch(FancyArrowPatch(start, end, connectionstyle=f"arc3,rad={rad}", arrowstyle="-|>",
                                         mutation_scale=11, color=EDGE, linewidth=1.0, alpha=0.9, zorder=1))

    OUTPUT.parent.mkdir(exist_ok=True)
    fig.savefig(OUTPUT, facecolor=BG, bbox_inches="tight", pad_inches=0.3)
    print(f"er_diagram: wrote {OUTPUT.relative_to(REPO_ROOT)} "
          f"({len(tables)} tables, {sum(len(c) for c in tables.values())} columns, "
          f"{sum(1 for cols in tables.values() for c in cols if c['fk'])} foreign keys)")


if __name__ == "__main__":
    draw(read_schema())
