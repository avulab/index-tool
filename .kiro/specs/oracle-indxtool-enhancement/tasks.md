# Implementation Plan: Oracle Index Tool Enhancement

## Overview

Modernise `indxtool.sql` for Oracle 19c+, complete four unimplemented procedures,
add ASSM awareness, replace deprecated APIs, add a scheduler job, write a test suite,
and update the README. All work is in PL/SQL (SQL*Plus scripts).

## Tasks

- [x] 1. Modernise DDL — remove STORAGE clauses, replace BITMAP INDEX, add idempotent guards, remove hardcoded connect
  - Remove `connect / as sysdba`; add a comment instructing the DBA to connect before running
  - Wrap every `CREATE TABLE`, `CREATE INDEX`, `CREATE SEQUENCE` in an `EXECUTE IMMEDIATE` block that catches `ORA-00955`
  - Strip all `STORAGE (INITIAL … NEXT … PCTINCREASE …)` clauses from `CREATE TABLE` and `ALTER TABLE … ADD CONSTRAINT … USING INDEX` statements
  - Replace `CREATE BITMAP INDEX site_index_stats_n2` with a plain B-tree `CREATE INDEX`
  - _Requirements: 9.1, 9.2, 9.3, 9.4_

- [x] 2. Add new `site_parameters` rows and private helper functions
  - [x] 2.1 Insert `DEFAULT_END_TIME` and `DEFAULT_MAX_MINUTES` rows (NULL values) into `site_parameters` seed data
    - _Requirements: (supports 1.x, 6.x time-constraint parameters)_
  - [x] 2.2 Implement private function `is_assm(v_tablespace_name VARCHAR2) RETURN BOOLEAN`
    - Query `dba_tablespaces.segment_space_management`; return FALSE on NO_DATA_FOUND
    - _Requirements: 6.2, 6.4, 7.1_
  - [x] 2.3 Implement private function `effective_end_time(v_end_time DATE, v_max_minutes NUMBER) RETURN DATE`
    - Explicit params take priority; fall back to `DEFAULT_END_TIME` then `DEFAULT_MAX_MINUTES` site params; return NULL if none set
    - _Requirements: (supports collect/rebuild time-constraint parameters)_
  - [x] 2.4 Implement private function `deadline_exceeded(v_deadline DATE) RETURN BOOLEAN`
    - Return TRUE when `v_deadline IS NOT NULL AND SYSDATE >= v_deadline`
    - _Requirements: (supports collect/rebuild time-constraint parameters)_


- [x] 3. Modernise `collect` procedure
  - [x] 3.1 Update package spec signature to add `v_end_time DATE DEFAULT NULL` and `v_max_minutes NUMBER DEFAULT NULL`
    - _Requirements: 1.2_
  - [x] 3.2 Replace `DBMS_SQL.OPEN_CURSOR` / `DBMS_SQL.PARSE` / `DBMS_SQL.EXECUTE` / `DBMS_SQL.CLOSE_CURSOR` with `EXECUTE IMMEDIATE`
    - _Requirements: 1.2_
  - [x] 3.3 Add skip logic for partitioned indexes and IOTs: detect via `dba_indexes.index_type` and `dba_indexes.table_type`; record message in `site_index_stats.message` and `CONTINUE`
    - _Requirements: 1.3_
  - [x] 3.4 Add `DBMS_STATS.GATHER_INDEX_STATS` call immediately before the `EXECUTE IMMEDIATE 'ANALYZE INDEX … VALIDATE STRUCTURE ONLINE'` call
    - _Requirements: 1.1_
  - [x] 3.5 Resolve deadline via `effective_end_time`; check `deadline_exceeded` at the top of the loop and exit gracefully (set status IDLE, commit, RETURN)
    - _Requirements: 1.4, 1.5_
  - [x] 3.6 Remove all remaining `DBMS_SQL` references from exception handlers in `collect`
    - _Requirements: 1.2_
  - [ ]* 3.7 Write property test: for any index processed by `collect`, a row exists in `site_index_stats` with `status = 'COMPLETED'`
    - **Property: collect completeness — every processed index produces a COMPLETED stats row**
    - **Validates: Requirements 1.1, 10.1**

- [x] 4. Implement `analyse` procedure
  - [x] 4.1 Load threshold values from `site_parameters` (mirrors `schedule` variable declarations)
    - _Requirements: 2.1_
  - [x] 4.2 Implement B-tree height check: INSERT SUBMITTED when `height > v_btree_height_threshold`, guarded by NOT EXISTS on non-COMPLETED entries
    - _Requirements: 2.2, 2.6_
  - [x] 4.3 Implement PCT_DELETE + DISTINCTIVENESS check: INSERT SUBMITTED when both thresholds exceeded, guarded by NOT EXISTS
    - _Requirements: 2.3, 2.6_
  - [x] 4.4 Implement PCT_USED vs historical average check: INSERT SUBMITTED when below threshold, guarded by NOT EXISTS
    - _Requirements: 2.4, 2.6_
  - [x] 4.5 Implement AGE_THRESHOLD check: INSERT SUBMITTED when no completed rebuild within threshold days, guarded by NOT EXISTS
    - _Requirements: 2.5, 2.6_
  - [x] 4.6 Add COMMIT at end of procedure
    - _Requirements: 2.7_
  - [ ]* 4.7 Write property test: after `analyse`, every index whose stats exceed any threshold has a SUBMITTED row in `site_index_rebuilds`
    - **Property: analyse threshold coverage — threshold breach always produces a SUBMITTED rebuild record**
    - **Validates: Requirements 2.2, 2.3, 2.4, 2.5, 10.2**

- [x] 5. Implement `report` procedure
  - [x] 5.1 Iterate `cur_rpt` (already defined in package spec); apply `v_schema` / `v_idx` filters via WHERE-clause additions or post-fetch IF guards
    - _Requirements: 3.1, 3.2, 3.3_
  - [x] 5.2 Emit each row via `DBMS_OUTPUT.PUT_LINE` in fixed-width column-aligned format when `v_trace_lvl > 0`
    - _Requirements: 3.4_
  - [x] 5.3 Emit "No index statistics data available." and return when cursor returns no rows
    - _Requirements: 3.5_
  - [ ]* 5.4 Write unit test: call `report` and verify it completes without raising an exception
    - **Validates: Requirements 3.1, 10.3**


- [x] 6. Implement `confirm` procedure
  - [x] 6.1 Display all SUBMITTED records (filtered by `v_schema` / `v_idx`) via `DBMS_OUTPUT.PUT_LINE`, showing record_id, owner, index name, reason, and timestamp
    - _Requirements: 4.1, 4.2, 4.3_
  - [x] 6.2 When both `v_schema` and `v_idx` are non-null, bulk-UPDATE matching SUBMITTED records to `status = 'VERIFIED'`, `timestamp = SYSDATE`
    - _Requirements: 4.4, 4.5_
  - [x] 6.3 Add COMMIT at end of procedure
    - _Requirements: 4.7_
  - [ ]* 6.4 Write unit test: call `confirm` with both params non-null and verify matching rows are set to VERIFIED
    - **Validates: Requirements 4.4, 4.5**

- [x] 7. Implement `select_tablespaces` procedure
  - [x] 7.1 Query `dba_tablespaces` for destination names matching `%INDEX%`, `%IDX%`, `%INDX%`, or ending with `X`
    - _Requirements: 5.1_
  - [x] 7.2 Query `dba_tablespaces` for source names matching `%DATA%` or ending with `D`
    - _Requirements: 5.2_
  - [x] 7.3 INSERT all source×destination pairs into `site_index_moves` where the pair does not already exist (use `MERGE` or INSERT with NOT EXISTS)
    - _Requirements: 5.3_
  - [x] 7.4 Emit a warning via `DBMS_OUTPUT.PUT_LINE` when either list is empty; leave `site_index_moves` unchanged
    - _Requirements: 5.4_
  - [x] 7.5 Add COMMIT at end of procedure
    - _Requirements: 5.5_
  - [ ]* 7.6 Write unit test: call `select_tablespaces` and verify `site_index_moves` is populated when matching tablespace names exist
    - **Validates: Requirements 5.3, 10.4**

- [x] 8. Checkpoint — compile and smoke-test the package
  - Ensure the package spec and body compile without errors (`SHOW ERRORS`)
  - Ensure all tests written so far pass; ask the user if questions arise.

- [x] 9. Modernise `verify` function
  - [x] 9.1 Call `is_assm(v_tablespace_name)` at the top of `verify`; if ASSM, set `v_concat := 'N'`, UPDATE status to VERIFIED, and return TRUE immediately
    - _Requirements: 7.1, 7.2_
  - [x] 9.2 Retain existing `dba_free_space` logic for non-ASSM tablespaces unchanged
    - _Requirements: 7.2, 7.3_

- [ ] 10. Modernise `rebuild` procedure
  - [-] 10.1 Update package spec signature to add `v_end_time DATE DEFAULT NULL` and `v_max_minutes NUMBER DEFAULT NULL`
    - _Requirements: 6.3_
  - [-] 10.2 Replace all `DBMS_SQL` calls with `EXECUTE IMMEDIATE`; remove `v_cur_handle` usage from `rebuild`
    - _Requirements: 6.3_
  - [-] 10.3 Call `is_assm` before the COALESCE step; skip `ALTER TABLESPACE … COALESCE` when ASSM
    - _Requirements: 6.4_
  - [-] 10.4 Replace `UNRECOVERABLE` keyword with `NOLOGGING` in the rebuild DDL string
    - _Requirements: 6.1_
  - [ ] 10.5 Omit `STORAGE (…)` clause from rebuild DDL when ASSM; retain it for non-ASSM tablespaces
    - _Requirements: 6.2_
  - [ ] 10.6 Resolve deadline via `effective_end_time`; check `deadline_exceeded` at the top of the loop and exit gracefully (set status IDLE, commit, RETURN)
    - _Requirements: 6.6_
  - [ ] 10.7 Remove `DBMS_SQL` references from `rebuild` exception handlers; ensure `index_tool_control` is set to IDLE on normal completion and FAILED on unhandled exception
    - _Requirements: 6.6_


- [ ] 11. Replace `DBMS_JOB` with `DBMS_SCHEDULER` job
  - Drop the `EXECUTE dbms_job.isubmit(…)` call at the bottom of the script
  - Add an idempotent `DBMS_SCHEDULER.DROP_JOB` + `DBMS_SCHEDULER.CREATE_JOB` block that creates `SITEDBA.INDEX_TOOL_WEEKLY`
  - Job action must call `collect`, `analyse`, `schedule`, and `rebuild` in sequence
  - Schedule: `FREQ=WEEKLY;BYDAY=SAT;BYHOUR=9;BYMINUTE=0;BYSECOND=0`
  - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [ ] 12. Checkpoint — full integration test
  - Ensure the complete `indxtool.sql` script runs from start to finish without errors on a clean schema
  - Ensure all tests pass; ask the user if questions arise.

- [ ] 13. Write `indxtool_test.sql` test suite
  - [ ] 13.1 Write test T1: call `collect`; assert rows exist in `site_index_stats` with `status = 'COMPLETED'`
    - _Requirements: 10.1_
  - [ ] 13.2 Write test T2: call `analyse` after `collect`; assert indexes exceeding any threshold have a SUBMITTED row in `site_index_rebuilds`
    - _Requirements: 10.2_
  - [ ] 13.3 Write test T3: call `report`; assert it completes without raising an exception
    - _Requirements: 10.3_
  - [ ] 13.4 Write test T4: call `select_tablespaces`; assert `site_index_moves` is populated when matching tablespace names exist in `dba_tablespaces`
    - _Requirements: 10.4_
  - [ ] 13.5 Write test T5 (round-trip): call `collect`, `analyse`, `schedule`, `rebuild`, `purge` in sequence; assert all `index_tool_control` rows have `status = 'IDLE'`
    - _Requirements: 10.5_
  - [ ] 13.6 Write test T6: call `get_site_param_value` with a non-existent parameter; assert `ORA-20000` is raised
    - _Requirements: 10.6_
  - [ ] 13.7 Write test T7: insert rows with timestamps before and after a cutoff date; call `purge(cutoff)`; assert pre-cutoff rows are deleted and post-cutoff rows are retained in both `site_index_stats` and `site_index_rebuilds`
    - _Requirements: 10.7_

- [ ] 14. Write `README.md` documentation
  - Document installation prerequisites: required Oracle privileges and minimum version (19c)
  - Document every public procedure and function: parameters, defaults, and behaviour
  - Document every `site_parameters` row: domain, name, default value, and effect
  - Write step-by-step operational guide: install → collect → report → confirm → rebuild → verify
  - Document the `DBMS_SCHEDULER` job: name, schedule, and how to enable/disable/run manually
  - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

- [ ] 15. Final checkpoint — ensure all tests pass
  - Run `indxtool_test.sql` end-to-end; verify all assertions pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at logical boundaries
- The design document contains the authoritative pseudocode for all procedure logic
- All dynamic SQL must use `EXECUTE IMMEDIATE`; no `DBMS_SQL` calls should remain after task 3 and 10
