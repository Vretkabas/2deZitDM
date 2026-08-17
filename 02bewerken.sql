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
SELECT status FROM movies WHERE title = 'test_film' FETCH FIRST 10 ROWS ONLY;

-- een test comment deleten
DELETE FROM comments WHERE comment_id = 1;
SELECT * FROM comments FETCH FIRST 10 ROWS ONLY;

-- ===== 3 TCL =====
-- nieuwe film + zijn genre invoegen en daarna savepoint plaatsen
INSERT ALL
    INTO movies (movie_id, imdb_id, title) VALUES (seq_movie_id.NEXTVAL, 'tt12030333', 'TCL_FILM')
    INTO movie_genres (movie_id, genre_id) VALUES (seq_movie_id.CURRVAL, 2)
SELECT * FROM dual;
SAVEPOINT na_film;

-- fout simuleren
INSERT INTO genres (genre_id, name) VALUES (seq_genre_id.NEXTVAL, 'oeps');

-- terug naar goede deel foutje weg
ROLLBACK TO na_film;
-- commit goede deel
COMMIT;

-- controleren of genres gemaakt werd
SELECT * FROM genres WHERE name = 'oeps';
-- movie werd wel gemaakt
SELECT * 
FROM movies m
JOIN movie_genres mg ON m.movie_id = mg.movie_id
WHERE m.title = 'TCL_FILM';

-- ===== 4 DQL: JOINS =====
-- alle films met hun genre en cast (inner join)
SELECT m.title, m.quality, g.name AS genre, mc.cast_role AS role, p.full_name AS name
FROM movies m
JOIN movie_genres mg ON m.movie_id = mg.movie_id
JOIN genres g ON mg.genre_id = g.genre_id
JOIN movie_cast mc ON m.movie_id = mc.movie_id
JOIN people p ON p.person_id = mc.person_id
FETCH FIRST 10 ROWS ONLY;

-- alle films en ook comments ookal null (left join)
SELECT * 
FROM movies m
LEFT JOIN comments co ON co.movie_id = m.movie_id
FETCH FIRST 10 ROWS ONLY;

-- zelfde maar right join
SELECT * 
FROM comments co
RIGHT JOIN movies m ON m.movie_id = co.movie_id
FETCH FIRST 10 ROWS ONLY;

SPOOL OFF;