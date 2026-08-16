SPOOL output/performance_output.txt
SET TIMING ON
-- toont output
SET SERVEROUTPUT ON
ALTER SESSION SET NLS_LENGTH_SEMANTICS = CHAR;
ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-RR';
ALTER SESSION SET NLS_LANGUAGE = 'ENGLISH';

-- ===== 1 view =====
-- view die film titel, zijn genres, gemiddelde score, aantal comments geeft
CREATE OR REPLACE view v_movie_overview AS
SELECT m.title, g.name AS genre, ra.score, COUNT(co.comment_id) AS aantal_comments
FROM movies m
JOIN movie_genres mg ON m.movie_id = mg.movie_id
JOIN genres g ON g.genre_id = mg.genre_id
JOIN ratings ra ON m.movie_id = ra.movie_id
JOIN comments co ON m.movie_id = co.movie_id
GROUP BY m.title, g.name, ra.score;

SELECT * FROM v_movie_overview FETCH FIRST 3 ROWS ONLY;

-- ===== 2 beveiliging views =====
-- view van de users read only (user_id, username, display name, created at)
CREATE OR REPLACE view v_public_users AS
SELECT user_id, username, display_name, created_at
FROM users
WHERE UPPER(is_active) = 'Y'
WITH READ ONLY;

-- beschikbare films
CREATE OR REPLACE view v_available_movies AS
SELECT *
FROM movies
WHERE UPPER(status) = 'AVAILABLE'
WITH CHECK OPTION;

-- testen
DESC v_public_users; -- geen email / pw
UPDATE v_public_users SET username='x' WHERE ROWNUM=1; -- faalt, read only
INSERT INTO v_available_movies (movie_id, imdb_id, status, title) VALUES (seq_movie_id.NEXTVAL, 'tt12334Fttt', 'archived', 'testtting');

-- ===== 3 indexen =====
CREATE INDEX ix_movies_title ON movies(title);
CREATE BITMAP INDEX bx_movies_quality ON movies(quality);
CREATE INDEX fx_movies_uppertitle ON movies(UPPER(title));
CREATE INDEX ix_watch_user_movie ON watch_history(user_id, movie_id);
CREATE INDEX ix_comments_movie ON comments(movie_id);
CREATE INDEX ix_ratings_movie ON ratings(movie_id);

-- ===== 4 bewijs snelheidsverschil =====
ALTER INDEX ix_watch_user_movie INVISIBLE;
ALTER INDEX PK_USERS INVISIBLE;
-- Plan tonen ZONDER index
EXPLAIN PLAN FOR SELECT u.user_id,
       (SELECT COUNT(*) FROM watch_history w WHERE w.user_id = u.user_id) AS kijkbeurten
FROM   users u;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);   -- TABLE ACCESS FULL

-- Tijd meten
SELECT u.user_id,
       (SELECT COUNT(*) FROM watch_history w WHERE w.user_id = u.user_id) AS kijkbeurten
FROM   users u;

ALTER INDEX ix_watch_user_movie VISIBLE;
ALTER INDEX PK_USERS VISIBLE;

-- Plan tonen MET index
EXPLAIN PLAN FOR SELECT u.user_id,
       (SELECT COUNT(*) FROM watch_history w WHERE w.user_id = u.user_id) AS kijkbeurten
FROM   users u;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);        -- -> INDEX RANGE SCAN

-- tijd opnieuw meten
SELECT u.user_id,
       (SELECT COUNT(*) FROM watch_history w WHERE w.user_id = u.user_id) AS kijkbeurten
FROM   users u;


-- voorbeeld 2
-- without index
ALTER INDEX ix_movies_title INVISIBLE

EXPLAIN PLAN FOR SELECT * FROM movies ORDER BY title FETCH FIRST 20 ROWS ONLY;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

SELECT * FROM movies ORDER BY title FETCH FIRST 20 ROWS ONLY;

-- with index
ALTER INDEX ix_movies_title VISIBLE

EXPLAIN PLAN FOR SELECT * FROM movies ORDER BY title FETCH FIRST 20 ROWS ONLY;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

SELECT * FROM movies ORDER BY title FETCH FIRST 20 ROWS ONLY;

-- voorbeeld 3

