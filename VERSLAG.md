# Filmbibliotheek — Data Management werkstuk

**Lucas Huygen** · tweede zittijd · Oracle Database XE 21c

---

## 1. Wat is dit?

Een Oracle-databank voor een **gedeelde filmbibliotheek**: een verzameling films die je op een thuisserver zou draaien en deelt met vrienden. Vrienden kunnen kijken, scoren en reageren op elkaars comments.

Ik koos dit thema omdat het elk cursusconcept toont. Het duidelijkste voorbeeld is beveiliging: omdat de bibliotheek gedeeld wordt met vrienden, is er een echte reden om rollen en rechten te definiëren.

---

## 2. De databank repliceren

| Stap | Bestand | Als wie | Wat |
|---|---|---|---|
| 1 | `01setup.sql` | `dm_lucas` | Tabellen, constraints, comments, sequences |
| 2 | `python_films/load_films.py` | — | Vult de databank (of gebruik `02data.sql`) |
| 3 | `02bewerken.sql` | `dm_lucas` | DML, transacties, queries |
| 4 | `03performance.sql` | `dm_lucas` | Views, indexen, performance, security |

Draaien via SQL\*Plus vanuit de map `2deZitDM`:

```
sqlplus dm_lucas@localhost:1521/XEPDB1
@01setup.sql
```

De relatieve paden in `SPOOL` verwachten dat je vanuit die map start en dat de map `output/` bestaat.

---

## 3. Het datamodel

Tien tabellen. De ERD staat in de map `ERD/` en online op dbdiagram.io. --> https://dbdiagram.io/d/FilmBibliotheek-6976329bbd82f5fce2892e35

### Kernentiteiten
`movies`, `people`, `genres`, `users`

### Koppeltabellen (M:N)
`movie_genres`, `movie_cast`, `friendships`, `ratings`

### Detailtabellen
`comments`, `watch_history`

### Waarom deze keuzes

**Eén `people`-tabel in plaats van `acteurs` + `regisseurs`.**
Mijn eerste ontwerp had aparte tabellen. Dat is fout, want mensen doen meerdere dingen: Clint Eastwood regisseert én acteert. Met gescheiden tabellen staat dezelfde persoon twee keer in de databank met twee verschillende id's ==> redundantie. Nu bepaalt de kolom `movie_cast.cast_role` de rol (`actor`, `director`, `writer`). Een rol toevoegen kost één waarde in een CHECK-constraint in plaats van een nieuwe tabel plus koppeltabel.

**Self-referencing foreign key op `comments`.**
`parent_comment_id` verwijst naar `comments.comment_id` in dezelfde tabel. Zo kunnen reacties genest worden (een reply op een reply) zonder een aparte tabel. `NULL` betekent "hoofdcomment". (zelfde als emp tabel in cursus)

**Self-referencing M:N op `friendships`.**
Beide kolommen (`user_id`, `friend_id`) verwijzen naar `users`. De samengestelde primaire sleutel `(user_id, friend_id)` verhindert dubbele vriendschapsverzoeken, en `CHECK (user_id <> friend_id)` verhindert dat iemand vriend van zichzelf wordt.

**`NUMBER` zonder precisie voor id-kolommen.**
Mijn eerste versie gebruikte `NUMBER(3)`. Dat loopt over bij 999 rijen, terwijl `watch_history` er 200.000 heeft. Id-kolommen krijgen nu gewoon `NUMBER`.

**`NLS_LENGTH_SEMANTICS = CHAR`.**
Filmtitels bevatten accenten en niet-Latijnse tekens (*Amélie*, *千と千尋の神隠し*). Met bytesemantiek zou `VARCHAR2(300)` betekenen: 300 *bytes*, waardoor zulke titels afgekapt raken.

---

## 4. Toegepaste concepten

### DDL en constraints — `01setup.sql`

Elke constraint heeft een expliciete naam volgens de conventie `pk_<tabel>`, `fk_<tabel>_<doel>`, `ck_<tabel>_<kolom>`, `uq_<tabel>_<kolom>`.

De `DROP TABLE`-volgorde is het omgekeerde van de aanmaakvolgorde: eerst de tabellen die een foreign key bezitten, dan de tabellen waarnaar verwezen wordt. Anders faalt het script met `ORA-02449`.

Gebruikte constraint-types: `PRIMARY KEY` (enkelvoudig en samengesteld), `FOREIGN KEY` (inline en out-of-line, inclusief self-referencing), `UNIQUE`, `NOT NULL`, `CHECK` (waardenlijst, bereik, en een vergelijking tussen twee kolommen), en `DEFAULT`.

### Sequences — `01setup.sql`

`NEXTVAL` verhoogt en geeft de nieuwe waarde; `CURRVAL` geeft de laatst uitgedeelde waarde **binnen dezelfde sessie**.

Ik gebruik `CURRVAL` om een detailrij te koppelen aan de masterrij die ik net invoegde, zonder het gegenereerde id te moeten opzoeken.

**Beperking die ik tegenkwam:** `NEXTVAL` en `CURRVAL` mogen niet overal staan. In de `WHERE`-clausule van een `SELECT` of in een subquery geeft Oracle `ORA-02287`.
### DML en TCL — `02bewerken.sql`

Een `INSERT ALL` voegt in één statement een film, zijn genre, een persoon en de cast-koppeling toe, met `NEXTVAL` voor de nieuwe id's en `CURRVAL` om ze aan elkaar te knopen.

De transactiedemo toont dat `SAVEPOINT` gedeeltelijk terugrollen mogelijk maakt: na het invoegen van een film plaats ik een savepoint, voeg dan iets ongewenst toe, en rol met `ROLLBACK TO na_film` enkel dat laatste stuk terug. De `COMMIT` daarna maakt de film definitief. De controlequeries erna bewijzen dat het gewenste deel bleef en het ongewenste verdween.

### DQL — `02bewerken.sql`

`INNER JOIN` over vier tabellen (film → genre en film → cast → persoon), `LEFT JOIN` om ook films zonder comments te tonen, en dezelfde relatie als `RIGHT JOIN` met de tabellen omgewisseld.

### Views — `03performance.sql`

Drie views, elk voor een ander doel uit de cursus:

- **`v_movie_overview`** — hergebruik van een complexe join, zodat de applicatie die niet telkens hoeft te herschrijven.
- **`v_public_users`** — beveiliging. Toont enkel `user_id`, `username`, `display_name` en `created_at`; `email` en `password_hash` zijn onbereikbaar. `WITH READ ONLY` maakt de view onwijzigbaar, wat een `UPDATE` laat falen met `ORA-42399`.
- **`v_available_movies`** — `WITH CHECK OPTION`. Een rij invoegen of wijzigen zodat ze buiten de view-voorwaarde valt, faalt met `ORA-01402`.

Ik gebruik `CREATE OR REPLACE VIEW` in plaats van `DROP` + `CREATE`, omdat toegekende rechten bij een `DROP` verloren gaan. Aangezien ik later `GRANT SELECT` op deze views doe, zou een drop mijn security-configuratie kapotmaken.

### Indexen en performance — `03performance.sql`

Zes handmatige indexen, gekozen om de vier types te demonstreren:

| Index | Type | Reden |
|---|---|---|
| `ix_movies_title` | B-tree | zoeken en sorteren op titel |
| `bx_movies_quality` | **bitmap** | lage kardinaliteit: slechts SD/HD/4K |
| `fx_movies_uppertitle` | **function-based** | maakt hoofdletterongevoelig zoeken indexeerbaar |
| `ix_watch_user_movie` | **composite** | `user_id` is de leidende kolom |
| `ix_comments_movie` | B-tree (FK) | gebruikt door `v_movie_overview` |
| `ix_ratings_movie` | B-tree (FK) | idem |

Daarnaast bestaan er **automatisch** indexen op elke `PRIMARY KEY` en `UNIQUE`-constraint, in totaal een vijftiental. De zes hierboven zijn dus een aanvulling, geen volledige lijst.

#### Wat ik geleerd heb uit de metingen

**Een leidende wildcard maakt elke B-tree nutteloos.** `WHERE title LIKE '%Incep%'` geeft altijd een full table scan.

**De optimizer beslist op basis van verwachte rij-aantallen, niet op basis van het bestaan van een index.** Bij dezelfde index en dezelfde kolom kiest hij een ander plan naargelang de waarde selectief is of niet.

**De clustering factor verklaart waarom een index op `status` nooit gebruikt wordt.** Ongeveer 10% van de films heeft status `archived` op het eerste gezicht selectief genoeg. Maar die rijen liggen willekeurig verspreid over alle datablokken: in elk blok van ~50 rijen zitten er ~5 archived. Via de index zou Oracle bijna 4.900 losse blokken moeten lezen (random I/O), terwijl de hele tabel maar ~1.000 blokken telt die hij sequentieel kan doorlopen. De index is dus ongeveer vier keer duurder. Niet het *percentage* telt, maar het *aantal rijen ten opzichte van het aantal blokken*.

Deze index heb ik daarom weer verwijderd: hij zou nooit gebruikt worden en enkel `INSERT`/`UPDATE`/`DELETE` vertragen.

**Meten vraagt zorg.** `SET TIMING` op een `SELECT *` meet enkel de eerste ~100 opgehaalde rijen, niet de volledige query — daarom gebruik ik `COUNT(*)`. En de `Cost`-waarde uit het uitvoeringsplan is betrouwbaarder dan kloktijd.

**Statistieken zijn een voorwaarde.** Zonder actuele statistieken veronderstelt de optimizer een gelijkmatige verdeling en kan hij scheve data niet herkennen.

Om te vergelijken gebruik ik `ALTER INDEX ... INVISIBLE` in plaats van de index te droppen: hij blijft bestaan en wordt door DML onderhouden, maar de optimizer negeert hem. Zo vergelijk ik exact dezelfde situatie met en zonder index.

### Security — `03performance.sql`

Twee rollen, volgens het principe van minimale rechten:

- **`role_viewer`** — `SELECT` op de drie views en op `movies`. Bewust **niet** op de tabel `users`: die bevat e-mailadressen en wachtwoordhashes. Daarvoor bestaat `v_public_users`.
- **`role_contributor`** — `INSERT` op `comments` en `ratings`, plus `SELECT` op `seq_comment_id`. Dat laatste is noodzakelijk: `comment_id` is `NOT NULL` zonder default, dus zonder toegang tot de sequence kan een vriend geen enkele reactie plaatsen.

`role_contributor` is tegelijk de rol waarmee een toekomstige webapplicatie zou verbinden.

**Delegatie.** `WITH GRANT OPTION` laat de ontvanger een recht doorgeven. Oracle staat dit **enkel toe richting een gebruiker**, niet richting een rol (`ORA-01926`) — logisch, want anders zou een rol ongecontroleerd rechten kunnen verspreiden.

Het intrekken van een object-privilege werkt **cascaderend**: trek ik het recht in bij `filmlib_friend`, dan verliest ook wie het van hem kreeg het meteen.

---

## 5. Databronnen

De databank bevat echte filmgegevens, geen verzonnen data.

| Bron | Wat | Licentie / opmerking |
|---|---|---|
| [IMDb Non-Commercial Datasets](https://datasets.imdbws.com/) | films, personen, cast, genres, stemmen | Enkel niet-commercieel gebruik; gebruikt in dat kader |
| [Faker](https://faker.readthedocs.io/) | synthetische gebruikers, comments, kijkgeschiedenis | MIT |


De sociale gegevens (`users`, `friendships`, `comments`, `ratings`, `watch_history`) bestaan niet als publieke dataset en zijn synthetisch gegenereerd met een vaste seed, zodat elke run dezelfde data oplevert.

### Geraadpleegde documentatie

- Oracle Help Center — *Indexes and Index-Organized Tables*
- Oracle Database SQL Language Reference — `EXPLAIN PLAN`, `CREATE SEQUENCE`, `CREATE VIEW`, `GRANT`
- Cursusmateriaal Data Management (Notion): DQL, DDL, Sequences, Views, Performance boosting, Database Security: https://app.notion.com/p/510949731bab4feab714010da0f74ba5?v=a7c6a87d436f428fa455af48367e2e76&source=copy_link
- gemini voor vragen: https://share.gemini.google/jmxPtI5QW8Ko

---

## 6. Het laadscript (ETL)

`python_films/load_films.py` doorloopt drie fasen:

1. **Extract** — de IMDb-bestanden worden streamend ingelezen. De volgorde is bewust: eerst het kleine `title.ratings`-bestand om een set populaire titels te bouwen, dan pas de grote bestanden filteren op die set. Zonder die volgorde zou `title.principals` (ongeveer 90 miljoen rijen) volledig in het geheugen belanden.
2. **Transform** — genres uitsplitsen, personen ontdubbelen, IMDb-categorieën mappen naar `actor`/`director`/`writer`, en de synthetische sociale data genereren binnen de grenzen van alle CHECK-constraints.
3. **Load** — `executemany` in batches van 5.000 rijen, in foreign-key-volgorde.

Na het laden worden de sequences met `ALTER SEQUENCE ... RESTART START WITH` voorbij de hoogste geladen id gezet, zodat `NEXTVAL` in de SQL-scripts niet botst met bestaande rijen.

De indexen worden pas na het laden aangemaakt, conform de best practice uit de cursus: een bestaande index moet bij elke `INSERT` bijgewerkt worden en vertraagt een bulk-load aanzienlijk.

---