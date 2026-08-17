-- Filmbibliotheek - master script

SET FEEDBACK ON

PROMPT
PROMPT ===================================================================
PROMPT  1/4  Structuur: tabellen, constraints, comments, sequences
PROMPT ===================================================================
@@01setup.sql

PROMPT
PROMPT ===================================================================
PROMPT  2/4  Data laden (dit duurt even)
PROMPT ===================================================================
@@data_dump.sql

PROMPT
PROMPT ===================================================================
PROMPT  3/4  DML, transacties en queries
PROMPT ===================================================================
@@02bewerken.sql

PROMPT
PROMPT ===================================================================
PROMPT  4/4  Views, indexen, performance en security
PROMPT ===================================================================
@@03performance.sql

PROMPT
PROMPT ===================================================================
PROMPT  Klaar. De uitvoer staat in de map output/ :
PROMPT    filmlib_output.txt       (structuur)
PROMPT    bewerkingen_output.txt   (DML, TCL, DQL)
PROMPT    performance_output.txt   (views, indexen, security)
PROMPT ===================================================================
