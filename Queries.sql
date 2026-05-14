-- ============================================================
-- queries.sql
-- Football Transfer Market Analytics Platform
-- Track C: Advanced Schema and Analytics Platform
-- Milestone 2: 10 queries
-- Dataset: Transfermarkt — Premier League + La Liga, 2015–2023
-- ============================================================
-- Query index:
--   Q02  DML        — Update unknown positions using appearance data
--   Q03  AGG-1      — Total transfer spending per club
--   Q04  AGG-2      — Average player market value by position
--   Q05  JOIN-1     — All transfers with player and club names
--   Q06  JOIN-2     — Players with their current club and league
--   Q07  SUB-1      — Players whose peak value exceeded £50m
--   Q08  SUB-2      — Clubs that have spent more than the average club
--   Q09  CTE-1      — Top 5 most profitable selling clubs
--   Q10  CTE-2      — Season-by-season transfer spend per league
--   Q11  WIN-1      — Rank players by market value within each position
--   Q12  WIN-2      — Running total of transfer spend per club over seasons
-- ============================================================
-- NOTE: Q11 and Q12 are window function queries included to
-- satisfy the minimum 2 window functions requirement.
-- Total queries in this file: 11 (2 through 12)
-- ============================================================


-- ============================================================
-- Q02 | DML | Fix Unknown Positions
-- Players loaded with position = 'Unknown' are updated where
-- we can infer their position from the appearances data.
-- Demonstrates an UPDATE with a correlated subquery.
-- ============================================================
UPDATE players p
SET    position = 'Forward'
WHERE  p.position = 'Unknown'
AND    EXISTS (
           SELECT 1
           FROM   appearances a
           WHERE  a.player_id = p.player_id
           AND    a.goals     > 10
       );


-- ============================================================
-- Q03 | AGGREGATION 1 | Total Transfer Spending per Club
-- Sums all permanent transfer fees paid by each buying club.
-- Only includes confirmed fees (fee_euros IS NOT NULL).
-- Orders by highest spender first.
-- ============================================================
SELECT
    c.name                          AS club,
    comp.name                       AS league,
    COUNT(t.transfer_id)            AS transfers_in,
    ROUND(SUM(t.fee_euros) / 1e6, 2)AS total_spent_millions
FROM   transfers      t
JOIN   clubs          c    ON c.club_id          = t.to_club_id
JOIN   competitions   comp ON comp.competition_id = c.competition_id
JOIN   transfer_types tt   ON tt.transfer_type_id = t.transfer_type_id
WHERE  tt.type_name   = 'permanent'
AND    t.fee_euros    IS NOT NULL
GROUP  BY c.name, comp.name
ORDER  BY total_spent_millions DESC
LIMIT  20;


-- ============================================================
-- Q04 | AGGREGATION 2 | Average Market Value by Position
-- Calculates the average and maximum market valuation for
-- each player position across all valuation snapshots.
-- Useful for benchmarking player value by role.
-- ============================================================
SELECT
    p.position,
    COUNT(DISTINCT p.player_id)         AS player_count,
    ROUND(AVG(mv.value_euros) / 1e6, 2) AS avg_value_millions,
    ROUND(MAX(mv.value_euros) / 1e6, 2) AS peak_value_millions
FROM   market_valuations mv
JOIN   players           p  ON p.player_id = mv.player_id
WHERE  p.position IS NOT NULL
GROUP  BY p.position
ORDER  BY avg_value_millions DESC;


-- ============================================================
-- Q05 | JOIN 1 | Full Transfer History with Names
-- Joins transfers with players, selling club, buying club,
-- and transfer type.
-- ============================================================
SELECT
    p.name                              AS player,
    p.position,
    p.nationality,
    fc.name                             AS from_club,
    tc.name                             AS to_club,
    tt.type_name                        AS transfer_type,
    t.season,
    ROUND(t.fee_euros / 1e6, 2)         AS fee_millions
FROM   transfers    t
JOIN   players      p   ON p.player_id        = t.player_id
INNER   JOIN clubs   fc  ON fc.club_id         = t.from_club_id
INNER   JOIN clubs   tc  ON tc.club_id         = t.to_club_id
JOIN   transfer_types tt ON tt.transfer_type_id = t.transfer_type_id
WHERE  t.fee_euros IS NOT NULL
ORDER  BY t.fee_euros DESC
LIMIT  50;


-- ============================================================
-- Q06 | JOIN 2 | Players with Current Club and League
-- Shows every player alongside their current club name and
-- the league that club competes in.
-- Demonstrates a three-table join across both domains.
-- ============================================================
SELECT
    p.name                  AS player,
    p.position,
    p.nationality,
    p.date_of_birth,
    c.name                  AS current_club,
    comp.name               AS league,
    comp.country            AS country
FROM   players      p
JOIN   clubs        c    ON c.club_id          = p.current_club_id
JOIN   competitions comp ON comp.competition_id = c.competition_id
ORDER  BY comp.name, c.name, p.name
LIMIT  100;


-- ============================================================
-- Q07 | SUBQUERY 1 | Players Whose Peak Value Exceeded €50m
-- Uses a subquery in the WHERE clause to filter players whose
-- maximum recorded valuation ever exceeded €50 million.
-- ============================================================
SELECT
    p.name,
    p.position,
    p.nationality,
    c.name                              AS current_club
FROM   players p
JOIN   clubs   c ON c.club_id = p.current_club_id
WHERE  p.player_id IN (
           SELECT  player_id
           FROM    market_valuations
           GROUP   BY player_id
           HAVING  MAX(value_euros) > 50000000
       )
ORDER  BY p.name;


-- ============================================================
-- Q08 | SUBQUERY 2 | Clubs Spending Above League Average
-- Finds clubs whose total transfer spend exceeds the average
-- total spend across all clubs in their league.
-- Uses a correlated subquery in the HAVING clause.
-- ============================================================
SELECT
    c.name                              AS club,
    comp.name                           AS league,
    ROUND(SUM(t.fee_euros) / 1e6, 2)   AS total_spent_millions
FROM   transfers    t
JOIN   clubs        c    ON c.club_id          = t.to_club_id
JOIN   competitions comp ON comp.competition_id = c.competition_id
WHERE  t.fee_euros IS NOT NULL
GROUP  BY c.club_id, c.name, comp.competition_id, comp.name
HAVING SUM(t.fee_euros) > (
           SELECT AVG(club_total)
           FROM (
               SELECT  to_club_id, SUM(fee_euros) AS club_total
               FROM    transfers
               WHERE   fee_euros IS NOT NULL
               GROUP   BY to_club_id
           ) sub
       )
ORDER  BY total_spent_millions DESC;


-- ============================================================
-- Q09 | CTE 1 | Top 10 Most Profitable Selling Clubs
-- Uses a CTE to calculate each club's total income from
-- player sales minus total spend on purchases, then ranks
-- clubs by net transfer profit.
-- ============================================================
WITH club_sales AS (
    -- Total income from selling players
    SELECT
        from_club_id        AS club_id,
        SUM(fee_euros)      AS total_income
    FROM   transfers
    WHERE  fee_euros IS NOT NULL
    AND    from_club_id IS NOT NULL
    GROUP  BY from_club_id
),
club_spend AS (
    -- Total spend on buying players
    SELECT
        to_club_id          AS club_id,
        SUM(fee_euros)      AS total_spend
    FROM   transfers
    WHERE  fee_euros IS NOT NULL
    AND    to_club_id IS NOT NULL
    GROUP  BY to_club_id
)
SELECT
    c.name                                          AS club,
    comp.name                                       AS league,
    ROUND(COALESCE(cs.total_income, 0) / 1e6, 2)   AS income_millions,
    ROUND(COALESCE(sp.total_spend,  0) / 1e6, 2)   AS spend_millions,
    ROUND((COALESCE(cs.total_income, 0)
         - COALESCE(sp.total_spend,  0)) / 1e6, 2) AS net_profit_millions
FROM   clubs        c
JOIN   competitions comp ON comp.competition_id = c.competition_id
LEFT   JOIN club_sales cs ON cs.club_id = c.club_id
LEFT   JOIN club_spend sp ON sp.club_id = c.club_id
ORDER  BY net_profit_millions DESC
LIMIT  10;


-- ============================================================
-- Q10 | CTE 2 | Season-by-Season Transfer Spend per League
-- Uses a CTE to aggregate transfer spend by league and season,
-- then selects the full result ordered chronologically.
-- Useful for the dashboard trend line chart.
-- ============================================================
WITH seasonal_spend AS (
    SELECT
        comp.name                           AS league,
        t.season,
        COUNT(t.transfer_id)                AS num_transfers,
        ROUND(SUM(t.fee_euros) / 1e6, 2)   AS total_spent_millions
    FROM   transfers    t
    JOIN   clubs        c    ON c.club_id          = t.to_club_id
    JOIN   competitions comp ON comp.competition_id = c.competition_id
    WHERE  t.fee_euros IS NOT NULL
    GROUP  BY comp.name, t.season
)
SELECT
    league,
    season,
    num_transfers,
    total_spent_millions
FROM   seasonal_spend
ORDER  BY league, season;


-- ============================================================
-- Q11 | WINDOW FUNCTION 1 | Rank Players by Peak Market Value
-- Uses RANK() window function to rank players within each
-- position group by their highest ever recorded market value.
-- ============================================================
SELECT
    player,
    position,
    nationality,
    peak_value_millions,
    RANK() OVER (
        PARTITION BY position
        ORDER BY peak_value_millions DESC
    ) AS rank_in_position
FROM (
    SELECT
        p.name                              AS player,
        p.position,
        p.nationality,
        ROUND(MAX(mv.value_euros) / 1e6, 2) AS peak_value_millions
    FROM   market_valuations mv
    JOIN   players           p  ON p.player_id = mv.player_id
    GROUP  BY p.player_id, p.name, p.position, p.nationality
) ranked
ORDER  BY position, rank_in_position
LIMIT  50;


-- ============================================================
-- Q12 | WINDOW FUNCTION 2 | Running Total of Transfer Spend
-- Uses SUM() OVER (PARTITION BY ... ORDER BY ...) to calculate
-- a running cumulative transfer spend per club across seasons.
-- ============================================================
SELECT
    c.name                                      AS club,
    t.season,
    ROUND(SUM(t.fee_euros) / 1e6, 2)           AS season_spend_millions,
    ROUND(SUM(SUM(t.fee_euros)) OVER (
        PARTITION BY c.club_id
        ORDER BY t.season
    ) / 1e6, 2)                                AS running_total_millions
FROM   transfers t
JOIN   clubs     c ON c.club_id = t.to_club_id
WHERE  t.fee_euros IS NOT NULL
GROUP  BY c.club_id, c.name, t.season
ORDER  BY c.name, t.season;


