SPOOL output/bewerkingen_output.txt
SET TIMING ON
-- toont output
SET SERVEROUTPUT ON
ALTER SESSION SET NLS_LENGTH_SEMANTICS = CHAR;
ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-RR';
ALTER SESSION SET NLS_LANGUAGE = 'ENGLISH';

-- verwijder als het al bestaat 
DELETE FROM movie_genres 
WHERE movie_id IN (SELECT movie_id FROM movies WHERE imdb_id = 'tt12030303');

DELETE FROM movie_cast 
WHERE movie_id IN (SELECT movie_id FROM movies WHERE imdb_id = 'tt12030303');

-- 2. Delete from parent tables next
DELETE FROM people 
WHERE imdb_id = 'tt12030303';

DELETE FROM movies 
WHERE imdb_id = 'tt12030303';

-- ===== 1 DML =====
-- test film toevoegen dmv seq
INSERT ALL
  INTO movies (movie_id, imdb_id, title) VALUES (seq_movie_id.NEXTVAL, 'tt12030303' , 'test_film')
  -- genre aan koppelen
  INTO movie_genres (movie_id, genre_id) VALUES (seq_movie_id.CURRVAL, 2)
  -- acteur maken
  INTO people (person_id, imdb_id, full_name) VALUES (seq_person_id.NEXTVAL, 'tt12030303', 'Lucas Huygen')
  -- movie cast nu
  INTO movie_cast (movie_id, person_id, cast_role) VALUES (seq_movie_id.CURRVAL, seq_person_id.CURRVAL, 'actor')
SELECT * FROM dual;

SELECT seq_movie_id.CURRVAL FROM dual;
SELECT *
FROM movies m
JOIN movie_genres mg ON m.movie_id = mg.movie_id
JOIN movie_cast mc ON m.movie_id = mc.movie_id
JOIN people p ON mc.person_id = p.person_id
WHERE m.imdb_id = 'tt12030303';

-- ===== 2 DML =====
-- status updaten van de test film
UPDATE movies SET status = 'archived' WHERE title = 'test_film';
SELECT status FROM movies WHERE title = 'test_film';

-- een test comment deleten
DELETE FROM comments WHERE comment_id = 1;
SELECT * FROM comments;

-- ===== 3 TCL =====
-- nieuwe film + zijn genre invoegen en daarna savepoint plaatsen


