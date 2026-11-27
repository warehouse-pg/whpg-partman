-- ########## WHPG: CHILD TABLES INHERIT THE PARENT'S STORAGE ##########
-- Child tables and the default partition must get the parent's access method, reloptions and
-- column encodings: AO column (with a column-level ENCODING that differs from the table-level one),
-- AO row and heap parents; children made by create_parent(), by run_maintenance(), and by native
-- sub-partitioning.

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(15);
CREATE SCHEMA partman_test;

CREATE TABLE partman_test.aoco_taptest_table (
    col1 bigint NOT NULL
    , col2 text ENCODING (compresstype=zlib, compresslevel=1)
    , col3 timestamptz NOT NULL DEFAULT now())
WITH (appendoptimized=true, orientation=column, compresstype=zstd, compresslevel=5)
DISTRIBUTED BY (col1)
PARTITION BY RANGE (col1);

CREATE TABLE partman_test.aorow_taptest_table (
    col1 bigint NOT NULL
    , col2 text
    , col3 timestamptz NOT NULL DEFAULT now())
WITH (appendoptimized=true, compresstype=zlib, compresslevel=3)
DISTRIBUTED BY (col1)
PARTITION BY RANGE (col1);

CREATE TABLE partman_test.heap_taptest_table (
    col1 bigint NOT NULL
    , col2 text)
DISTRIBUTED BY (col1)
PARTITION BY RANGE (col1);

SELECT create_parent('partman_test.aoco_taptest_table', 'col1', 'native', '10', p_premake := 2, p_jobmon := false);
SELECT create_parent('partman_test.aorow_taptest_table', 'col1', 'native', '10', p_premake := 2, p_jobmon := false);
SELECT create_parent('partman_test.heap_taptest_table', 'col1', 'native', '10', p_premake := 2, p_jobmon := false);

-- AO column parent
SELECT results_eq(
    $$SELECT c.relname::text COLLATE "default", a.amname::text COLLATE "default"
      FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid JOIN pg_am a ON a.oid = c.relam
      WHERE i.inhparent = 'partman_test.aoco_taptest_table'::regclass ORDER BY 1$$
    , $$VALUES ('aoco_taptest_table_default', 'ao_column'), ('aoco_taptest_table_p0', 'ao_column')
             , ('aoco_taptest_table_p10', 'ao_column'), ('aoco_taptest_table_p20', 'ao_column')$$
    , 'Check that aoco_taptest_table children inherited the ao_column access method');
SELECT results_eq(
    $$SELECT c.relname::text COLLATE "default", c.reloptions @> ARRAY['compresstype=zstd', 'compresslevel=5']
      FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
      WHERE i.inhparent = 'partman_test.aoco_taptest_table'::regclass ORDER BY 1$$
    , $$VALUES ('aoco_taptest_table_default', true), ('aoco_taptest_table_p0', true)
             , ('aoco_taptest_table_p10', true), ('aoco_taptest_table_p20', true)$$
    , 'Check that aoco_taptest_table children inherited the reloptions');
SELECT results_eq(
    $$SELECT c.relname::text COLLATE "default", e.attoptions @> ARRAY['compresstype=zstd', 'compresslevel=5']
      FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
      JOIN pg_attribute_encoding e ON e.attrelid = c.oid AND e.attnum = 1
      WHERE i.inhparent = 'partman_test.aoco_taptest_table'::regclass ORDER BY 1$$
    , $$VALUES ('aoco_taptest_table_default', true), ('aoco_taptest_table_p0', true)
             , ('aoco_taptest_table_p10', true), ('aoco_taptest_table_p20', true)$$
    , 'Check that aoco_taptest_table children inherited the table-level encoding on col1');
SELECT results_eq(
    $$SELECT c.relname::text COLLATE "default", e.attoptions @> ARRAY['compresstype=zlib', 'compresslevel=1']
      FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
      JOIN pg_attribute_encoding e ON e.attrelid = c.oid AND e.attnum = 2
      WHERE i.inhparent = 'partman_test.aoco_taptest_table'::regclass ORDER BY 1$$
    , $$VALUES ('aoco_taptest_table_default', true), ('aoco_taptest_table_p0', true)
             , ('aoco_taptest_table_p10', true), ('aoco_taptest_table_p20', true)$$
    , 'Check that aoco_taptest_table children inherited the column-level encoding on col2');

-- Children made later by run_maintenance()
INSERT INTO partman_test.aoco_taptest_table (col1, col2) VALUES (generate_series(1, 25), 'stuff');
SELECT run_maintenance('partman_test.aoco_taptest_table', p_jobmon := false);

SELECT results_eq(
    $$SELECT c.relname::text COLLATE "default", a.amname::text COLLATE "default", c.reloptions @> ARRAY['compresstype=zstd', 'compresslevel=5']
      FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid JOIN pg_am a ON a.oid = c.relam
      WHERE i.inhparent = 'partman_test.aoco_taptest_table'::regclass
      AND c.relname IN ('aoco_taptest_table_p30', 'aoco_taptest_table_p40') ORDER BY 1$$
    , $$VALUES ('aoco_taptest_table_p30', 'ao_column', true), ('aoco_taptest_table_p40', 'ao_column', true)$$
    , 'Check that children made by run_maintenance() inherited the ao_column access method and reloptions');
SELECT results_eq(
    $$SELECT c.relname::text COLLATE "default", e.attoptions @> ARRAY['compresstype=zlib', 'compresslevel=1']
      FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
      JOIN pg_attribute_encoding e ON e.attrelid = c.oid AND e.attnum = 2
      WHERE i.inhparent = 'partman_test.aoco_taptest_table'::regclass
      AND c.relname IN ('aoco_taptest_table_p30', 'aoco_taptest_table_p40') ORDER BY 1$$
    , $$VALUES ('aoco_taptest_table_p30', true), ('aoco_taptest_table_p40', true)$$
    , 'Check that children made by run_maintenance() inherited the column-level encoding on col2');
SELECT results_eq('SELECT count(*)::int FROM partman_test.aoco_taptest_table', ARRAY[25], 'Check count from aoco_taptest_table');
SELECT is_empty('SELECT * FROM partman_test.aoco_taptest_table_default', 'Check that aoco_taptest_table_default is empty');

-- AO row parent
SELECT results_eq(
    $$SELECT c.relname::text COLLATE "default", a.amname::text COLLATE "default", c.reloptions @> ARRAY['compresstype=zlib', 'compresslevel=3']
      FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid JOIN pg_am a ON a.oid = c.relam
      WHERE i.inhparent = 'partman_test.aorow_taptest_table'::regclass ORDER BY 1$$
    , $$VALUES ('aorow_taptest_table_default', 'ao_row', true), ('aorow_taptest_table_p0', 'ao_row', true)
             , ('aorow_taptest_table_p10', 'ao_row', true), ('aorow_taptest_table_p20', 'ao_row', true)$$
    , 'Check that aorow_taptest_table children inherited the ao_row access method and reloptions');

-- Native sub-partitioning of the AO row parent: sub-parents and their children
SELECT create_sub_parent('partman_test.aorow_taptest_table', 'col3', 'native', 'daily', p_native_check := 'yes', p_premake := 2, p_jobmon := false);

SELECT is_partitioned('partman_test', 'aorow_taptest_table_p0', 'Check aorow_taptest_table_p0 is natively partitioned');
SELECT results_eq(
    $$SELECT c.relname::text COLLATE "default", a.amname::text COLLATE "default"
      FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid JOIN pg_am a ON a.oid = c.relam
      WHERE i.inhparent = 'partman_test.aorow_taptest_table'::regclass AND c.relkind = 'p' ORDER BY 1$$
    , $$VALUES ('aorow_taptest_table_p0', 'ao_row'), ('aorow_taptest_table_p10', 'ao_row')
             , ('aorow_taptest_table_p20', 'ao_row')$$
    , 'Check that aorow_taptest_table sub-parents inherited the ao_row access method');
SELECT cmp_ok(
    (SELECT count(*)::int FROM pg_partition_tree('partman_test.aorow_taptest_table'::regclass) t WHERE t.level = 2 AND t.isleaf)
    , '>', 0
    , 'Check that aorow_taptest_table has sub-partition children');
SELECT is(
    (SELECT count(*)::int
     FROM pg_partition_tree('partman_test.aorow_taptest_table'::regclass) t
     JOIN pg_class c ON c.oid = t.relid
     WHERE t.isleaf
     AND (c.relam <> (SELECT oid FROM pg_am WHERE amname = 'ao_row') OR NOT c.reloptions @> ARRAY['compresstype=zlib', 'compresslevel=3']))
    , 0
    , 'Check that every aorow_taptest_table leaf partition inherited the ao_row access method and reloptions');

-- Heap parent: children stay heap without reloptions
SELECT results_eq(
    $$SELECT c.relname::text COLLATE "default", a.amname::text COLLATE "default", c.reloptions IS NULL
      FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid JOIN pg_am a ON a.oid = c.relam
      WHERE i.inhparent = 'partman_test.heap_taptest_table'::regclass ORDER BY 1$$
    , $$VALUES ('heap_taptest_table_default', 'heap', true), ('heap_taptest_table_p0', 'heap', true)
             , ('heap_taptest_table_p10', 'heap', true), ('heap_taptest_table_p20', 'heap', true)$$
    , 'Check that heap_taptest_table children stay heap');
SELECT is_empty(
    $$SELECT 1 FROM pg_inherits i JOIN pg_attribute_encoding e ON e.attrelid = i.inhrelid
      WHERE i.inhparent = 'partman_test.heap_taptest_table'::regclass$$
    , 'Check that heap_taptest_table children have no column encodings');

SELECT * FROM finish();
ROLLBACK;
