

SET client_encoding = 'UTF8';

CREATE OR REPLACE VIEW mod_catalog_view AS
SELECT
    m.mod_id,
    m.name          AS mod_name,
    g.name          AS game_name,
    coalesce(u.username, m.nexus_author) AS author_name,
    m.category,
    m.created_at
FROM mods m
INNER JOIN games g ON m.game_id   = g.game_id
LEFT  JOIN users u ON m.author_id = u.user_id;

CREATE OR REPLACE VIEW mod_ratings_view AS
SELECT
    m.mod_id,
    m.name                                    AS mod_name,
    COUNT(r.review_id)                        AS review_count,
    ROUND(AVG(r.rating)::NUMERIC, 2)          AS avg_rating
FROM mods m
LEFT JOIN reviews r ON m.mod_id = r.mod_id
GROUP BY
    m.mod_id,
    m.name;
CREATE OR REPLACE VIEW loadout_summary_view WITH (security_invoker = true) AS
SELECT
    l.loadout_id,
    l.name          AS loadout_name,
    u.username      AS owner_username,
    g.name          AS game_name,
    COUNT(lm.id)    AS mod_count
FROM loadouts l
INNER JOIN users        u  ON l.user_id    = u.user_id
INNER JOIN games        g  ON l.game_id    = g.game_id
LEFT  JOIN loadout_mods lm ON l.loadout_id = lm.loadout_id
GROUP BY
    l.loadout_id,
    l.name,
    u.username,
    g.name;

CREATE OR REPLACE VIEW loadout_health_view WITH (security_invoker = true) AS
SELECT
    l.loadout_id,
    count(*) FILTER (WHERE c.severity = 'error')   AS error_count,
    count(*) FILTER (WHERE c.severity = 'warning') AS warning_count,
    count(*) FILTER (WHERE c.severity = 'info')    AS info_count,
    greatest(0, 100 - 25 * count(*) FILTER (WHERE c.severity = 'error')
                    - 10 * count(*) FILTER (WHERE c.severity = 'warning'))::int AS score,
    CASE
        WHEN count(*) FILTER (WHERE c.severity = 'error')   > 0 THEN 'broken'
        WHEN count(*) FILTER (WHERE c.severity = 'warning') > 0 THEN 'warnings'
        ELSE 'healthy'
    END AS status
FROM loadouts l
LEFT JOIN LATERAL fn_check_loadout_compatibility(l.loadout_id) c ON true
GROUP BY l.loadout_id;

CREATE OR REPLACE VIEW mod_conflict_summary_view AS
SELECT
    m.mod_id,
    m.name::text AS mod_name,
    (SELECT count(*) FILTER (WHERE c.status = 'incompatible')
     FROM   compatibility_matrix c
     JOIN   mod_versions va ON va.version_id = c.version_a_id
     JOIN   mod_versions vb ON vb.version_id = c.version_b_id
     WHERE  m.mod_id IN (va.mod_id, vb.mod_id)) AS incompatible_pairs,
    (SELECT count(*) FILTER (WHERE c.status = 'partial')
     FROM   compatibility_matrix c
     JOIN   mod_versions va ON va.version_id = c.version_a_id
     JOIN   mod_versions vb ON vb.version_id = c.version_b_id
     WHERE  m.mod_id IN (va.mod_id, vb.mod_id)) AS partial_pairs,
    (SELECT count(*)
     FROM   mod_dependencies d
     JOIN   mod_versions dv ON dv.version_id = d.dependent_version_id
     WHERE  d.dep_type = 'conflicts'
       AND  (d.required_mod_id = m.mod_id OR dv.mod_id = m.mod_id)) AS declared_conflicts,
    (SELECT count(DISTINCT dv.mod_id)
     FROM   mod_dependencies d
     JOIN   mod_versions dv ON dv.version_id = d.dependent_version_id
     WHERE  d.required_mod_id = m.mod_id
       AND  d.dep_type <> 'conflicts'
       AND  dv.mod_id <> m.mod_id) AS dependent_mods
FROM mods m;

CREATE MATERIALIZED VIEW mv_game_leaderboard AS
WITH game_mean AS (
    SELECT m.game_id, avg(r.rating)::numeric AS mean_rating
    FROM   reviews r
    JOIN   mods m ON m.mod_id = r.mod_id
    GROUP  BY m.game_id
),
scored AS (
    SELECT m.game_id, m.mod_id, m.name::text AS mod_name, m.rating_count,
           m.rating_avg::numeric AS rating_avg,
           round((5 * coalesce(gm.mean_rating, 0) + m.rating_count * m.rating_avg)
                 / (5 + m.rating_count), 4) AS bayes_score,
           m.download_count
    FROM   mods m
    LEFT   JOIN game_mean gm ON gm.game_id = m.game_id
),
ranked AS (
    SELECT s.*, RANK() OVER (PARTITION BY s.game_id
                             ORDER BY s.bayes_score DESC, s.download_count DESC) AS rank_in_game
    FROM   scored s
)
SELECT game_id, mod_id, mod_name, rating_count, rating_avg, bayes_score, download_count, rank_in_game
FROM   ranked
WHERE  rank_in_game <= 20;

CREATE UNIQUE INDEX uq_mv_game_leaderboard_game_mod
    ON mv_game_leaderboard (game_id, mod_id);
