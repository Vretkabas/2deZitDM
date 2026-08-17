# Filmbibliotheek — Data Management werkstuk

**Lucas Huygen** · tweede zittijd

Dit bestand legt uit hoe je de databank opzet. De inhoudelijke verantwoording
(waarom deze tabellen, deze indexen, deze rollen) staat in **`VERSLAG.md`**.

---

## Gebruik van AI — volledige openheid

Ik heb bij dit werkstuk Claude Code gebruikt. Hieronder staat wat door AI gemaakt is
en wat door mij, zodat er geen twijfel over bestaat.

**Door AI geschreven:**

- `python_films/load_films.py` — het ETL-script
- `python_films/export_dump.py` — het exportscript voor de datadump
- `README.md`


**Over de gesprekken:** Claude Code draait lokaal in de terminal en genereert geen
deelbare gesprekslinks, dus ik kan de conversaties helaas niet als bijlage meesturen.

---

## Wat je nodig hebt

- Oracle Database (ontwikkeld op XE 21c, werkt op elke recente versie)
- SQL\*Plus of SQLcl
- Een eigen schemagebruiker — de naam maakt niet uit, de scripts gebruiken nergens
  een schemaprefix en maken alles aan in het schema waarmee je verbonden bent.

Python is **niet** nodig als je de meegeleverde datadump gebruikt.

---

## Snelste weg (aanbevolen) — enkel Oracle

Open een terminal in de map `2deZitDM` en verbind:

```
sqlplus <jouw_gebruiker>@localhost:1521/XEPDB1
```

Draai daarna in deze volgorde:

```
@01setup.sql        -- tabellen, constraints, comments, sequences
@data_dump.sql      -- vult alle tabellen met data (kon ik niet op github plaatsen, meegeleverd in uploadzone)
@02bewerken.sql     -- DML, transacties, queries
@03performance.sql  -- views, indexen, performance, security
```

### Vooraf: rechten voor de security-sectie

`03performance.sql` maakt een gebruiker en twee rollen aan. Dat vraagt system
privileges die een gewone schemagebruiker niet heeft. Ken ze eenmalig toe als
`SYSTEM` (of `SYS AS SYSDBA`):

```sql
GRANT CREATE USER, CREATE ROLE, DROP USER TO <jouw_gebruiker>;
GRANT CREATE SESSION TO <jouw_gebruiker> WITH ADMIN OPTION;
```

Die tweede regel is nodig omdat je `CREATE SESSION` alleen kan doorgeven aan
`filmlib_friend` als je het zelf `WITH ADMIN OPTION` bezit. Zonder die optie faalt
de toekenning met `ORA-01031`.

Ben je al DBA of verbonden als `SYSTEM`, dan kan je deze stap overslaan.

---

## Volledige weg — met de originele IMDb-data

Wie de data liever zelf opbouwt uit de bronbestanden:

1. Download deze bestanden van <https://datasets.imdbws.com/> naar `python_films/movies/`:
   `title.basics.tsv.gz`, `title.principals.tsv.gz`, `title.ratings.tsv.gz`, `name.basics.tsv.gz`
2. `pip install oracledb faker`
3. `@01setup.sql` draaien
4. `python python_films/load_films.py`

Let op: dit downloadt ongeveer 3,5 GB en de verwerking duurt enkele minuten.
De datadump levert exact hetzelfde resultaat, daarom is die de aanbevolen weg.

---

## De bestanden

| Bestand | Inhoud |
|---|---|
| `01setup.sql` | 10 tabellen met alle constraints, `COMMENT ON`, 6 sequences |
| `data_dump.sql` | Alle data als `INSERT`-statements + sequences bijzetten |
| `02bewerken.sql` | DML, `SAVEPOINT`/`ROLLBACK`/`COMMIT`, joins en queries |
| `03performance.sql` | Views, indexen, uitvoeringsplannen, gebruikers en rollen |
| `python_films/load_films.py` | ETL-script (IMDb → Oracle) |
| `python_films/export_dump.py` | Genereert `data_dump.sql` uit een gevulde databank |
| `VERSLAG.md` | Verantwoording van alle keuzes + bronvermelding |
| `ERD/` | Entity-relationship diagram |
| `output/` | Gespoolde uitvoer van elk script (bewijs van uitvoering) |

---

## Goed om te weten bij het draaien

**Start vanuit de map `2deZitDM`.** De `SPOOL`-opdrachten gebruiken relatieve paden
en schrijven naar `output/`. Die map moet bestaan.

**Foutmeldingen bij de eerste run zijn normaal.** Elk script begint met `DROP`-opdrachten
zodat het herhaaldelijk gedraaid kan worden. Bestaat het object nog niet, dan meldt
Oracle "does not exist" en loopt het script gewoon door.

**Sommige fouten zijn opzettelijk.** In `03performance.sql` staan tests die *moeten*
mislukken, telkens gemarkeerd in commentaar:

| Fout | Waarom die hoort te verschijnen |
|---|---|
| `ORA-42399` | `UPDATE` op een view met `WITH READ ONLY` |
| `ORA-01402` | rij zou buiten de `WITH CHECK OPTION`-voorwaarde vallen |
| `ORA-01031` | `filmlib_friend` mag de filmcollectie niet wijzigen |

Die drie zijn het bewijs dat de constraints en rechten werken.

**`data_dump.sql` één keer draaien.** Het bestand bevat alleen `INSERT`-statements.
Wil je opnieuw laden, draai dan eerst `01setup.sql` (dat maakt de tabellen leeg opnieuw aan).

**Wachtwoord van de testgebruiker:** `filmlib_friend` / `Geheim123` — wordt aangemaakt
door `03performance.sql` voor de security-demo.
