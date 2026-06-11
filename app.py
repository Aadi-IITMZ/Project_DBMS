# ============================================================
# app.py
# Football Transfer Market Analytics — Streamlit Dashboard
# ============================================================
# SETUP:
#   pip install streamlit plotly psycopg2-binary pandas
#
# RUN:
#   streamlit run app.py
#
# Opens automatically at http://localhost:8501
# Update DB_CONFIG below with your PostgreSQL credentials
# ============================================================

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import psycopg2

# ── Page config ───────────────────────────────────────────────
st.set_page_config(
    page_title="Football Transfer Analytics",
    page_icon="⚽",
    layout="wide",
    initial_sidebar_state="expanded"
)

# ── DB config — update password ───────────────────────────────
DB_CONFIG = {
    'host':     'localhost',
    'port':     5432,
    'dbname':   'football_analytics',
    'user':     'postgres',
    'password': 'your_password_here'
}

# ── DB connection (cached so it doesn't reconnect every render)
@st.cache_resource
def get_connection():
    return psycopg2.connect(**DB_CONFIG)

@st.cache_data(ttl=60)
def query(sql):
    conn = get_connection()
    return pd.read_sql_query(sql, conn)

# ── Sidebar ───────────────────────────────────────────────────
st.sidebar.title("⚽ Filters")
st.sidebar.markdown("---")

season_range = st.sidebar.slider(
    "Season Range",
    min_value=2015,
    max_value=2023,
    value=(2015, 2023),
    step=1
)

league_options = ["Both", "Premier League", "La Liga"]
selected_league = st.sidebar.selectbox("League", league_options)

st.sidebar.markdown("---")
st.sidebar.markdown("**Dataset**")
st.sidebar.markdown("Transfermarkt · 2015–2023")
st.sidebar.markdown("Premier League + La Liga")
st.sidebar.markdown("25,649 rows · 7 tables")

# ── League filter helper ──────────────────────────────────────
def league_clause(alias="comp"):
    if selected_league == "Premier League":
        return f"AND {alias}.name = 'premier-league'"
    elif selected_league == "La Liga":
        return f"AND {alias}.name = 'laliga'"
    return ""

def league_label(raw):
    return "Premier League" if raw == "premier-league" else "La Liga"

# ── Title ─────────────────────────────────────────────────────
st.title("⚽ Football Transfer Market Analytics")
st.markdown(f"**Scope:** {selected_league if selected_league != 'Both' else 'Premier League + La Liga'} · **Seasons:** {season_range[0]}–{season_range[1]}")
st.markdown("---")

# ── KPI row ───────────────────────────────────────────────────
kpi1, kpi2, kpi3, kpi4 = st.columns(4)

total_spend = query(f"""
    SELECT ROUND(SUM(t.fee_euros) / 1e6, 1) AS val
    FROM transfers t
    JOIN clubs c ON c.club_id = t.to_club_id
    JOIN competitions comp ON comp.competition_id = c.competition_id
    WHERE t.fee_euros IS NOT NULL
    AND t.season BETWEEN {season_range[0]} AND {season_range[1]}
    {league_clause()}
""")

total_transfers = query(f"""
    SELECT COUNT(*) AS val
    FROM transfers t
    JOIN clubs c ON c.club_id = t.to_club_id
    JOIN competitions comp ON comp.competition_id = c.competition_id
    WHERE t.season BETWEEN {season_range[0]} AND {season_range[1]}
    {league_clause()}
""")

total_players = query(f"""
    SELECT COUNT(DISTINCT p.player_id) AS val
    FROM players p
    JOIN clubs c ON c.club_id = p.current_club_id
    JOIN competitions comp ON comp.competition_id = c.competition_id
    WHERE 1=1 {league_clause()}
""")

avg_fee = query(f"""
    SELECT ROUND(AVG(t.fee_euros) / 1e6, 1) AS val
    FROM transfers t
    JOIN clubs c ON c.club_id = t.to_club_id
    JOIN competitions comp ON comp.competition_id = c.competition_id
    WHERE t.fee_euros IS NOT NULL AND t.fee_euros > 0
    AND t.season BETWEEN {season_range[0]} AND {season_range[1]}
    {league_clause()}
""")

kpi1.metric("Total Spend", f"€{total_spend['val'].iloc[0]}m")
kpi2.metric("Total Transfers", f"{int(total_transfers['val'].iloc[0]):,}")
kpi3.metric("Players", f"{int(total_players['val'].iloc[0]):,}")
kpi4.metric("Avg Fee", f"€{avg_fee['val'].iloc[0]}m")

st.markdown("---")

# ── Tabs ──────────────────────────────────────────────────────
tab1, tab2, tab3, tab4, tab5 = st.tabs([
    "💰 Club Spending",
    "📈 Player Value",
    "💹 Profitability",
    "📅 Seasonal Trends",
    "⚡ Performance"
])

# ── TAB 1: Club Spending ──────────────────────────────────────
with tab1:
    st.subheader("Top 10 Clubs by Total Transfer Spend")

    df1 = query(f"""
        SELECT
            c.name                              AS club,
            comp.name                           AS league,
            ROUND(SUM(t.fee_euros) / 1e6, 1)   AS total_spent_millions
        FROM   transfers      t
        JOIN   clubs          c    ON c.club_id          = t.to_club_id
        JOIN   competitions   comp ON comp.competition_id = c.competition_id
        JOIN   transfer_types tt   ON tt.transfer_type_id = t.transfer_type_id
        WHERE  tt.type_name = 'permanent'
        AND    t.fee_euros  IS NOT NULL
        AND    t.season BETWEEN {season_range[0]} AND {season_range[1]}
        {league_clause()}
        GROUP  BY c.name, comp.name
        ORDER  BY total_spent_millions DESC
        LIMIT  10
    """)

    df1['league_label'] = df1['league'].apply(league_label)

    fig1 = px.bar(
        df1, x='total_spent_millions', y='club',
        color='league_label',
        orientation='h',
        color_discrete_map={"Premier League": "#00e5a0", "La Liga": "#e55a00"},
        labels={'total_spent_millions': 'Total Spend (€m)', 'club': ''},
        text='total_spent_millions'
    )
    fig1.update_traces(texttemplate='€%{text}m', textposition='outside')
    fig1.update_layout(
        yaxis={'categoryorder': 'total ascending'},
        legend_title="League",
        height=450,
        margin=dict(l=0, r=80, t=20, b=0)
    )
    st.plotly_chart(fig1, use_container_width=True)
    st.dataframe(df1[['club', 'league_label', 'total_spent_millions']].rename(
        columns={'league_label': 'league', 'total_spent_millions': 'spend (€m)'}
    ), use_container_width=True)

# ── TAB 2: Player Value by Age ────────────────────────────────
with tab2:
    st.subheader("Average Player Market Value by Age")

    df2 = query(f"""
        SELECT
            DATE_PART('year', AGE(mv.valuation_date, p.date_of_birth))::int AS age,
            ROUND(AVG(mv.value_euros) / 1e6, 2) AS avg_value_millions
        FROM   market_valuations mv
        JOIN   players p ON p.player_id = mv.player_id
        JOIN   clubs c ON c.club_id = p.current_club_id
        JOIN   competitions comp ON comp.competition_id = c.competition_id
        WHERE  p.date_of_birth IS NOT NULL
        AND    DATE_PART('year', AGE(mv.valuation_date, p.date_of_birth)) BETWEEN 16 AND 38
        AND    DATE_PART('year', mv.valuation_date::date) BETWEEN {season_range[0]} AND {season_range[1]}
        {league_clause()}
        GROUP  BY age
        ORDER  BY age
    """)

    peak = df2.loc[df2['avg_value_millions'].idxmax()]

    fig2 = go.Figure()
    fig2.add_trace(go.Scatter(
        x=df2['age'], y=df2['avg_value_millions'],
        mode='lines', fill='tozeroy',
        line=dict(color='#00e5a0', width=2.5),
        fillcolor='rgba(0,229,160,0.15)',
        name='Avg Value'
    ))
    fig2.add_trace(go.Scatter(
        x=[peak['age']], y=[peak['avg_value_millions']],
        mode='markers+text',
        marker=dict(color='#e55a00', size=10),
        text=[f"Peak: age {int(peak['age'])} · €{peak['avg_value_millions']}m"],
        textposition='top right',
        name='Peak'
    ))
    fig2.update_layout(
        xaxis_title='Player Age',
        yaxis_title='Avg Market Value (€m)',
        height=400,
        margin=dict(l=0, r=0, t=20, b=0),
        showlegend=False
    )
    st.plotly_chart(fig2, use_container_width=True)

# ── TAB 3: Profitability ──────────────────────────────────────
with tab3:
    st.subheader("Top 10 Clubs by Net Transfer Profit")

    df3 = query(f"""
        WITH club_sales AS (
            SELECT from_club_id AS club_id, SUM(fee_euros) AS total_income
            FROM   transfers
            WHERE  fee_euros IS NOT NULL AND from_club_id IS NOT NULL
            AND    season BETWEEN {season_range[0]} AND {season_range[1]}
            GROUP  BY from_club_id
        ),
        club_spend AS (
            SELECT to_club_id AS club_id, SUM(fee_euros) AS total_spend
            FROM   transfers
            WHERE  fee_euros IS NOT NULL AND to_club_id IS NOT NULL
            AND    season BETWEEN {season_range[0]} AND {season_range[1]}
            GROUP  BY to_club_id
        )
        SELECT
            c.name                                              AS club,
            comp.name                                           AS league,
            ROUND(COALESCE(cs.total_income, 0) / 1e6, 1)       AS income_millions,
            ROUND(COALESCE(sp.total_spend,  0) / 1e6, 1)       AS spend_millions,
            ROUND((COALESCE(cs.total_income, 0)
                 - COALESCE(sp.total_spend, 0)) / 1e6, 1)      AS net_profit_millions
        FROM   clubs        c
        JOIN   competitions comp ON comp.competition_id = c.competition_id
        LEFT   JOIN club_sales cs ON cs.club_id = c.club_id
        LEFT   JOIN club_spend sp ON sp.club_id = c.club_id
        WHERE  1=1 {league_clause()}
        ORDER  BY net_profit_millions DESC
        LIMIT  10
    """)

    df3['league_label'] = df3['league'].apply(league_label)
    df3['color'] = df3['net_profit_millions'].apply(lambda x: '#00e5a0' if x >= 0 else '#e55a00')

    fig3 = px.bar(
        df3, x='net_profit_millions', y='club',
        orientation='h',
        color='net_profit_millions',
        color_continuous_scale=[[0, '#e55a00'], [0.5, '#ffffff'], [1, '#00e5a0']],
        labels={'net_profit_millions': 'Net Profit (€m)', 'club': ''},
        text='net_profit_millions'
    )
    fig3.update_traces(texttemplate='€%{text}m', textposition='outside')
    fig3.update_layout(
        yaxis={'categoryorder': 'total ascending'},
        coloraxis_showscale=False,
        height=450,
        margin=dict(l=0, r=80, t=20, b=0)
    )
    st.plotly_chart(fig3, use_container_width=True)

# ── TAB 4: Seasonal Trends ────────────────────────────────────
with tab4:
    st.subheader("Season-by-Season Transfer Spend per League")

    df4 = query(f"""
        SELECT
            comp.name                           AS league,
            t.season,
            ROUND(SUM(t.fee_euros) / 1e6, 1)   AS total_spent_millions
        FROM   transfers    t
        JOIN   clubs        c    ON c.club_id          = t.to_club_id
        JOIN   competitions comp ON comp.competition_id = c.competition_id
        WHERE  t.fee_euros IS NOT NULL
        AND    t.season BETWEEN {season_range[0]} AND {season_range[1]}
        {league_clause()}
        GROUP  BY comp.name, t.season
        ORDER  BY league, season
    """)

    df4['league_label'] = df4['league'].apply(league_label)

    fig4 = px.line(
        df4, x='season', y='total_spent_millions',
        color='league_label',
        markers=True,
        color_discrete_map={"Premier League": "#00e5a0", "La Liga": "#e55a00"},
        labels={'total_spent_millions': 'Total Spend (€m)', 'season': 'Season', 'league_label': 'League'}
    )
    fig4.update_layout(
        height=400,
        margin=dict(l=0, r=0, t=20, b=0),
        xaxis=dict(tickmode='linear', dtick=1)
    )
    st.plotly_chart(fig4, use_container_width=True)

# ── TAB 5: Performance ────────────────────────────────────────
with tab5:
    st.subheader("Goals & Assists per 90 Minutes by Position")

    df5 = query(f"""
        SELECT
            p.position,
            ROUND(SUM(a.goals)::numeric
                  / NULLIF(SUM(a.minutes_played), 0) * 90, 2) AS goals_per_90,
            ROUND(SUM(a.assists)::numeric
                  / NULLIF(SUM(a.minutes_played), 0) * 90, 2) AS assists_per_90
        FROM   appearances a
        JOIN   players     p ON p.player_id = a.player_id
        JOIN   clubs       c ON c.club_id   = a.club_id
        JOIN   competitions comp ON comp.competition_id = c.competition_id
        WHERE  a.minutes_played >= 90
        AND    p.position NOT IN ('Unknown')
        AND    a.season BETWEEN {season_range[0]} AND {season_range[1]}
        {league_clause()}
        GROUP  BY p.position
        ORDER  BY goals_per_90 DESC
    """)

    fig5 = go.Figure()
    fig5.add_trace(go.Bar(
        name='Goals per 90',
        x=df5['position'], y=df5['goals_per_90'],
        marker_color='#00e5a0',
        text=df5['goals_per_90'], textposition='outside'
    ))
    fig5.add_trace(go.Bar(
        name='Assists per 90',
        x=df5['position'], y=df5['assists_per_90'],
        marker_color='#e55a00',
        text=df5['assists_per_90'], textposition='outside'
    ))
    fig5.update_layout(
        barmode='group',
        xaxis_title='Position',
        yaxis_title='Per 90 Minutes',
        height=400,
        margin=dict(l=0, r=0, t=20, b=0)
    )
    st.plotly_chart(fig5, use_container_width=True)
    st.dataframe(df5, use_container_width=True)
