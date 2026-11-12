-- 1.
CREATE TABLE table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1,(10^7)::int) x;

-- 2.
SELECT *, pg_size_pretty(total_bytes) AS total,
          pg_size_pretty(index_bytes) AS INDEX,
          pg_size_pretty(toast_bytes) AS toast,
          pg_size_pretty(table_bytes) AS TABLE
FROM ( SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
       FROM (SELECT c.oid, nspname AS table_schema,
                    relname AS TABLE_NAME,
                    c.reltuples AS row_estimate,
                    pg_total_relation_size(c.oid) AS total_bytes,
                    pg_indexes_size(c.oid) AS index_bytes,
                    pg_total_relation_size(reltoastrelid) AS toast_bytes
             FROM pg_class c
             LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE relkind = 'r'
            ) a
     ) a
WHERE table_name LIKE '%table_to_delete%';
-- size - 575 MB

-- 3.
DELETE FROM table_to_delete
WHERE REPLACE(col, 'veeeeeeery_long_string','')::int % 3 = 0;
-- a) time 5.9 s
-- b) size 575 MB

VACUUM FULL VERBOSE table_to_delete;
-- d) 383 MB

DROP TABLE table_to_delete;
CREATE TABLE table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1,(10^7)::int) x;
-- 575 MB

-- 4.
TRUNCATE table_to_delete;
-- a) 0.25 s
-- c) 8 KB

/*
    5. Explanation:

a) At the start the table took 575 MB. After the DELETE it was still 575 MB, even though
one third of the rows was removed. Only after VACUUM FULL did the size go down to 383 MB.
When I recreated the table it was 575 MB again, and after TRUNCATE it became only 8 KB.

b) DELETE was much slower than TRUNCATE: it took 5.9 s to remove one third of the rows,
while TRUNCATE removed all 10 million rows in 0.25 s. DELETE also did not free any disk
space, but TRUNCATE gave the space back immediately. The reason is that DELETE works
row by row, so it can use WHERE and fires triggers, while TRUNCATE removes all rows at
once and locks the whole table. In PostgreSQL both of them can be rolled back if they
are run inside BEGIN, but with autocommit on they are committed right away, so there
is nothing to roll back.

c) DELETE does not free space because rows are only marked as dead and stay in the file.
VACUUM FULL rewrites the table with only live rows, so the size went down to 383 MB.
TRUNCATE just replaces the table file with an empty one, so it is fast and frees space
at once. After many deletes the table gets bigger and slower until vacuum runs, so
TRUNCATE is better for removing all rows and DELETE for removing only some of them.
*/