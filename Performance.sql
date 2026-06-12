-- ============================================================
-- performance.sql
-- Football Transfer Market Analytics Platform
-- Track C: Advanced Schema and Analytics Platform
-- Milestone 3: Query Performance Analysis
-- ============================================================
-- This file documents the before/after performance analysis
-- for 2 selected slow queries, plus the stored procedure.
--
-- ============================================================


-- ============================================================
-- SECTION 1: DROP NEW INDEXES (reset to baseline)
-- Removes the indexes added during performance testing so the
-- BEFORE timings can be reproduced on a fresh system.
-- ============================================================
DROP INDEX IF EXISTS idx_transfers_from_club;
DROP INDEX IF EXISTS idx_transfers_to_club;
DROP INDEX IF EXISTS idx_players_nationality;
DROP INDEX IF EXISTS idx_valuations_value;


-- ============================================================
-- SECTION 2: BEFORE INDEXING — EXPLAIN ANALYZE
-- Run these queries to capture baseline execution plans.
-- Both queries perform sequential scans at this stage.
-- ============================================================

-- ── BEFORE | Q09 | Club Profit/Loss (CTE) ───────────────────
-- Observed: Sequential scan on transfers for from_club_id
-- and to_club_id filters. Execution time: ~2.7ms baseline.
EXPLAIN ANALYZE
WITH club_sales AS (
    SELECT from_club_id AS club_id, SUM(fee_euros) AS total_income
    FROM   transfers
    WHERE  fee_euros IS NOT NULL
    AND    from_club_id IS NOT NULL
    GROUP  BY from_club_id
),
club_spend AS (
    SELECT to_club_id AS club_id, SUM(fee_euros) AS total_spend
    FROM   transfers
    WHERE  fee_euros IS NOT NULL
    AND    to_club_id IS NOT NULL
    GROUP  BY to_club_id
)
SELECT
    c.name,
    comp.name,
    ROUND(COALESCE(cs.total_income, 0) / 1e6, 2),
    ROUND(COALESCE(sp.total_spend,  0) / 1e6, 2),
    ROUND((COALESCE(cs.total_income, 0)
         - COALESCE(sp.total_spend,  0)) / 1e6, 2)
FROM   clubs        c
JOIN   competitions comp ON comp.competition_id = c.competition_id
LEFT   JOIN club_sales cs ON cs.club_id = c.club_id
LEFT   JOIN club_spend sp ON sp.club_id = c.club_id
ORDER  BY 5 DESC
LIMIT  10;


-- ── BEFORE | Q15 | Top Nationalities by Peak Value ──────────
-- Observed: Sequential scan on market_valuations (8000 rows)
-- and sequential scan on players filtering by nationality.
-- Execution time: ~10.3ms baseline.
EXPLAIN ANALYZE
SELECT
    p.nationality,
    COUNT(DISTINCT p.player_id),
    ROUND(AVG(peak.max_value) / 1e6, 2),
    ROUND(MAX(peak.max_value) / 1e6, 2)
FROM   players p
JOIN (
    SELECT   player_id, MAX(value_euros) AS max_value
    FROM     market_valuations
    GROUP BY player_id
) peak ON peak.player_id = p.player_id
WHERE  p.nationality IS NOT NULL
GROUP  BY p.nationality
HAVING COUNT(DISTINCT p.player_id) >= 5
ORDER  BY 3 DESC
LIMIT  10;


-- ============================================================
-- SECTION 3: ADD NEW INDEXES
-- These indexes target the unindexed columns identified in
-- the BEFORE query plans above.
-- ============================================================

-- Index on transfers.from_club_id
-- Justification: Q09 and Q18 filter on from_club_id to
-- calculate club sales income. Without this index, PostgreSQL
-- performs a full sequential scan of 9,055 transfer rows.
CREATE INDEX idx_transfers_from_club
    ON transfers(from_club_id);

-- Index on transfers.to_club_id
-- Justification: Q03, Q09, Q10, Q12 all join or filter on
-- to_club_id to aggregate spending per buying club. This is
-- the most frequently queried column in the transfers table.
CREATE INDEX idx_transfers_to_club
    ON transfers(to_club_id);

-- Index on players.nationality
-- Justification: Q15 groups and filters 4,328 player rows by
-- nationality. An index allows the planner to avoid a full
-- sequential scan when filtering by specific nationalities.
CREATE INDEX idx_players_nationality
    ON players(nationality);

-- Index on market_valuations.value_euros
-- Justification: Q07 and Q15 filter on maximum value_euros
-- per player. An index on this column supports range scans
-- and MAX() aggregations more efficiently at larger scale.
CREATE INDEX idx_valuations_value
    ON market_valuations(value_euros);


-- ============================================================
-- SECTION 4: AFTER INDEXING — EXPLAIN ANALYZE
-- Same queries rerun after indexes are created.
-- Note: On this dataset (25,649 rows) the query planner may
-- still choose sequential scans as the data fits in memory.
-- This is expected behaviour — indexes become more impactful
-- as data volume grows beyond available memory buffers.
-- ============================================================

-- ── AFTER | Q09 | Club Profit/Loss (CTE) ────────────────────
-- Observed: Planning time increases slightly as planner now
-- evaluates index paths. Execution time: ~4.3ms.
-- The planner chose sequential scan over index scan because
-- the full transfers table fits in shared memory buffers.
EXPLAIN ANALYZE
WITH club_sales AS (
    SELECT from_club_id AS club_id, SUM(fee_euros) AS total_income
    FROM   transfers
    WHERE  fee_euros IS NOT NULL
    AND    from_club_id IS NOT NULL
    GROUP  BY from_club_id
),
club_spend AS (
    SELECT to_club_id AS club_id, SUM(fee_euros) AS total_spend
    FROM   transfers
    WHERE  fee_euros IS NOT NULL
    AND    to_club_id IS NOT NULL
    GROUP  BY to_club_id
)
SELECT
    c.name,
    comp.name,
    ROUND(COALESCE(cs.total_income, 0) / 1e6, 2),
    ROUND(COALESCE(sp.total_spend,  0) / 1e6, 2),
    ROUND((COALESCE(cs.total_income, 0)
         - COALESCE(sp.total_spend,  0)) / 1e6, 2)
FROM   clubs        c
JOIN   competitions comp ON comp.competition_id = c.competition_id
LEFT   JOIN club_sales cs ON cs.club_id = c.club_id
LEFT   JOIN club_spend sp ON sp.club_id = c.club_id
ORDER  BY 5 DESC
LIMIT  10;


-- ── AFTER | Q15 | Top Nationalities by Peak Value ───────────
-- Observed: Execution time: ~12.9ms.
-- Planner still uses sequential scan on market_valuations
-- as aggregating MAX() across all 8,000 rows is unavoidable.
-- Index on nationality would help more on selective queries
-- (e.g. WHERE nationality = 'Spanish') than GROUP BY.
EXPLAIN ANALYZE
SELECT
    p.nationality,
    COUNT(DISTINCT p.player_id),
    ROUND(AVG(peak.max_value) / 1e6, 2),
    ROUND(MAX(peak.max_value) / 1e6, 2)
FROM   players p
JOIN (
    SELECT   player_id, MAX(value_euros) AS max_value
    FROM     market_valuations
    GROUP BY player_id
) peak ON peak.player_id = p.player_id
WHERE  p.nationality IS NOT NULL
GROUP  BY p.nationality
HAVING COUNT(DISTINCT p.player_id) >= 5
ORDER  BY 3 DESC
LIMIT  10;


