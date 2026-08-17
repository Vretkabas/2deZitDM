"""
Genereert een SQL-dump met INSERT-statements van de volledige filmbibliotheek.

Resultaat: 2deZitDM/data_dump.sql  -- draaibaar met @data_dump.sql na 01setup.sql

Waarom INSERT-statements en geen Data Pump: een .dmp-bestand is versiegebonden
(een 21c-dump importeert niet in 19c), terwijl INSERT-statements op elke Oracle
draaien zonder extra tooling.
"""

import os
from datetime import datetime
from pathlib import Path

import oracledb

DB_USER = os.environ.get("DB_USER", "dm_lucas")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "Lucas12!")
DB_DSN = os.environ.get("DB_DSN", "localhost:1521/XEPDB1")

OUTFILE = Path(__file__).resolve().parent.parent / "data_dump.sql"

COMMIT_EVERY = 1_000       # COMMIT invoegen om de zoveel rijen

# Tabellen in foreign-key-volgorde: ouders eerst, anders faalt de import.
TABLES = [
    "genres",
    "people",
    "users",
    "movies",
    "movie_genres",
    "movie_cast",
    "friendships",
    "comments",
    "ratings",
    "watch_history",
]

DATE_FMT = "YYYY-MM-DD HH24:MI:SS"


def sql_value(value):
    """Zet een Python-waarde om naar een letterlijke SQL-waarde."""
    if value is None:
        return "NULL"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, datetime):
        return f"TO_DATE('{value:%Y-%m-%d %H:%M:%S}','{DATE_FMT}')"
    # string: enkele quotes verdubbelen
    return "'" + str(value).replace("'", "''") + "'"


def export_table(cur, out, table):
    cur.execute(f"SELECT * FROM {table}")
    columns = [d[0].lower() for d in cur.description]
    collist = ", ".join(columns)

    out.write(f"\n-- ===== {table} =====\n")

    count = 0
    while True:
        rows = cur.fetchmany(1_000)
        if not rows:
            break
        for row in rows:
            values = ", ".join(sql_value(v) for v in row)
            out.write(f"INSERT INTO {table} ({collist}) VALUES ({values});\n")
            count += 1
            if count % COMMIT_EVERY == 0:
                out.write("COMMIT;\n")
    out.write("COMMIT;\n")
    print(f"  {table:<16} {count:>8,} rijen")
    return count


def main():
    print(f"Verbinden met {DB_DSN} als {DB_USER} ...")
    with oracledb.connect(user=DB_USER, password=DB_PASSWORD, dsn=DB_DSN) as conn:
        with conn.cursor() as cur, open(OUTFILE, "w", encoding="utf-8") as out:
            out.write("-- Datadump filmbibliotheek\n")
            out.write("-- Draai dit NA 01setup.sql (tabellen moeten bestaan).\n")
            out.write("-- Tabellen staan in foreign-key-volgorde.\n\n")

            # SET DEFINE OFF is essentieel: filmtitels bevatten '&' (bv. "Fire & Ice")
            # en SQL*Plus zou die anders als substitutievariabele interpreteren.
            out.write("SET DEFINE OFF\n")
            out.write("SET FEEDBACK OFF\n")
            out.write("ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';\n")

            totaal = 0
            for table in TABLES:
                totaal += export_table(cur, out, table)

            # Sequences doorzetten voorbij de hoogste geladen id
            out.write("\n-- ===== sequences bijzetten =====\n")
            for seq, table, column in [
                ("seq_genre_id", "genres", "genre_id"),
                ("seq_person_id", "people", "person_id"),
                ("seq_movie_id", "movies", "movie_id"),
                ("seq_user_id", "users", "user_id"),
                ("seq_comment_id", "comments", "comment_id"),
                ("seq_watch_id", "watch_history", "watch_id"),
            ]:
                cur.execute(f"SELECT NVL(MAX({column}), 0) + 1 FROM {table}")
                volgende = cur.fetchone()[0]
                out.write(f"ALTER SEQUENCE {seq} RESTART START WITH {volgende};\n")

            out.write("\nSET FEEDBACK ON\n")
            out.write("COMMIT;\n")

    grootte_mb = OUTFILE.stat().st_size / 1024 / 1024
    print(f"\nKlaar: {OUTFILE}")
    print(f"  {totaal:,} rijen, {grootte_mb:.1f} MB")
    print("  (SQL-tekst comprimeert ongeveer 10:1 in een ZIP)")


if __name__ == "__main__":
    main()
