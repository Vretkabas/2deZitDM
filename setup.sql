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
TRUNCATE TABLE genres;  -- tabel leegmaken
DROP TABLE watch_history;
DROP TABLE ratings;
DROP TABLE comments;
DROP TABLE movies_cast;
DROP TABLE movie_genres;
DROP TABLE friendships;
DROP TABLE movies;
DROP TABLE users;
DROP TABLE people;
DROP TABLE genres;

-- ===== 2 DDL =====
-- ERD ==> in ERD folder of betere view hier --> https://dbdiagram.io/d/FilmBibliotheek-6976329bbd82f5fce2892e35
CREATE TABLE genres (
    genre_id NUMBER(3),
    name VARCHAR2(40) UNIQUE NOT NULL
);

CREATE TABLE people (
    person_id NUMBER(3),
    imdb_id VARCHAR2(12) UNIQUE,
    full_name VARCHAR2(120) NOT NULL,
    birth_year NUMBER(4) CHECK (birth_year BETWEEN 1850 AND 2027)
);