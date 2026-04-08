-- ============================================================
-- Football Transfer Market Analytics Platform
-- Track C: Advanced Schema and Analytics Platform
-- schema.sql — runs from scratch, no manual edits required
-- Dataset: Transfermarkt (Kaggle: davidcariboo/player-scores)
-- Scope: Premier League + La Liga
-- ============================================================

-- Drop tables in reverse dependency order (safe re-run)
DROP TABLE IF EXISTS appearances        CASCADE;
DROP TABLE IF EXISTS market_valuations  CASCADE;
DROP TABLE IF EXISTS transfers          CASCADE;
DROP TABLE IF EXISTS transfer_types     CASCADE;
DROP TABLE IF EXISTS players            CASCADE;
DROP TABLE IF EXISTS clubs              CASCADE;
DROP TABLE IF EXISTS competitions       CASCADE;


-- ============================================================
-- DOMAIN 1: Club Operations
-- ============================================================

-- competitions
-- One row per league. Clubs belong to exactly one competition.
-- Justification: competition_id -> name, country, tier (no transitive deps)
CREATE TABLE competitions (
    competition_id   SERIAL          PRIMARY KEY,
    name             VARCHAR(100)    NOT NULL UNIQUE,
    country          VARCHAR(100)    NOT NULL,
    tier             VARCHAR(20)     NOT NULL
                         CHECK (tier IN ('first', 'second', 'third')),
    CONSTRAINT chk_country_nonempty CHECK (char_length(trim(country)) > 0)
);

-- clubs
-- One row per club. A club belongs to one competition (league).
-- Justification: club_id -> name, city, competition_id
-- competition_id stored here, not name/country, to avoid transitive dependency (3NF)
CREATE TABLE clubs (
    club_id          SERIAL          PRIMARY KEY,
    name             VARCHAR(150)    NOT NULL UNIQUE,
    city             VARCHAR(100)    NOT NULL,
    competition_id   INT             NOT NULL
                         REFERENCES competitions(competition_id)
                         ON DELETE RESTRICT
);


-- ============================================================
-- DOMAIN 2: Player Careers
-- ============================================================

-- players
-- One row per player. club_id = current club at time of data load.
-- Justification: player_id -> name, dob, nationality, position, club_id
-- nationality does NOT depend on club_id (avoids transitive dep — 3NF satisfied)
CREATE TABLE players (
    player_id        SERIAL          PRIMARY KEY,
    name             VARCHAR(150)    NOT NULL,
    date_of_birth    DATE,
    nationality      VARCHAR(100),
    position         VARCHAR(50)
                         CHECK (position IN (
                             'Goalkeeper','Defender','Midfielder',
                             'Forward','Unknown'
                         )),
    current_club_id  INT
                         REFERENCES clubs(club_id)
                         ON DELETE SET NULL
);

-- transfer_types
-- Lookup table for how a transfer was conducted.
-- Justification: transfer_type_id -> type_name, description (no deps between non-key cols)
-- Removing type_name from transfers avoids repeating string literals — satisfies 3NF.
-- Pre-seeded with INSERT statements below; no manual edits required.
CREATE TABLE transfer_types (
    transfer_type_id  SERIAL         PRIMARY KEY,
    type_name         VARCHAR(50)    NOT NULL UNIQUE,
    description       VARCHAR(200)
);

INSERT INTO transfer_types (type_name, description) VALUES
    ('permanent',    'Full transfer with a fixed fee paid between clubs'),
    ('loan',         'Temporary move; player returns to parent club after agreed period'),
    ('free transfer','Player moves at end of contract; no fee paid'),
    ('undisclosed',  'Transfer completed but fee not publicly revealed');

-- transfers
-- One row per transfer event. Links a player, a selling club, and a buying club.
-- Composite FK pattern: from_club_id and to_club_id both reference clubs.
-- fee_euros NULL = loan or undisclosed fee.
-- Justification: transfer_id -> player_id, from_club_id, to_club_id, season, fee, type
-- type_name lives in transfer_types, not here — avoids transitive dep (3NF)
CREATE TABLE transfers (
    transfer_id       SERIAL         PRIMARY KEY,
    player_id         INT            NOT NULL
                          REFERENCES players(player_id)
                          ON DELETE CASCADE,
    from_club_id      INT
                          REFERENCES clubs(club_id)
                          ON DELETE SET NULL,
    to_club_id        INT
                          REFERENCES clubs(club_id)
                          ON DELETE SET NULL,
    transfer_type_id  INT            NOT NULL
                          REFERENCES transfer_types(transfer_type_id)
                          ON DELETE RESTRICT,
    season            INT            NOT NULL
                          CHECK (season BETWEEN 2000 AND 2030),
    fee_euros         NUMERIC(15, 2)
                          CHECK (fee_euros IS NULL OR fee_euros >= 0),
    CONSTRAINT chk_different_clubs CHECK (from_club_id IS NULL
                                          OR to_club_id IS NULL
                                          OR from_club_id <> to_club_id)
);

-- market_valuations
-- One row per player per valuation date (point-in-time snapshot).
-- Composite candidate key: (player_id, valuation_date) — used for BCNF argument.
-- Justification: (player_id, valuation_date) -> value_euros
CREATE TABLE market_valuations (
    valuation_id     SERIAL          PRIMARY KEY,
    player_id        INT             NOT NULL
                         REFERENCES players(player_id)
                         ON DELETE CASCADE,
    valuation_date   DATE            NOT NULL,
    value_euros      NUMERIC(15, 2)  NOT NULL
                         CHECK (value_euros >= 0),
    CONSTRAINT uq_player_valuation_date UNIQUE (player_id, valuation_date)
);

-- appearances
-- One row per player per club per season (aggregated stats).
-- Composite candidate key: (player_id, club_id, season)
-- Justification: (player_id, club_id, season) -> goals, assists, minutes_played
-- goals depends on ALL three key parts — satisfies 2NF (no partial dependency)
CREATE TABLE appearances (
    appearance_id    SERIAL          PRIMARY KEY,
    player_id        INT             NOT NULL
                         REFERENCES players(player_id)
                         ON DELETE CASCADE,
    club_id          INT             NOT NULL
                         REFERENCES clubs(club_id)
                         ON DELETE CASCADE,
    season           INT             NOT NULL
                         CHECK (season BETWEEN 2000 AND 2030),
    goals            INT             NOT NULL DEFAULT 0 CHECK (goals >= 0),
    assists          INT             NOT NULL DEFAULT 0 CHECK (assists >= 0),
    minutes_played   INT             NOT NULL DEFAULT 0 CHECK (minutes_played >= 0),
    CONSTRAINT uq_appearance UNIQUE (player_id, club_id, season)
);


-- ============================================================
-- Indexes (baseline — performance section adds more)
-- ============================================================
CREATE INDEX idx_players_club        ON players(current_club_id);
CREATE INDEX idx_transfers_player    ON transfers(player_id);
CREATE INDEX idx_transfers_season    ON transfers(season);
CREATE INDEX idx_transfers_type      ON transfers(transfer_type_id);
CREATE INDEX idx_valuations_player   ON market_valuations(player_id);
CREATE INDEX idx_appearances_player  ON appearances(player_id);
CREATE INDEX idx_appearances_season  ON appearances(season);


-- ============================================================
-- Verification query (runs after load to confirm row counts)
-- ============================================================
-- SELECT 'competitions'    AS tbl, COUNT(*) FROM competitions
-- UNION ALL
-- SELECT 'clubs',                   COUNT(*) FROM clubs
-- UNION ALL
-- SELECT 'transfer_types',          COUNT(*) FROM transfer_types
-- UNION ALL
-- SELECT 'players',                 COUNT(*) FROM players
-- UNION ALL
-- SELECT 'transfers',               COUNT(*) FROM transfers
-- UNION ALL
-- SELECT 'market_valuations',       COUNT(*) FROM market_valuations
-- UNION ALL
-- SELECT 'appearances',             COUNT(*) FROM appearances;
