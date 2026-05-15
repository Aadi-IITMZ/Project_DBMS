# Football Transfer Market Analytics Platform

**Track C — Advanced Schema and Analytics Platform** Dataset: Transfermarkt (Kaggle: davidcariboo/player-scores) Scope: Premier League \+ La Liga, 2015–2023  
GitHub: [https://github.com/Aadi-IITMZ/Project\_DBMS](https://github.com/Aadi-IITMZ/Project_DBMS)  
---

## Dataset Manipulation/Filtering

Using a Python script, the dataset downloadable from [kaggle.com/datasets/davidcariboo/player-scores](https://www.kaggle.com/datasets/davidcariboo/player-scores) was filtered down from over 1 million rows across 6 CSV files to approximately 25,000 rows covering the Premier League and La Liga between 2015 and 2023\. This scope provides enough data for meaningful analysis while keeping the system under light load. The filtered CSV files are provided in the *`filtered/`* folder.

---

## Prerequisites

Make sure the following are installed on your system before starting:

- PostgreSQL (any recent version)  
- Python 3.12 or higher  
- The following Python packages:

```
pip install psycopg2-binary pandas
```

---

## Step 1 — Create the Database

Open pgAdmin and connect to your PostgreSQL server. Open a query tool on the default `postgres` database and run:

```sql
CREATE DATABASE football_analytics;
```

Then switch to the *`football_analytics`* database by opening a new query tool connected to it.

---

## Step 2 — Run the Schema

With *`football_analytics`* selected in pgAdmin, open and run ***`schema.sql`***. This creates all 7 tables, indexes, and seeds the *`transfer_types`* lookup table.  
---

## Step 3 — Configure the Loading Script

Open *`load_data.py`* and update the *`DB_CONFIG`* block at the top with your PostgreSQL credentials:

```py
DB_CONFIG = {
    'host':     'localhost',
    'port':     5432,
    'dbname':   'football_analytics',
    'user':     'postgres',
    'password': 'your_password_here'
}
```

---

## Step 4 — Load the Data

Place the *`filtered/`* folder in the same directory as *`load_data.py`*. The following 6 files are required:

- `competitions.csv`  
- `clubs.csv`  
- `players.csv`  
- `transfers.csv`  
- `player_valuations.csv`  
- `appearances.csv`

Then run:

```
python load_data.py
```

The script will print a row count for every table on completion. Expected output:

```
competitions              2 rows
clubs                    70 rows
transfer_types            4 rows
players               4,328 rows
transfers             9,055 rows
market_valuations     8,000 rows
appearances           4,190 rows
TOTAL                25,649 rows
```

---

## Step 5 — Run the Queries

Open *`queries.sql`* in pgAdmin and run the file by each query (marked with comments)

---

## Resetting the Database

To wipe all data and start fresh, simply re-run *`schema.sql`* followed by *`load_data.py`*. The schema uses *`DROP TABLE IF EXISTS ... CASCADE`* so it cleans up safely every time.  
