"""
Laadscript voor de filmbibliotheek-databank.

Extract  : IMDb datasets (https://datasets.imdbws.com/) uit ./movies/
Transform: filteren, dedupliceren, synthetische sociale data genereren
Load     : bulk-insert in Oracle via oracledb

Draai eerst setup.sql (tabellen + sequences), daarna dit script.
"""

import csv
import gzip
import os
import random
from datetime import datetime, timedelta
from pathlib import Path

import oracledb
from faker import Faker

# ===== CONFIG =====

N_MOVIES = 100_000        # aantal films dat we behouden
MIN_VOTES = 1_000        # enkel films met minstens zoveel IMDb-stemmen
N_USERS = 300
N_FRIENDSHIPS = 1_000
N_COMMENTS = 5_000
N_RATINGS = 100_000
N_WATCH = 200_000

BATCH = 5_000            # rijen per executemany-batch
SEED = 42                # vaste seed -> zelfde synthetische data bij elke run

DATA_DIR = Path(__file__).resolve().parent / "movies"

DB_USER = os.environ.get("DB_USER", "dm_lucas")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "Lucas12!")
DB_DSN = os.environ.get("DB_DSN", "localhost:1521/XEPDB1")

# IMDb-categorie -> onze cast_role (CHECK: actor/director/writer)
CAST_ROLE = {
    "actor": "actor",
    "actress": "actor",
    "self": "actor",
    "director": "director",
    "writer": "writer",
}

NULL = r"\N"             # IMDb gebruikt \N voor onbekend

random.seed(SEED)
fake = Faker()
Faker.seed(SEED)


# ===== HULPFUNCTIES =====

def read_tsv(filename):
    """Leest een gezipte IMDb-TSV rij per rij (streaming, niet in het geheugen)."""
    path = DATA_DIR / filename
    if not path.exists():
        raise SystemExit(f"Bestand niet gevonden: {path}\nDownload het van https://datasets.imdbws.com/")
    with gzip.open(path, mode="rt", encoding="utf-8", newline="") as f:
        yield from csv.DictReader(f, delimiter="\t")


def to_int(value):
    """IMDb-waarde naar int, of None als ze onbekend is."""
    if value == NULL or value == "":
        return None
    try:
        return int(value)
    except ValueError:
        return None


def load_in_batches(cur, sql, rows, label):
    """Voegt rijen toe in batches i.p.v. rij per rij (veel sneller)."""
    total = 0
    buffer = []
    for row in rows:
        buffer.append(row)
        if len(buffer) >= BATCH:
            cur.executemany(sql, buffer)
            total += len(buffer)
            buffer.clear()
    if buffer:
        cur.executemany(sql, buffer)
        total += len(buffer)
    print(f"  {label:<16} {total:>8,} rijen")
    return total


# ===== EXTRACT =====

def extract_movies():
    """
    Kiest de N_MOVIES populairste films.

    Volgorde is belangrijk: eerst de kleine ratings-file om een set kandidaten
    te bouwen, pas daarna de grote basics-file filteren op die set. Zo houden
    we nooit miljoenen rijen in het geheugen.
    """
    print("Extract: title.ratings ...")
    votes = {}
    for row in read_tsv("title.ratings.tsv.gz"):
        n = to_int(row["numVotes"])
        if n is not None and n >= MIN_VOTES:
            votes[row["tconst"]] = n
    print(f"  {len(votes):,} titels met >= {MIN_VOTES:,} stemmen")

    print("Extract: title.basics ...")
    candidates = []
    for row in read_tsv("title.basics.tsv.gz"):
        if row["titleType"] != "movie":
            continue
        tconst = row["tconst"]
        if tconst not in votes:
            continue
        year = to_int(row["startYear"])
        runtime = to_int(row["runtimeMinutes"])
        if year is None or year <= 1888 or runtime is None or runtime <= 0:
            continue
        candidates.append({
            "tconst": tconst,
            "title": row["primaryTitle"][:300],
            "year": year,
            "runtime": runtime,
            "genres": [] if row["genres"] == NULL else row["genres"].split(","),
            "votes": votes[tconst],
        })

    candidates.sort(key=lambda m: m["votes"], reverse=True)
    movies = candidates[:N_MOVIES]
    print(f"  {len(movies):,} films behouden")
    return movies


def extract_cast(kept_tconst):
    """Leest de (grote) principals-file en houdt enkel rijen van onze films."""
    print("Extract: title.principals ...")
    links = set()          # (tconst, nconst, cast_role) -> ontdubbeld voor de PK
    needed_people = set()
    for row in read_tsv("title.principals.tsv.gz"):
        if row["tconst"] not in kept_tconst:
            continue
        role = CAST_ROLE.get(row["category"])
        if role is None:
            continue
        links.add((row["tconst"], row["nconst"], role))
        needed_people.add(row["nconst"])
    print(f"  {len(links):,} cast-koppelingen, {len(needed_people):,} personen nodig")
    return links, needed_people


def extract_people(needed_people):
    """Leest name.basics en houdt enkel de personen die in onze films voorkomen."""
    print("Extract: name.basics ...")
    people = []
    for row in read_tsv("name.basics.tsv.gz"):
        nconst = row["nconst"]
        if nconst not in needed_people:
            continue
        birth = to_int(row["birthYear"])
        if birth is not None and not (1850 <= birth <= 2027):
            birth = None                      # respecteert ck_people_birthyear
        people.append({
            "nconst": nconst,
            "name": row["primaryName"][:120],
            "birth_year": birth,
        })
    print(f"  {len(people):,} personen behouden")
    return people


# ===== TRANSFORM =====

def build_synthetic_users():
    users = []
    for user_id in range(1, N_USERS + 1):
        users.append((
            user_id,
            fake.unique.user_name()[:30],
            fake.unique.email()[:120],
            "not-a-real-hash",                # placeholder, nooit een echt wachtwoord
            fake.name()[:60],
            "Y" if random.random() < 0.95 else "N",
            fake.date_time_between(start_date="-3y"),
        ))
    return users


def build_synthetic_friendships(user_ids):
    statuses = ["pending", "accepted", "blocked"]
    weights = [0.2, 0.7, 0.1]
    pairs = set()
    while len(pairs) < N_FRIENDSHIPS:
        a, b = random.sample(user_ids, 2)     # sample -> nooit a == b (ck_friendships_diff)
        pairs.add((a, b))
    return [
        (a, b, random.choices(statuses, weights)[0], fake.date_time_between(start_date="-2y"))
        for a, b in pairs
    ]


def build_synthetic_comments(user_ids, movie_ids):
    """30% van de comments is een reply op een eerdere comment van dezelfde film."""
    comments = []
    per_movie = {}
    for comment_id in range(1, N_COMMENTS + 1):
        movie_id = random.choice(movie_ids)
        user_id = random.choice(user_ids)
        parent = None
        eerdere = per_movie.get(movie_id)
        if eerdere and random.random() < 0.30:
            parent = random.choice(eerdere)
        comments.append((
            comment_id,
            movie_id,
            user_id,
            parent,
            fake.sentence(nb_words=random.randint(6, 20))[:2000],
            fake.date_time_between(start_date="-2y"),
        ))
        per_movie.setdefault(movie_id, []).append(comment_id)
    return comments


def build_synthetic_ratings(user_ids, movie_ids):
    """Max 1 score per (user, film) -> respecteert pk_ratings."""
    seen = set()
    rows = []
    pogingen = 0
    max_pogingen = N_RATINGS * 5
    while len(rows) < N_RATINGS and pogingen < max_pogingen:
        pogingen += 1
        key = (random.choice(user_ids), random.choice(movie_ids))
        if key in seen:
            continue
        seen.add(key)
        rows.append((key[0], key[1], random.randint(1, 10),
                     fake.date_time_between(start_date="-2y")))
    return rows


def build_synthetic_watch_history(user_ids, movie_runtimes):
    movie_ids = list(movie_runtimes)
    rows = []
    for watch_id in range(1, N_WATCH + 1):
        movie_id = random.choice(movie_ids)
        volledig = movie_runtimes[movie_id] * 60
        seconden = random.randint(0, volledig)          # ck_watch_seconds: >= 0
        rows.append((
            watch_id,
            random.choice(user_ids),
            movie_id,
            fake.date_time_between(start_date="-2y"),
            seconden,
        ))
    return rows


# ===== LOAD =====

def clear_tables(cur):
    """Maakt de tabellen leeg in FK-volgorde, zodat het script herbruikbaar is."""
    print("Bestaande data verwijderen ...")
    cur.execute("DELETE FROM watch_history")
    cur.execute("DELETE FROM ratings")
    cur.execute("DELETE FROM comments WHERE parent_comment_id IS NOT NULL")  # kinderen eerst
    cur.execute("DELETE FROM comments")
    cur.execute("DELETE FROM movie_cast")
    cur.execute("DELETE FROM movie_genres")
    cur.execute("DELETE FROM friendships")
    cur.execute("DELETE FROM movies")
    cur.execute("DELETE FROM users")
    cur.execute("DELETE FROM people")
    cur.execute("DELETE FROM genres")


def reset_sequences(cur):
    """
    De ID's zijn hier in Python toegekend. Zet elke sequence voorbij de hoogste
    geladen waarde, zodat NEXTVAL in het notebook niet botst met bestaande rijen.
    """
    print("Sequences doorzetten ...")
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
        cur.execute(f"ALTER SEQUENCE {seq} RESTART START WITH {volgende}")
        print(f"  {seq:<16} -> {volgende:,}")


def main():
    # ---------- EXTRACT ----------
    movies = extract_movies()
    kept_tconst = {m["tconst"] for m in movies}
    cast_links, needed_people = extract_cast(kept_tconst)
    people = extract_people(needed_people)

    # ---------- TRANSFORM ----------
    print("Transform: ID's toekennen ...")

    genre_names = sorted({g for m in movies for g in m["genres"]})
    genre_id = {name: i for i, name in enumerate(genre_names, start=1)}
    movie_id = {m["tconst"]: i for i, m in enumerate(movies, start=1)}
    person_id = {p["nconst"]: i for i, p in enumerate(people, start=1)}

    kwaliteiten = ["SD", "HD", "4K"]
    kwaliteit_kans = [0.2, 0.65, 0.15]
    nu = datetime.now()

    genre_rows = [(genre_id[name], name) for name in genre_names]
    people_rows = [(person_id[p["nconst"]], p["nconst"], p["name"], p["birth_year"])
                   for p in people]
    movie_rows = [(
        movie_id[m["tconst"]],
        m["tconst"],
        m["title"],
        m["year"],
        m["runtime"],
        random.choices(kwaliteiten, kwaliteit_kans)[0],
        "available" if random.random() < 0.9 else "archived",
        nu - timedelta(days=random.randint(0, 730)),
    ) for m in movies]
    movie_genre_rows = [(movie_id[m["tconst"]], genre_id[g])
                        for m in movies for g in m["genres"]]
    cast_rows = [(movie_id[t], person_id[n], role)
                 for t, n, role in cast_links if n in person_id]

    print("Transform: synthetische sociale data ...")
    user_rows = build_synthetic_users()
    user_ids = [u[0] for u in user_rows]
    movie_ids = list(movie_id.values())
    movie_runtimes = {movie_id[m["tconst"]]: m["runtime"] for m in movies}

    friendship_rows = build_synthetic_friendships(user_ids)
    comment_rows = build_synthetic_comments(user_ids, movie_ids)
    rating_rows = build_synthetic_ratings(user_ids, movie_ids)
    watch_rows = build_synthetic_watch_history(user_ids, movie_runtimes)

    # ---------- LOAD ----------
    print(f"Verbinden met {DB_DSN} als {DB_USER} ...")
    with oracledb.connect(user=DB_USER, password=DB_PASSWORD, dsn=DB_DSN) as conn:
        with conn.cursor() as cur:
            clear_tables(cur)

            print("Laden (ouders eerst, dan de koppeltabellen) ...")
            load_in_batches(cur,
                "INSERT INTO genres (genre_id, name) VALUES (:1, :2)",
                genre_rows, "genres")
            load_in_batches(cur,
                "INSERT INTO people (person_id, imdb_id, full_name, birth_year) "
                "VALUES (:1, :2, :3, :4)",
                people_rows, "people")
            load_in_batches(cur,
                "INSERT INTO users (user_id, username, email, password_hash, "
                "display_name, is_active, created_at) VALUES (:1, :2, :3, :4, :5, :6, :7)",
                user_rows, "users")
            load_in_batches(cur,
                "INSERT INTO movies (movie_id, imdb_id, title, release_year, "
                "runtime_min, quality, status, added_at) "
                "VALUES (:1, :2, :3, :4, :5, :6, :7, :8)",
                movie_rows, "movies")
            load_in_batches(cur,
                "INSERT INTO movie_genres (movie_id, genre_id) VALUES (:1, :2)",
                movie_genre_rows, "movie_genres")
            load_in_batches(cur,
                "INSERT INTO movie_cast (movie_id, person_id, cast_role) "
                "VALUES (:1, :2, :3)",
                cast_rows, "movie_cast")
            load_in_batches(cur,
                "INSERT INTO friendships (user_id, friend_id, status, requested_at) "
                "VALUES (:1, :2, :3, :4)",
                friendship_rows, "friendships")
            load_in_batches(cur,
                "INSERT INTO comments (comment_id, movie_id, user_id, "
                "parent_comment_id, body, created_at) VALUES (:1, :2, :3, :4, :5, :6)",
                comment_rows, "comments")
            load_in_batches(cur,
                "INSERT INTO ratings (user_id, movie_id, score, rated_at) "
                "VALUES (:1, :2, :3, :4)",
                rating_rows, "ratings")
            load_in_batches(cur,
                "INSERT INTO watch_history (watch_id, user_id, movie_id, "
                "watched_at, seconds_watched) VALUES (:1, :2, :3, :4, :5)",
                watch_rows, "watch_history")

            reset_sequences(cur)

        conn.commit()

    print("Klaar.")


if __name__ == "__main__":
    main()
