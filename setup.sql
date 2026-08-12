-- ===== 0 SETUP =====

-- alle output vanaf hier wordt weggeschreven
SPOOL output/filmlib_output.txt
-- toont tijd dat nodig is per statement (nodig later)
SET TIMING ON
-- toont output
SET SERVEROUTPUT ON
ALTER SESSION SET NLS_LENGTH_SEMANTICS = CHAR;
ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-RR';
ALTER SESSION SET NLS_LANGUAGE = 'ENGLISH';


-- ===== 1 OPSCHONEN =====

-- Alle tabellen droppen
DROP TABLE watch_history;
DROP TABLE ratings;
DROP TABLE comments;
DROP TABLE movie_cast;
DROP TABLE movie_genres;
DROP TABLE friendships;
DROP TABLE movies;
DROP TABLE users;
DROP TABLE people;
DROP TABLE genres;

-- ===== 2 DDL =====
-- ERD ==> in ERD folder of betere view hier --> https://dbdiagram.io/d/FilmBibliotheek-6976329bbd82f5fce2892e35
CREATE TABLE genres (
    genre_id NUMBER,
    name VARCHAR2(40) CONSTRAINT uq_genres_name UNIQUE NOT NULL,
    CONSTRAINT pk_genres PRIMARY KEY (genre_id)
);

CREATE TABLE people (
    person_id NUMBER,
    imdb_id VARCHAR2(12) CONSTRAINT uq_people_imdb UNIQUE,
    full_name VARCHAR2(120) NOT NULL,
    birth_year NUMBER(4) CONSTRAINT ck_people_birthyear CHECK (birth_year BETWEEN 1850 AND 2027),
    CONSTRAINT pk_people PRIMARY KEY (person_id)
);

-- out-of-line pk
CREATE TABLE users (
    user_id NUMBER,
    username VARCHAR2(30) CONSTRAINT uq_users_username UNIQUE NOT NULL,
    email VARCHAR2(120) CONSTRAINT uq_users_email UNIQUE NOT NULL,
    password_hash VARCHAR2(120) NOT NULL,
    display_name VARCHAR2(60),
    is_active CHAR(1) DEFAULT 'Y' CONSTRAINT ck_users_active CHECK (is_active IN ('Y', 'N')),
    created_at DATE DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_users PRIMARY KEY (user_id)
);

CREATE TABLE movies (
    movie_id NUMBER,
    imdb_id VARCHAR2(12) CONSTRAINT uq_movies_imdb UNIQUE NOT NULL,
    title VARCHAR2(300) NOT NULL,
    release_year NUMBER(4) CONSTRAINT ck_movies_year CHECK (release_year > 1888),
    runtime_min NUMBER(4) CONSTRAINT ck_movies_runtime CHECK (runtime_min > 0),
    quality VARCHAR2(4) DEFAULT 'HD' CONSTRAINT ck_movies_quality CHECK (quality IN ('SD', 'HD', '4K')),
    status VARCHAR2(10) DEFAULT 'available' CONSTRAINT ck_movies_status CHECK (status IN ('available', 'archived')),
    added_at DATE DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_movies PRIMARY KEY (movie_id)
);

-- inline pk/fk
CREATE TABLE friendships (
    user_id NUMBER CONSTRAINT fk_friendships_user REFERENCES users(user_id),
    friend_id NUMBER CONSTRAINT fk_friendships_friend REFERENCES users(user_id),
    status VARCHAR2(10) default 'pending' CONSTRAINT ck_friendships_status CHECK (status IN ('pending', 'accepted', 'blocked')),
    requested_at DATE DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_friendships PRIMARY KEY (user_id, friend_id),
    -- user kan kan geen vriend zijn van zichzelf
    CONSTRAINT ck_friendships_diff CHECK (user_id <> friend_id)
);

CREATE TABLE movie_genres (
    movie_id NUMBER CONSTRAINT fk_moviegenres_movie REFERENCES movies(movie_id),
    genre_id NUMBER CONSTRAINT fk_moviegenres_genre REFERENCES genres(genre_id),
    CONSTRAINT pk_moviegenres PRIMARY KEY (movie_id, genre_id)
);

CREATE TABLE movie_cast (
    movie_id NUMBER CONSTRAINT fk_moviecast_movie REFERENCES movies(movie_id),
    person_id NUMBER CONSTRAINT fk_moviecast_person REFERENCES people(person_id),
    cast_role VARCHAR2(20) CONSTRAINT ck_moviecast_role CHECK (cast_role IN ('actor', 'director', 'writer')),
    CONSTRAINT pk_moviecast PRIMARY KEY (movie_id, person_id, cast_role)
);

CREATE TABLE comments (
    comment_id NUMBER,
    movie_id NUMBER NOT NULL CONSTRAINT fk_comments_movie REFERENCES movies(movie_id),
    user_id NUMBER NOT NULL CONSTRAINT fk_comments_user REFERENCES users(user_id),
    parent_comment_id NUMBER CONSTRAINT fk_comments_parent REFERENCES comments(comment_id),
    body VARCHAR2(2000) NOT NULL,
    created_at DATE DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_comments PRIMARY KEY (comment_id)
);

CREATE TABLE ratings (
    user_id NUMBER CONSTRAINT fk_ratings_user REFERENCES users(user_id),
    movie_id NUMBER CONSTRAINT fk_ratings_movie REFERENCES movies(movie_id),
    score NUMBER(2) NOT NULL CONSTRAINT ck_ratings_score CHECK (score BETWEEN 1 AND 10),
    rated_at DATE DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_ratings PRIMARY KEY (user_id, movie_id)
);

CREATE TABLE watch_history (
    watch_id NUMBER,
    user_id NUMBER NOT NULL CONSTRAINT fk_watch_user REFERENCES users(user_id),
    movie_id NUMBER NOT NULL CONSTRAINT fk_watch_movie REFERENCES movies(movie_id),
    watched_at DATE DEFAULT SYSDATE NOT NULL,
    seconds_watched NUMBER CONSTRAINT ck_watch_seconds CHECK (seconds_watched >= 0),
    CONSTRAINT pk_watch_history PRIMARY KEY (watch_id)
);


-- ===== 3 COMMENTS =====

COMMENT ON TABLE genres IS 'Lijst van filmgenres';
COMMENT ON COLUMN genres.name IS 'Naam van het genre, uniek';

COMMENT ON TABLE people IS 'Acteurs, regisseurs en schrijvers';
COMMENT ON COLUMN people.imdb_id IS 'IMDb id (nm...), uniek';
COMMENT ON COLUMN people.birth_year IS 'Geboortejaar, tussen 1850 en 2027';

COMMENT ON TABLE users IS 'Gebruikers van de filmbibliotheek';
COMMENT ON COLUMN users.username IS 'Loginnaam, uniek';
COMMENT ON COLUMN users.email IS 'E-mailadres, uniek';
COMMENT ON COLUMN users.password_hash IS 'Gehasht wachtwoord, nooit plaintext';
COMMENT ON COLUMN users.is_active IS 'Y = actief account, N = geblokkeerd/gedeactiveerd';

COMMENT ON TABLE movies IS 'Alle films in de bibliotheek';
COMMENT ON COLUMN movies.imdb_id IS 'IMDb id (tt...), uniek';
COMMENT ON COLUMN movies.release_year IS 'Jaar van uitgave, moet na 1888 zijn';
COMMENT ON COLUMN movies.runtime_min IS 'Speelduur in minuten';
COMMENT ON COLUMN movies.quality IS 'Beschikbare kwaliteit: SD, HD of 4K';
COMMENT ON COLUMN movies.status IS 'available of archived';

COMMENT ON TABLE friendships IS 'Vriendschappen tussen users (aanvrager -> ontvanger)';
COMMENT ON COLUMN friendships.user_id IS 'User die de aanvraag stuurt';
COMMENT ON COLUMN friendships.friend_id IS 'User die de aanvraag krijgt';
COMMENT ON COLUMN friendships.status IS 'pending, accepted of blocked';

COMMENT ON TABLE movie_genres IS 'Koppeltabel film <-> genre';

COMMENT ON TABLE movie_cast IS 'Koppeltabel film <-> persoon met zijn rol';
COMMENT ON COLUMN movie_cast.cast_role IS 'actor, director of writer';

COMMENT ON TABLE comments IS 'Reacties van users op films, kunnen genest zijn';
COMMENT ON COLUMN comments.parent_comment_id IS 'Verwijst naar de comment waarop geantwoord wordt, NULL = hoofdcomment';
COMMENT ON COLUMN comments.body IS 'Tekst van de reactie';

COMMENT ON TABLE ratings IS 'Score die een user aan een film geeft, 1 per film';
COMMENT ON COLUMN ratings.score IS 'Score van 1 tot 10';

COMMENT ON TABLE watch_history IS 'Kijkgeschiedenis, 1 rij per keer kijken';
COMMENT ON COLUMN watch_history.watched_at IS 'Wanneer er gekeken is';
COMMENT ON COLUMN watch_history.seconds_watched IS 'Aantal seconden effectief bekeken';

-- ===== 4 SEQUENCES 