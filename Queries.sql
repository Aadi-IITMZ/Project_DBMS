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


-- ============================================================
-- MILESTONE 3 QUERIES (Q13 - Q22)
-- Completing the required 20 queries for Track C
-- ============================================================
-- Query index (continued):
--   Q13  RECURSIVE CTE    — Trace a player's full transfer chain
--   Q14  TRANSACTION      — Atomically transfer a player between clubs
--   Q15  AGG-3            — Top 10 nationalities by avg peak market value
--   Q16  AGG-4            — Goals + assists per 90 minutes by position
--   Q17  JOIN + SUBQUERY  — Players transferred within 1 year of peak value
--   Q18  JOIN + CTE       — Clubs that bought and sold the same player
--   Q19  WINDOW-3         — Year-on-year % change in club transfer spend
--   Q20  WINDOW-4         — Moving average of player market value over time
--   Q21  SUB + AGG        — League comparison: avg fee vs avg player value
--   Q22  STORED PROCEDURE — Update player's club after a new transfer
-- ============================================================

SELECT player_id, name FROM players WHERE name LIKE '%Case%';

-- ============================================================
-- Q13 | RECURSIVE CTE | Player Transfer Chain
-- Traces the full career transfer history of a player by
-- recursively following their moves from club to club.
-- Demonstrates recursive CTE — mandatory Track C requirement.
-- To trace a different player, change the player_id in the
-- anchor member.
-- ============================================================
WITH RECURSIVE transfer_chain AS (

    -- Anchor: first recorded transfer for the player
    SELECT
        t.transfer_id,
        t.player_id,
        t.from_club_id,
        t.to_club_id,
        t.season,
        t.fee_euros,
        1 AS depth
    FROM   transfers t
    WHERE  t.player_id = 16306
    AND    t.from_club_id IS NOT NULL

    UNION ALL

    -- Recursive: follow the player to their next club
    SELECT
        t.transfer_id,
        t.player_id,
        t.from_club_id,
        t.to_club_id,
        t.season,
        t.fee_euros,
        tc.depth + 1
    FROM   transfers      t
    JOIN   transfer_chain tc ON t.from_club_id = tc.to_club_id
                             AND t.player_id   = tc.player_id
                             AND t.season      > tc.season
    WHERE  tc.depth < 10   -- guard against infinite loops
)
SELECT
    p.name                              AS player,
    fc.name                             AS from_club,
    toc.name                            AS to_club,
    tc.season,
    ROUND(tc.fee_euros / 1e6, 2)        AS fee_millions,
    tc.depth                            AS transfer_number
FROM   transfer_chain tc
JOIN   players p   ON p.player_id  = tc.player_id
LEFT JOIN clubs fc  ON fc.club_id  = tc.from_club_id
LEFT JOIN clubs toc ON toc.club_id = tc.to_club_id
ORDER  BY tc.depth;


-- ============================================================
-- Q14 | STORED PROCEDURE | Complete Player Transfer
-- Transfers a player to a new club by:
--   1. Validating player and both clubs exist
--   2. Inserting a full transfer record with fee and type
--   3. Updating the player's current club atomically
--
-- HOW TO RUN:
--   CALL transfer_player(player_id, to_club_id, fee_in_euros);
--   Example: CALL transfer_player(3109, 5, 50000000);
--   For a free transfer: CALL transfer_player(3109, 5, 0);
-- ============================================================
CREATE OR REPLACE PROCEDURE transfer_player(
    p_player_id   INT,
    p_to_club_id  INT,
    p_fee_euros   NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_from_club_id    INT;
    v_transfer_type   INT;
BEGIN
    -- Validate player exists
    IF NOT EXISTS (SELECT 1 FROM players WHERE player_id = p_player_id) THEN
        RAISE EXCEPTION 'Player with id % does not exist', p_player_id;
    END IF;

    -- Validate destination club exists
    IF NOT EXISTS (SELECT 1 FROM clubs WHERE club_id = p_to_club_id) THEN
        RAISE EXCEPTION 'Club with id % does not exist', p_to_club_id;
    END IF;

    -- Get player's current club
    SELECT current_club_id INTO v_from_club_id
    FROM   players WHERE player_id = p_player_id;

    -- Determine transfer type from fee
    IF p_fee_euros = 0 THEN
        SELECT transfer_type_id INTO v_transfer_type
        FROM   transfer_types WHERE type_name = 'free transfer';
    ELSIF p_fee_euros IS NULL THEN
        SELECT transfer_type_id INTO v_transfer_type
        FROM   transfer_types WHERE type_name = 'undisclosed';
    ELSE
        SELECT transfer_type_id INTO v_transfer_type
        FROM   transfer_types WHERE type_name = 'permanent';
    END IF;

    -- Insert transfer record
    INSERT INTO transfers (
        player_id, from_club_id, to_club_id,
        transfer_type_id, season, fee_euros
    ) VALUES (
        p_player_id,
        v_from_club_id,
        p_to_club_id,
        v_transfer_type,
        2023,
        NULLIF(p_fee_euros, 0)
    );

    -- Update player's current club
    UPDATE players
    SET    current_club_id = p_to_club_id
    WHERE  player_id = p_player_id;

    RAISE NOTICE 'Player % successfully transferred to club % for €%',
        p_player_id, p_to_club_id, p_fee_euros;
END;
$$;

-- Test call (transfer Steven Gerrard to Barcelona for €50m):
-- CALL transfer_player(3109, 5, 50000000);


-- ============================================================
-- Q15 | AGGREGATION 3 | Top 10 Nationalities by Peak Value
-- Groups players by nationality and calculates their average
-- peak market value. Shows which countries produce the most
-- valuable players on average.
-- ============================================================
SELECT
    p.nationality,
    COUNT(DISTINCT p.player_id)                 AS player_count,
    ROUND(AVG(peak.max_value) / 1e6, 2)         AS avg_peak_value_millions,
    ROUND(MAX(peak.max_value) / 1e6, 2)         AS highest_peak_millions
FROM   players p
JOIN (
    SELECT   player_id, MAX(value_euros) AS max_value
    FROM     market_valuations
    GROUP BY player_id
) peak ON peak.player_id = p.player_id
WHERE  p.nationality IS NOT NULL
GROUP  BY p.nationality
HAVING COUNT(DISTINCT p.player_id) >= 5   -- at least 5 players per nationality
ORDER  BY avg_peak_value_millions DESC
LIMIT  10;


-- ============================================================
-- Q16 | AGGREGATION 4 | Goals + Assists per 90 Minutes
-- Calculates attacking contribution per 90 minutes for each
-- position group. Filters out players with minimal minutes
-- to avoid skewed ratios from rare appearances.
-- ============================================================
SELECT
    p.position,
    COUNT(DISTINCT p.player_id)                             AS players,
    ROUND(SUM(a.goals)::numeric   / NULLIF(SUM(a.minutes_played), 0) * 90, 2)
                                                            AS goals_per_90,
    ROUND(SUM(a.assists)::numeric / NULLIF(SUM(a.minutes_played), 0) * 90, 2)
                                                            AS assists_per_90,
    ROUND((SUM(a.goals) + SUM(a.assists))::numeric
          / NULLIF(SUM(a.minutes_played), 0) * 90, 2)      AS contributions_per_90
FROM   appearances a
JOIN   players     p ON p.player_id = a.player_id
WHERE  a.minutes_played >= 90   -- at least one full game worth of minutes
AND    p.position IS NOT NULL
GROUP  BY p.position
ORDER  BY contributions_per_90 DESC;


-- ============================================================
-- Q17 | JOIN + SUBQUERY | Transfers Near Peak Value
-- Finds players who were transferred within one season of
-- reaching their peak recorded market value — indicating
-- clubs sold at or near the optimal time.
-- ============================================================
SELECT
    p.name                              AS player,
    p.position,
    p.nationality,
    fc.name                             AS sold_by,
    tc.name                             AS bought_by,
    t.season                            AS transfer_season,
    ROUND(peak.max_value   / 1e6, 2)   AS peak_value_millions,
    ROUND(t.fee_euros      / 1e6, 2)   AS transfer_fee_millions
FROM   transfers t
JOIN   players   p   ON p.player_id  = t.player_id
LEFT JOIN clubs  fc  ON fc.club_id   = t.from_club_id
LEFT JOIN clubs  tc  ON tc.club_id   = t.to_club_id
JOIN (
    -- Subquery: get each player's peak value and the year it occurred
    SELECT
        mv.player_id,
        MAX(mv.value_euros)                         AS max_value,
        EXTRACT(YEAR FROM MAX(mv.valuation_date))   AS peak_year
    FROM   market_valuations mv
    GROUP  BY mv.player_id
) peak ON peak.player_id = t.player_id
WHERE  t.fee_euros IS NOT NULL
AND    ABS(t.season - peak.peak_year) <= 1   -- transferred within 1 season of peak
ORDER  BY peak.max_value DESC
LIMIT  20;


-- ============================================================
-- Q18 | JOIN + CTE | Club Profit/Loss per Player
-- Identifies clubs that both bought and sold the same player,
-- then calculates the profit or loss made on that player.
-- ============================================================
WITH bought AS (
    SELECT
        to_club_id      AS club_id,
        player_id,
        fee_euros       AS buy_fee,
        season          AS buy_season
    FROM   transfers
    WHERE  fee_euros IS NOT NULL
    AND    to_club_id IS NOT NULL
),
sold AS (
    SELECT
        from_club_id    AS club_id,
        player_id,
        fee_euros       AS sell_fee,
        season          AS sell_season
    FROM   transfers
    WHERE  fee_euros IS NOT NULL
    AND    from_club_id IS NOT NULL
)
SELECT
    c.name                                          AS club,
    p.name                                          AS player,
    b.buy_season,
    s.sell_season,
    ROUND(b.buy_fee  / 1e6, 2)                     AS bought_for_millions,
    ROUND(s.sell_fee / 1e6, 2)                     AS sold_for_millions,
    ROUND((s.sell_fee - b.buy_fee) / 1e6, 2)       AS profit_millions
FROM   bought b
JOIN   sold   s ON s.club_id   = b.club_id
               AND s.player_id = b.player_id
               AND s.sell_season > b.buy_season
JOIN   clubs   c ON c.club_id  = b.club_id
JOIN   players p ON p.player_id = b.player_id
ORDER  BY profit_millions DESC
LIMIT  20;


-- ============================================================
-- Q19 | WINDOW FUNCTION 3 | Year-on-Year Transfer Spend Change
-- Uses LAG() window function to compare each club's transfer
-- spend against the previous season, calculating the
-- percentage change year on year.
-- ============================================================
SELECT
    club,
    season,
    season_spend_millions,
    prev_season_millions,
    ROUND(
        (season_spend_millions - prev_season_millions)
        / NULLIF(prev_season_millions, 0) * 100
    , 1)                            AS pct_change
FROM (
    SELECT
        c.name                                      AS club,
        t.season,
        ROUND(SUM(t.fee_euros) / 1e6, 2)           AS season_spend_millions,
        ROUND(LAG(SUM(t.fee_euros)) OVER (
            PARTITION BY c.club_id
            ORDER BY t.season
        ) / 1e6, 2)                                AS prev_season_millions
    FROM   transfers t
    JOIN   clubs     c ON c.club_id = t.to_club_id
    WHERE  t.fee_euros IS NOT NULL
    GROUP  BY c.club_id, c.name, t.season
) yoy
WHERE  prev_season_millions IS NOT NULL
ORDER  BY ABS(
    (season_spend_millions - prev_season_millions)
    / NULLIF(prev_season_millions, 0) * 100
) DESC
LIMIT  30;


-- ============================================================
-- Q20 | WINDOW FUNCTION 4 | Moving Average of Player Value
-- Uses AVG() OVER with a sliding window frame to calculate
-- a 3-snapshot moving average of a player's market value,
-- smoothing out sudden spikes in valuation data.
-- ============================================================
SELECT
    p.name                                          AS player,
    p.position,
    mv.valuation_date,
    ROUND(mv.value_euros       / 1e6, 2)           AS value_millions,
    ROUND(AVG(mv.value_euros) OVER (
        PARTITION BY mv.player_id
        ORDER BY mv.valuation_date
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) / 1e6, 2)                                    AS moving_avg_millions
FROM   market_valuations mv
JOIN   players           p ON p.player_id = mv.player_id
WHERE  p.player_id IN (
    -- Only show players with at least 5 valuation snapshots
    SELECT player_id
    FROM   market_valuations
    GROUP  BY player_id
    HAVING COUNT(*) >= 5
)
ORDER  BY p.name, mv.valuation_date
LIMIT  100;


-- ============================================================
-- Q21 | SUBQUERY + AGGREGATION | League Fee vs Player Value
-- Compares the average transfer fee paid in each league
-- against the average market value of players bought,
-- showing whether clubs pay above or below market value.
-- ============================================================
SELECT
    comp.name                                       AS league,
    ROUND(AVG(t.fee_euros)   / 1e6, 2)             AS avg_fee_paid_millions,
    ROUND(AVG(player_val.avg_value) / 1e6, 2)      AS avg_player_value_millions,
    ROUND((AVG(t.fee_euros) - AVG(player_val.avg_value))
          / NULLIF(AVG(player_val.avg_value), 0) * 100, 1)
                                                    AS pct_above_market_value
FROM   transfers t
JOIN   clubs     c    ON c.club_id          = t.to_club_id
JOIN   competitions comp ON comp.competition_id = c.competition_id
JOIN (
    -- Subquery: average market value per player across all snapshots
    SELECT   player_id, AVG(value_euros) AS avg_value
    FROM     market_valuations
    GROUP BY player_id
) player_val ON player_val.player_id = t.player_id
WHERE  t.fee_euros IS NOT NULL
GROUP  BY comp.name
ORDER  BY avg_fee_paid_millions DESC;






