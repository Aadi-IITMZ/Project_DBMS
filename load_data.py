# ============================================================
# load_data.py
# Football Transfer Market Analytics Platform
# ============================================================
# Loads filtered CSVs from the filtered/ folder into PostgreSQL.
# Handles all column mapping, type conversion, and cleaning.

# REQUIRES:
#   pip install psycopg2-binary pandas
# ============================================================

import psycopg2
import pandas as pd
import os
from psycopg2.extras import execute_values

# ── Database config — update these values ────────────────────
DB_CONFIG = {
    'host':     'localhost',
    'port':     5432,
    'dbname':   'football_analytics',   # your database name
    'user':     'postgres',             # your PostgreSQL username
    'password': 'your_password_here'    # your PostgreSQL password
}
# ─────────────────────────────────────────────────────────────

FILTERED_DIR = 'filtered'   # folder containing filtered CSVs

# ── Helpers ──────────────────────────────────────────────────
def load_csv(filename):
    path = os.path.join(FILTERED_DIR, filename)
    df = pd.read_csv(path, low_memory=False)
    print(f"  loaded {filename:<35} {len(df):>7,} rows")
    return df

def run(conn, sql, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params)
    conn.commit()

def bulk_insert(conn, table, columns, rows):
    if not rows:
        return
    sql = f"INSERT INTO {table} ({', '.join(columns)}) VALUES %s ON CONFLICT DO NOTHING"
    with conn.cursor() as cur:
        execute_values(cur, sql, rows)
    conn.commit()
    print(f"  inserted {len(rows):>7,} rows into {table}")

# ── Position normaliser ───────────────────────────────────────
POSITION_MAP = {
    'Goalkeeper': 'Goalkeeper',
    'Defender':   'Defender',
    'Midfield':   'Midfielder',
    'Attack':     'Forward',
    'Missing':    'Unknown',
}

def normalise_position(raw):
    if pd.isna(raw):
        return 'Unknown'
    return POSITION_MAP.get(str(raw).strip(), 'Unknown')

# ── Transfer type classifier ──────────────────────────────────
# Maps raw CSV values to our transfer_types lookup table
def classify_transfer(fee_raw):
    """
    The transfers CSV has a market_value_in_eur and transfer_fee columns.
    We infer type from whether a fee is present and its value.
    Returns one of: permanent, loan, free transfer, undisclosed
    """
    if pd.isna(fee_raw):
        return 'undisclosed'
    try:
        fee = float(fee_raw)
        if fee == 0:
            return 'free transfer'
        if fee > 0:
            return 'permanent'
    except (ValueError, TypeError):
        pass
    return 'undisclosed'

# ── Main ─────────────────────────────────────────────────────
def main():
    print("\n── Connecting to PostgreSQL ────────────────────────────\n")
    conn = psycopg2.connect(**DB_CONFIG)
    print("  connected successfully\n")

    print("── Loading CSVs ────────────────────────────────────────\n")
    comp_df   = load_csv('competitions.csv')
    clubs_df  = load_csv('clubs.csv')
    players_df= load_csv('players.csv')
    trans_df  = load_csv('transfers.csv')
    val_df    = load_csv('player_valuations.csv')
    app_df    = load_csv('appearances.csv')

    # ── 1. competitions ──────────────────────────────────────
    print("\n── Inserting competitions ──────────────────────────────\n")
    # Map tier from competition type column
    TIER_MAP = {'first_tier': 'first', 'second_tier': 'second', 'third_tier': 'third'}
    rows = []
    for _, r in comp_df.iterrows():
        tier = TIER_MAP.get(str(r.get('type', '')).strip(), 'first')
        rows.append((
            str(r['name']).strip(),
            str(r.get('country_name', r.get('country', 'Unknown'))).strip(),
            tier
        ))
    bulk_insert(conn, 'competitions', ['name', 'country', 'tier'], rows)

    # Build competition name -> id lookup
    with conn.cursor() as cur:
        cur.execute("SELECT competition_id, name FROM competitions")
        comp_lookup = {name: cid for cid, name in cur.fetchall()}

    # Build competition_id (raw string like GB1) -> db id lookup
    comp_id_map = {}
    for _, r in comp_df.iterrows():
        name = str(r['name']).strip()
        raw_id = str(r['competition_id']).strip()
        if name in comp_lookup:
            comp_id_map[raw_id] = comp_lookup[name]

    # ── 2. clubs ─────────────────────────────────────────────
    print("\n── Inserting clubs ─────────────────────────────────────\n")
    rows = []
    for _, r in clubs_df.iterrows():
        raw_comp = str(r.get('domestic_competition_id', '')).strip()
        db_comp_id = comp_id_map.get(raw_comp)
        if db_comp_id is None:
            continue
        city = str(r.get('city', 'Unknown')).strip()
        if not city or city == 'nan':
            city = 'Unknown'
        name = str(r['name']).strip()
        if not name or name == 'nan':
            continue
        rows.append((name, city, db_comp_id))
    bulk_insert(conn, 'clubs', ['name', 'city', 'competition_id'], rows)

    # Build club name -> db id lookup
    with conn.cursor() as cur:
        cur.execute("SELECT club_id, name FROM clubs")
        club_name_lookup = {name: cid for cid, name in cur.fetchall()}

    # Build raw club_id -> db club_id lookup
    club_id_map = {}
    for _, r in clubs_df.iterrows():
        raw_id = r.get('club_id')
        name = str(r['name']).strip()
        if name in club_name_lookup:
            club_id_map[raw_id] = club_name_lookup[name]

    # ── 3. players ───────────────────────────────────────────
    print("\n── Inserting players ───────────────────────────────────\n")
    rows = []
    for _, r in players_df.iterrows():
        raw_club = r.get('current_club_id')
        db_club_id = club_id_map.get(raw_club)
        dob = r.get('date_of_birth')
        if pd.isna(dob):
            dob = None
        name = str(r.get('name', r.get('pretty_name', ''))).strip()
        if not name or name == 'nan':
            continue
        nationality = str(r.get('country_of_citizenship', '')).strip()
        if not nationality or nationality == 'nan':
            nationality = None
        position = normalise_position(r.get('position'))
        rows.append((
            int(r['player_id']),
            name,
            dob,
            nationality,
            position,
            db_club_id
        ))
    bulk_insert(conn, 'players',
                ['player_id', 'name', 'date_of_birth',
                 'nationality', 'position', 'current_club_id'], rows)

    # Build raw player_id -> db player_id lookup
    with conn.cursor() as cur:
        cur.execute("SELECT player_id FROM players")
        valid_player_ids = set(r[0] for r in cur.fetchall())

    # ── 4. transfer_types (already seeded in schema.sql) ─────
    with conn.cursor() as cur:
        cur.execute("SELECT transfer_type_id, type_name FROM transfer_types")
        type_lookup = {name: tid for tid, name in cur.fetchall()}

    # ── 5. transfers ─────────────────────────────────────────
    print("\n── Inserting transfers ─────────────────────────────────\n")
    rows = []
    for _, r in trans_df.iterrows():
        raw_player = r.get('player_id')
        if raw_player not in valid_player_ids:
            continue

        # season: convert "15/16" -> 2015
        try:
            season_raw = str(r.get('transfer_season', '')).split('/')[0]
            season = int(season_raw) + 2000
            if not (2000 <= season <= 2030):
                continue
        except (ValueError, TypeError):
            continue

        from_club = club_id_map.get(r.get('from_club_id'))
        to_club   = club_id_map.get(r.get('to_club_id'))

        # Skip if both clubs are the same valid club
        if from_club and to_club and from_club == to_club:
            continue

        fee_raw = r.get('transfer_fee')

        # Explicitly convert pandas NaN to None before inserting
        import math
        try:
            fee_float = float(fee_raw)
            if math.isnan(fee_float) or fee_float <= 0:
                fee = None
            else:
                fee = fee_float
        except (ValueError, TypeError):
            fee = None

        transfer_type_name = classify_transfer(fee_raw)

        # Check loan flag if present
        if str(r.get('is_loan', '')).strip().lower() in ('true', '1', 'yes'):
            transfer_type_name = 'loan'

        type_id = type_lookup.get(transfer_type_name, type_lookup['undisclosed'])

        rows.append((
            int(raw_player),
            from_club,
            to_club,
            type_id,
            season,
            fee
        ))
    bulk_insert(conn, 'transfers',
                ['player_id', 'from_club_id', 'to_club_id',
                 'transfer_type_id', 'season', 'fee_euros'], rows)

    # ── 6. market_valuations ─────────────────────────────────
    print("\n── Inserting market_valuations ─────────────────────────\n")
    rows = []
    seen = set()
    for _, r in val_df.iterrows():
        raw_player = r.get('player_id')
        if raw_player not in valid_player_ids:
            continue
        try:
            val = float(r.get('market_value_in_eur', 0))
            if val < 0:
                continue
        except (ValueError, TypeError):
            continue
        date = str(r.get('date', '')).strip()
        if not date or date == 'nan':
            continue
        key = (int(raw_player), date)
        if key in seen:
            continue
        seen.add(key)
        rows.append((int(raw_player), date, val))
    bulk_insert(conn, 'market_valuations',
                ['player_id', 'valuation_date', 'value_euros'], rows)

    # ── 7. appearances ───────────────────────────────────────
    print("\n── Inserting appearances ───────────────────────────────\n")
    rows = []
    seen = set()
    for _, r in app_df.iterrows():
        raw_player = r.get('player_id')
        if raw_player not in valid_player_ids:
            continue
        raw_club = r.get('player_current_club_id', r.get('club_id'))
        db_club = club_id_map.get(raw_club)
        if db_club is None:
            continue
        date_str = str(r.get('date', '')).strip()
        try:
            season = int(date_str[:4])
            if not (2000 <= season <= 2030):
                continue
        except (ValueError, TypeError):
            continue
        key = (int(raw_player), db_club, season)
        if key in seen:
            continue
        seen.add(key)
        goals   = max(0, int(r.get('goals', 0) or 0))
        assists = max(0, int(r.get('assists', 0) or 0))
        minutes = max(0, int(r.get('minutes_played', 0) or 0))
        rows.append((int(raw_player), db_club, season, goals, assists, minutes))
    bulk_insert(conn, 'appearances',
                ['player_id', 'club_id', 'season',
                 'goals', 'assists', 'minutes_played'], rows)

    # ── Final row counts ─────────────────────────────────────
    print("\n── Verification ────────────────────────────────────────\n")
    tables = ['competitions', 'clubs', 'transfer_types', 'players',
              'transfers', 'market_valuations', 'appearances']
    total = 0
    with conn.cursor() as cur:
        for t in tables:
            cur.execute(f"SELECT COUNT(*) FROM {t}")
            count = cur.fetchone()[0]
            total += count
            print(f"  {t:<25} {count:>7,} rows")
    print(f"\n  {'TOTAL':<25} {total:>7,} rows")
    print("\n── Done. Database is ready. ────────────────────────────\n")
    conn.close()

if __name__ == '__main__':
    main()
