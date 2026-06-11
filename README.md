# Football Transfer Market Analytics Platform
**Track C — Advanced Schema and Analytics Platform**  
Dataset: Transfermarkt (Kaggle: davidcariboo/player-scores)  
Scope: Premier League + La Liga, 2015–2023  
GitHub: https://github.com/Aadi-IITMZ/Project_DBMS

---

## Dataset Manipulation/Filtering

Using a Python script, the dataset downloadable from [kaggle.com/datasets/davidcariboo/player-scores](https://www.kaggle.com/datasets/davidcariboo/player-scores) was filtered down from over 1 million rows across 6 CSV files to approximately 25,000 rows covering the Premier League and La Liga between 2015 and 2023. This scope provides enough data for meaningful analysis while keeping the system under light load. The filtered CSV files are provided in the `filtered/` folder.

---

## Repository Structure

```
/filtered/          Filtered CSV files (6 files)
ERD M1.pdf          ER diagram
schema.sql          Database schema — creates all 7 tables and indexes
load_data.py        Loads filtered CSVs into PostgreSQL
app.py              Streamlit analytics dashboard
Queries.sql         All 21 SQL queries labelled by purpose
performance.sql     EXPLAIN ANALYZE before/after indexing analysis
README.md           This file
requirements.txt    Python dependencies
.env.example        Environment variable template
```

---

## Prerequisites

Make sure the following are installed on your system before starting:

- PostgreSQL (any recent version)
- Python 3.8 or higher

Install all Python dependencies:

```
pip install -r requirements.txt
```

---

## Step 1 — Environment Setup

Copy `.env.example` to `.env`:

```
cp .env.example .env
```

Open `.env` and fill in your PostgreSQL credentials:

```
DB_HOST=localhost
DB_PORT=5432
DB_NAME=football_analytics
DB_USER=postgres
DB_PASSWORD=
```

---

## Step 2 — Create the Database

Open pgAdmin and connect to your PostgreSQL server. Open a query tool on the default `postgres` database and run:

```sql
CREATE DATABASE football_analytics;
```

Then switch to the `football_analytics` database by opening a new query tool connected to it.

---

## Step 3 — Run the Schema

With `football_analytics` selected in pgAdmin, open and run `schema.sql`. This creates all 7 tables, indexes, and seeds the `transfer_types` lookup table. NOTICE messages on first run are harmless.

---

## Step 4 — Load the Data

Make sure the `filtered/` folder is in the same directory as `load_data.py`, then run:

```
python load_data.py
```

Expected output:

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

Open `Queries.sql` in pgAdmin (connected to `football_analytics`) and run the full file. All 21 queries will execute sequentially, each labelled by type and purpose.

For performance analysis, open and run `performance.sql` section by section.

---

## Step 6 — Run the Streamlit Dashboard

```
streamlit run app.py
```

Opens automatically at `http://localhost:8501`. Make sure PostgreSQL is running before starting the app. The dashboard includes:

- Season range and league filters in the sidebar
- 4 KPI cards (total spend, transfers, players, average fee)
- 5 interactive chart tabs: Club Spending, Player Value by Age, Profitability, Seasonal Trends, Performance per 90

---

## Resetting the Database

To wipe all data and start fresh, re-run `schema.sql` followed by `load_data.py`. The schema uses `DROP TABLE IF EXISTS ... CASCADE` so it cleans up safely every time.
