# index-tool

Oracle PL/SQL tool for automated index maintenance. Collects index statistics, schedules rebuilds based on configurable thresholds, and executes them. Originally developed for Oracle 9i.

## Files

| File | Purpose |
|------|---------|
| `sitedba.sql` | Creates the `sitedba` schema. Run once before `indxtool.sql`. |
| `indxtool.sql` | Main install script: tables, sequences, and the `index_tool` package. |
| `itstatus.sql` | Status reporting queries — run ad hoc to check progress. |

## Installation

1. Connect as `sysdba` and run `sitedba.sql` to create the schema:
   ```
   sqlplus / as sysdba @sitedba.sql
   ```
   You will be prompted for: `password`, `data_tablespace`, `temp_tablespace`, `index_tablespace`.

2. Run the main install script:
   ```
   sqlplus /nolog @indxtool.sql
   ```
   You will be prompted for: `data_tablespace`, `index_tablespace`.

   This creates the tables, package, and schedules a weekly job (Saturdays at 9am).

## How It Works

The tool runs three steps in sequence, scheduled weekly via DBMS_SCHEDULER:

1. **collect** — Gathers statistics for all non-SYS/SYSTEM indexes using `ANALYZE INDEX ... VALIDATE STRUCTURE ONLINE`.
2. **schedule** — Evaluates collected stats against thresholds and inserts candidates into `site_index_rebuilds`.
3. **rebuild** — Rebuilds each scheduled index online with `ALTER INDEX ... REBUILD NOLOGGING ONLINE`.

## Configuration

Thresholds are stored in the `site_parameters` table (domain = `INDEX_TOOL`):

| Parameter | Default | Description |
|-----------|---------|-------------|
| `BTREE_HEIGHT_THRESHOLD` | 4 | Rebuild if B-tree height exceeds this |
| `PCT_DELETE_THRESHOLD` | 10 | Rebuild if % deleted leaf rows exceeds this |
| `DISTINCTIVENESS_THRESHOLD` | 30 | Used with PCT_DELETE check |
| `PCT_USED_CHANGE_THRESHOLD` | 10 | Rebuild if PCT_USED drops more than this % below average |
| `AGE_THRESHOLD` | 90 | Rebuild if not rebuilt within this many days |
| `MOVE_INDEXES` | TRUE | Whether to move indexes between tablespaces |

To change a threshold:
```sql
UPDATE sitedba.site_parameters SET value = '5'
 WHERE domain = 'INDEX_TOOL' AND name = 'BTREE_HEIGHT_THRESHOLD';
COMMIT;
```

## Index Moves

To move indexes from one tablespace to another, set `MOVE_INDEXES = TRUE` and populate `site_index_moves`:
```sql
INSERT INTO sitedba.site_index_moves VALUES ('SOURCE_TS', 'TARGET_TS');
COMMIT;
```

## Monitoring

Run `itstatus.sql` as `sysdba` or `sitedba` to see current job status and any failures:
```
sqlplus / as sysdba @itstatus.sql
```

To stop a running job gracefully, set the control status to `QUIT`:
```sql
UPDATE sitedba.index_tool_control SET status = 'QUIT' WHERE program_id IN ('COLLECT','REBUILD');
COMMIT;
```

## Known Limitations

- Partitioned indexes and Index Organised Tables (IOTs) are not supported.
- The free-space check in `verify` uses `dba_free_space` and is not reliable for locally managed tablespaces with AUTOALLOCATE (default since Oracle 9i).
- `ANALYZE INDEX ... VALIDATE STRUCTURE` is flagged as deprecated for optimizer statistics, but it is the only Oracle mechanism that populates the `index_stats` view with structural data (`DEL_LF_ROWS`, `PCT_USED`, `HEIGHT`) that this tool depends on. `DBMS_STATS` does not provide this data and is not a drop-in replacement here.
- The `analyse`, `report`, `confirm`, and `select_tablespaces` procedures are not yet implemented.
