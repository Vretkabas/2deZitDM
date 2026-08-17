SPOOL output/performance_output.txt
SET TIMING ON
-- toont output
SET SERVEROUTPUT ON
ALTER SESSION SET NLS_LENGTH_SEMANTICS = CHAR;
ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-RR';
ALTER SESSION SET NLS_LANGUAGE = 'ENGLISH';

-- ===== 1 view =====
-- view die film titel, zijn genres, gemiddelde score, aantal comments geeft
CREATE OR REPLACE VIEW v_movie_overview AS
SELECT m.movie_id,
       m.title,
       m.release_year,
       (SELECT LISTAGG(g.name, ', ') WITHIN GROUP (ORDER BY g.name)
          FROM movie_genres mg
          JOIN genres g ON g.genre_id = mg.genre_id
         WHERE mg.movie_id = m.movie_id)   AS genres,
       (SELECT ROUND(AVG(ra.score), 2)
          FROM ratings ra
         WHERE ra.movie_id = m.movie_id)   AS gem_score,
       (SELECT COUNT(*)
          FROM comments co
         WHERE co.movie_id = m.movie_id)   AS aantal_comments
FROM movies m;
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
-- eerst indexen droppen
DROP INDEX ix_movies_title;
DROP INDEX bx_movies_quality;
DROP INDEX fx_movies_uppertitle;
DROP INDEX ix_watch_user_movie;
DROP INDEX ix_comments_movie;
DROP INDEX ix_ratings_movie;

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
ALTER INDEX ix_movies_title INVISIBLE;

EXPLAIN PLAN FOR SELECT * FROM movies ORDER BY title FETCH FIRST 20 ROWS ONLY;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

SELECT * FROM movies ORDER BY title FETCH FIRST 20 ROWS ONLY;

-- with index
ALTER INDEX ix_movies_title VISIBLE;

EXPLAIN PLAN FOR SELECT * FROM movies ORDER BY title FETCH FIRST 20 ROWS ONLY;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

SELECT * FROM movies ORDER BY title FETCH FIRST 20 ROWS ONLY;

-- voorbeeld 3: waarom ik geen index op status maak bijvoorbeeld
SELECT status, COUNT(*) FROM movies GROUP BY status;   -- ~90% available, ~10% archived

DROP INDEX ix_movies_status;
CREATE INDEX ix_movies_status ON movies(status);

EXPLAIN PLAN FOR SELECT * FROM movies WHERE status = 'archived';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);     -- een full table scan

DROP INDEX ix_movies_status;


-- ===== 5 users, priv en roles =====
-- Eerst droppen
DROP USER filmlib_friend;
DROP ROLE role_viewer;
DROP ROLE role_contributor;

CREATE USER filmlib_friend IDENTIFIED BY Geheim123;
GRANT CREATE SESSION TO filmlib_friend;

-- vriend mag select op mijn publieke views + movies, insert op comments/ratings. 
CREATE ROLE role_viewer;
BEGIN
  FOR v IN (SELECT view_name FROM user_views
            WHERE view_name IN ('V_MOVIE_OVERVIEW', 'V_PUBLIC_USERS', 'V_AVAILABLE_MOVIES')) LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT ON ' || v.view_name || ' TO role_viewer';
    DBMS_OUTPUT.PUT_LINE('grant op ' || v.view_name);
  END LOOP;
END;
/
-- select op movies tabel
GRANT SELECT ON movies TO role_viewer;

SELECT grantee, table_name, privilege
FROM   user_tab_privs
WHERE  grantee = 'ROLE_VIEWER';

-- nieuwe rol contributor insert op comments/ratings
CREATE ROLE role_contributor;
GRANT INSERT ON ratings TO role_contributor;
GRANT INSERT ON comments TO role_contributor;
GRANT SELECT on seq_comment_id TO role_contributor;

SELECT grantee, table_name, privilege
FROM user_tab_privs 
WHERE grantee = 'ROLE_CONTRIBUTOR';

GRANT SELECT ON v_movie_overview TO filmlib_friend WITH GRANT OPTION;
GRANT role_contributor TO filmlib_friend;
GRANT role_viewer TO filmlib_friend;

SPOOL OFF;