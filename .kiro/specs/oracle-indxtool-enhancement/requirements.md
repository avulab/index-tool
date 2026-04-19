# Requirements Document

## Introduction

This document describes the requirements for enhancing `indxtool.sql`, a PL/SQL-based Oracle index analysis and rebuild tool originally written circa 2001–2003 for Oracle 8i/9i. The enhancement modernises the tool to work correctly with current Oracle versions (19c+), completes four unimplemented procedures (`analyse`, `report`, `confirm`, `select_tablespaces`), replaces deprecated APIs and DDL patterns, and adds an automated test suite together with user-facing documentation.

## Glossary

- **Index_Tool**: The PL/SQL package `sitedba.index_tool` that collects, analyses, schedules, and rebuilds Oracle B-tree indexes.
- **Collect**: The `index_tool.collect` procedure that gathers index structural statistics and stores them in `site_index_stats`.
- **Analyse**: The `index_tool.analyse` procedure that evaluates collected statistics and flags indexes that require rebuilding.
- **Report**: The `index_tool.report` procedure that produces a formatted, human-readable summary of index health.
- **Confirm**: The `index_tool.confirm` procedure that allows a DBA to approve or reject individual scheduled rebuild entries.
- **Schedule**: The `index_tool.schedule` procedure that inserts rebuild candidates into `site_index_rebuilds` based on configurable thresholds.
- **Rebuild**: The `index_tool.rebuild` procedure that executes `ALTER INDEX … REBUILD` for all verified, scheduled indexes.
- **Purge**: The `index_tool.purge` procedure that removes historical records older than a configurable date.
- **Select_Tablespaces**: The `index_tool.select_tablespaces` procedure that auto-populates `site_index_moves` based on tablespace naming conventions.
- **Verify**: The private `index_tool.verify` function that checks whether sufficient space exists in the target tablespace before a rebuild.
- **DBMS_Stats**: The Oracle-supplied package `DBMS_STATS` used for gathering optimizer statistics on indexes.
- **DBMS_Scheduler**: The Oracle-supplied package `DBMS_SCHEDULER` used for scheduling recurring database jobs.
- **ASSM**: Automatic Segment Space Management — the modern Oracle tablespace space-management mode that makes extent-level free-space checks unnecessary.
- **LMT**: Locally Managed Tablespace — the current Oracle tablespace type that does not use dictionary-managed `STORAGE` clauses.
- **site_index_stats**: The table that stores per-run index structural statistics collected by Collect.
- **site_index_rebuilds**: The table that stores scheduled and completed rebuild records.
- **site_index_moves**: The table that maps source tablespaces to destination tablespaces for index relocation.
- **site_parameters**: The table that stores configurable thresholds and feature flags consumed by Index_Tool.
- **index_tool_control**: The table that stores the running status of each Index_Tool module.
- **DBA**: Database Administrator — the human operator who installs, configures, and monitors Index_Tool.
- **Threshold**: A numeric value stored in `site_parameters` that governs when an index is flagged for rebuild.
- **B-tree Index**: The standard Oracle index type managed by Index_Tool; partitioned indexes and Index-Organised Tables are explicitly out of scope.

---

## Requirements

### Requirement 1: Modernise Statistics Collection

**User Story:** As a DBA, I want index statistics to be gathered using supported Oracle APIs, so that the tool remains compatible with Oracle 19c and later and does not rely on deprecated commands.

#### Acceptance Criteria

1. WHEN Collect is invoked, THE Index_Tool SHALL gather index structural statistics using `DBMS_STATS.GATHER_INDEX_STATS` instead of `ANALYZE INDEX … VALIDATE STRUCTURE`.
2. WHEN Collect is invoked, THE Index_Tool SHALL use `EXECUTE IMMEDIATE` for all dynamic SQL statements instead of the `DBMS_SQL` package.
3. WHEN Collect encounters a partitioned index or an Index-Organised Table, THE Index_Tool SHALL skip that index, record a message in `site_index_stats.message`, and continue processing remaining indexes.
4. WHEN Collect completes successfully, THE Index_Tool SHALL set `index_tool_control.status` to `'IDLE'` for program_id `'COLLECT'`.
5. IF Collect encounters an unhandled exception, THEN THE Index_Tool SHALL set `index_tool_control.status` to `'FAILED'`, record `SQLERRM` in `index_tool_control.message`, commit the status update, and re-raise the exception.

### Requirement 2: Implement the Analyse Procedure

**User Story:** As a DBA, I want the `analyse` procedure to evaluate collected statistics and flag indexes that need rebuilding, so that I have a clear, data-driven basis for scheduling rebuilds.

#### Acceptance Criteria

1. WHEN Analyse is invoked, THE Index_Tool SHALL evaluate the most recent `site_index_stats` record for each index against all configured Thresholds stored in `site_parameters` for domain `'INDEX_TOOL'`.
2. WHEN an index's B-tree height exceeds `BTREE_HEIGHT_THRESHOLD`, THE Index_Tool SHALL insert a record into `site_index_rebuilds` with `status = 'SUBMITTED'` and a reason that includes the threshold value.
3. WHEN an index's percentage of deleted leaf rows exceeds `PCT_DELETE_THRESHOLD` and its distinctiveness is below `DISTINCTIVENESS_THRESHOLD`, THE Index_Tool SHALL insert a record into `site_index_rebuilds` with `status = 'SUBMITTED'` and a reason that includes both threshold values.
4. WHEN an index's `pct_used` falls below the historical average by more than `PCT_USED_CHANGE_THRESHOLD` percent, THE Index_Tool SHALL insert a record into `site_index_rebuilds` with `status = 'SUBMITTED'` and a reason that includes the threshold value.
5. WHEN an index has no completed rebuild recorded in `site_index_rebuilds` within the last `AGE_THRESHOLD` days, THE Index_Tool SHALL insert a record into `site_index_rebuilds` with `status = 'SUBMITTED'` and a reason that includes the threshold value.
6. WHEN Analyse would insert a duplicate rebuild record for an index that already has a non-completed entry in `site_index_rebuilds`, THE Index_Tool SHALL skip that index without inserting a duplicate.
7. WHEN Analyse completes, THE Index_Tool SHALL commit all inserted records.

### Requirement 3: Implement the Report Procedure

**User Story:** As a DBA, I want the `report` procedure to produce a formatted summary of index health, so that I can quickly assess the state of all monitored indexes without writing ad-hoc queries.

#### Acceptance Criteria

1. WHEN Report is invoked, THE Index_Tool SHALL output one row per monitored index showing: owner, index name, current B-tree height, current percentage of deleted leaf rows, current `pct_used`, historical average `pct_used`, and rebuild status.
2. WHEN Report is invoked with a non-null `v_schema` parameter, THE Index_Tool SHALL restrict output to indexes owned by that schema.
3. WHEN Report is invoked with a non-null `v_idx` parameter, THE Index_Tool SHALL restrict output to the index matching that name.
4. WHEN Report is invoked with `v_trace_lvl` greater than 0, THE Index_Tool SHALL emit each output row via `DBMS_OUTPUT.PUT_LINE` in a fixed-width, column-aligned format.
5. WHEN no statistics records exist for any index, THE Index_Tool SHALL output a message stating that no data is available and return without error.

### Requirement 4: Implement the Confirm Procedure

**User Story:** As a DBA, I want the `confirm` procedure to let me approve or reject individual scheduled rebuild entries interactively, so that I retain control over which indexes are actually rebuilt.

#### Acceptance Criteria

1. WHEN Confirm is invoked, THE Index_Tool SHALL display each `site_index_rebuilds` record with `status = 'SUBMITTED'` showing: record_id, owner, index name, reason, and timestamp.
2. WHEN Confirm is invoked with a non-null `v_schema` parameter, THE Index_Tool SHALL restrict displayed records to indexes owned by that schema.
3. WHEN Confirm is invoked with a non-null `v_idx` parameter, THE Index_Tool SHALL restrict displayed records to the index matching that name.
4. WHEN Confirm is called with `v_schema` and `v_idx` both non-null, THE Index_Tool SHALL set `status = 'VERIFIED'` for all matching `SUBMITTED` records, simulating bulk approval suitable for scripted or scheduled use.
5. WHEN Confirm approves a record, THE Index_Tool SHALL update `site_index_rebuilds.status` to `'VERIFIED'` and set `timestamp` to `SYSDATE`.
6. WHEN Confirm rejects a record, THE Index_Tool SHALL update `site_index_rebuilds.status` to `'REJECTED'` and set `timestamp` to `SYSDATE`.
7. WHEN Confirm completes, THE Index_Tool SHALL commit all status changes.

### Requirement 5: Implement the Select_Tablespaces Procedure

**User Story:** As a DBA, I want the `select_tablespaces` procedure to auto-populate `site_index_moves` based on tablespace naming conventions, so that index relocation targets are determined automatically without manual configuration.

#### Acceptance Criteria

1. WHEN Select_Tablespaces is invoked, THE Index_Tool SHALL query `dba_tablespaces` and classify tablespaces whose names match the patterns `%INDEX%`, `%IDX%`, `%INDX%`, or end with `X` as index-destination tablespaces.
2. WHEN Select_Tablespaces is invoked, THE Index_Tool SHALL classify tablespaces whose names match the patterns `%DATA%` or end with `D` as index-source tablespaces.
3. WHEN Select_Tablespaces identifies at least one source and one destination tablespace, THE Index_Tool SHALL insert corresponding rows into `site_index_moves`, pairing each source with each destination, skipping pairs that already exist.
4. WHEN Select_Tablespaces finds no tablespaces matching either naming convention, THE Index_Tool SHALL emit a warning message via `DBMS_OUTPUT.PUT_LINE` and leave `site_index_moves` unchanged.
5. WHEN Select_Tablespaces completes, THE Index_Tool SHALL commit all inserted rows.

### Requirement 6: Modernise the Rebuild Procedure

**User Story:** As a DBA, I want the `rebuild` procedure to use current Oracle DDL syntax and APIs, so that rebuilds succeed on modern Oracle versions without deprecated-keyword errors.

#### Acceptance Criteria

1. WHEN Rebuild constructs an `ALTER INDEX … REBUILD` statement, THE Index_Tool SHALL use the `NOLOGGING` keyword instead of the deprecated `UNRECOVERABLE` keyword.
2. WHEN Rebuild constructs an `ALTER INDEX … REBUILD` statement for an index in an LMT tablespace with ASSM, THE Index_Tool SHALL omit the `STORAGE` clause entirely.
3. WHEN Rebuild is invoked, THE Index_Tool SHALL use `EXECUTE IMMEDIATE` for all dynamic SQL statements instead of the `DBMS_SQL` package.
4. WHEN Rebuild determines that the target tablespace uses ASSM, THE Index_Tool SHALL skip the `ALTER TABLESPACE … COALESCE` step and the `dba_free_space` space-verification step.
5. WHEN Rebuild determines that the target tablespace is dictionary-managed, THE Index_Tool SHALL retain the `ALTER TABLESPACE … COALESCE` step and the `dba_free_space` space-verification step.
6. WHEN Rebuild completes all scheduled indexes, THE Index_Tool SHALL set `index_tool_control.status` to `'IDLE'` for program_id `'REBUILD'`.

### Requirement 7: Modernise the Verify Function

**User Story:** As a DBA, I want the `verify` function to correctly handle ASSM tablespaces, so that space checks do not incorrectly block rebuilds in modern environments.

#### Acceptance Criteria

1. WHEN Verify is called with a tablespace that uses ASSM, THE Index_Tool SHALL return `TRUE` without querying `dba_free_space`.
2. WHEN Verify is called with a dictionary-managed tablespace, THE Index_Tool SHALL retain the existing `dba_free_space` checks for initial extent, next extent, and total free blocks.
3. WHEN Verify determines that a dictionary-managed tablespace has insufficient free space after three attempts, THE Index_Tool SHALL set `site_index_rebuilds.status` to `'FAILED'` and record a descriptive message.

### Requirement 8: Modernise Job Scheduling

**User Story:** As a DBA, I want the tool to schedule its weekly job using `DBMS_SCHEDULER`, so that the job is visible in `dba_scheduler_jobs` and manageable with current Oracle tooling.

#### Acceptance Criteria

1. THE Index_Tool installation script SHALL create a `DBMS_SCHEDULER` job named `'SITEDBA.INDEX_TOOL_WEEKLY'` that calls `collect`, `analyse`, `schedule`, and `rebuild` in sequence.
2. THE Index_Tool installation script SHALL schedule the job to run every Saturday at 09:00 using a `DBMS_SCHEDULER` repeat interval.
3. THE Index_Tool installation script SHALL NOT use `DBMS_JOB.ISUBMIT` or any other `DBMS_JOB` API.
4. WHEN the installation script is run on a database where the job already exists, THE Index_Tool SHALL drop and recreate the job without error.

### Requirement 9: Modernise DDL and Schema Objects

**User Story:** As a DBA, I want all table and index DDL to be compatible with LMT/ASSM tablespaces, so that the installation script runs without errors on modern Oracle databases.

#### Acceptance Criteria

1. THE Index_Tool installation script SHALL create all tables and indexes without `STORAGE (INITIAL … NEXT … PCTINCREASE …)` clauses.
2. THE Index_Tool installation script SHALL replace the `BITMAP INDEX` on `site_index_stats(status)` with a B-tree index, consistent with the existing `site_index_rebuilds_n2` index.
3. THE Index_Tool installation script SHALL use a `CREATE … IF NOT EXISTS` guard or equivalent `EXECUTE IMMEDIATE` with exception handling so that re-running the script on an existing schema does not raise `ORA-00955` errors.
4. THE Index_Tool installation script SHALL NOT contain a hardcoded `connect / as sysdba` statement; instead, the script SHALL document that the DBA must connect as `sysdba` before running it.

### Requirement 10: Implement Automated Tests

**User Story:** As a DBA or developer, I want an automated test suite for Index_Tool, so that regressions can be detected after changes.

#### Acceptance Criteria

1. THE Index_Tool test suite SHALL include a test that calls `collect` against a known set of indexes and verifies that corresponding rows are inserted into `site_index_stats` with `status = 'COMPLETED'`.
2. THE Index_Tool test suite SHALL include a test that calls `analyse` after `collect` and verifies that indexes exceeding any configured Threshold are inserted into `site_index_rebuilds` with `status = 'SUBMITTED'`.
3. THE Index_Tool test suite SHALL include a test that calls `report` and verifies that output is produced without raising an exception.
4. THE Index_Tool test suite SHALL include a test that calls `select_tablespaces` and verifies that `site_index_moves` is populated when matching tablespace names exist.
5. THE Index_Tool test suite SHALL include a round-trip test: after `collect`, `analyse`, `schedule`, `rebuild`, and `purge` are called in sequence, THE Index_Tool SHALL leave `index_tool_control` with all program statuses set to `'IDLE'`.
6. THE Index_Tool test suite SHALL include a test that verifies `get_site_param_value` raises `ORA-20000` when a requested parameter does not exist in `site_parameters`.
7. THE Index_Tool test suite SHALL include a test that verifies `purge` removes all `site_index_stats` and `site_index_rebuilds` records with `timestamp` older than the supplied cutoff date and retains all records with `timestamp` on or after the cutoff date.

### Requirement 11: Generate User Documentation

**User Story:** As a DBA, I want up-to-date documentation for Index_Tool, so that I can install, configure, and operate the tool without reading the source code.

#### Acceptance Criteria

1. THE Index_Tool documentation SHALL describe the installation prerequisites including required Oracle privileges and minimum Oracle version (19c).
2. THE Index_Tool documentation SHALL document every public procedure and function in `index_tool`, including parameter descriptions, default values, and expected behaviour.
3. THE Index_Tool documentation SHALL document every row in `site_parameters` including the parameter name, domain, default value, and effect on tool behaviour.
4. THE Index_Tool documentation SHALL include a step-by-step operational guide covering: initial installation, first-run collection, reviewing the report, confirming rebuilds, and verifying completion.
5. THE Index_Tool documentation SHALL document the `DBMS_SCHEDULER` job name, schedule, and instructions for enabling, disabling, and manually running the job.

### Requirement 12: Time-Constrained Execution

**User Story:** As a DBA, I want to be able to start Index_Tool procedures with time constraints (e.g. finish within x minutes or run between x and y clock times), so that the tool does not overrun maintenance windows or interfere with production workloads.

#### Acceptance Criteria

1. WHEN a procedure is invoked, THE Index_Tool SHALL accept an optional `v_end_time` parameter of type `DATE` representing the wall-clock deadline after which no new index operations shall be started.
2. WHEN a procedure is invoked, THE Index_Tool SHALL accept an optional `v_max_minutes` parameter of type `NUMBER` representing the maximum elapsed minutes from invocation after which no new index operations shall be started.
3. WHEN both `v_end_time` and `v_max_minutes` are supplied, THE Index_Tool SHALL use whichever deadline is earlier.
4. WHEN neither `v_end_time` nor `v_max_minutes` is supplied, THE Index_Tool SHALL read default values from `site_parameters` using domain `'INDEX_TOOL'` and names `'DEFAULT_END_TIME'` (stored as `HH24:MI`) and `'DEFAULT_MAX_MINUTES'`; if neither parameter exists the procedure SHALL run without a time constraint.
5. BEFORE starting each individual index operation (collect, rebuild), THE Index_Tool SHALL check whether the current time has reached or exceeded the effective deadline; if so it SHALL skip the remaining operations, record a `'TIMED_OUT'` status in `index_tool_control.message`, set `index_tool_control.status` to `'IDLE'`, commit, and return.
6. WHEN an index operation is skipped due to a time constraint, THE Index_Tool SHALL leave the corresponding `site_index_stats` or `site_index_rebuilds` record in its current status (e.g. `'SUBMITTED'` or `'RETRY'`) so that it is picked up on the next run.
7. THE Index_Tool test suite SHALL include a test that sets a deadline in the past and verifies that `collect` and `rebuild` skip all index operations and set `index_tool_control.message` to indicate a timeout.

### Requirement 12: Control functionality

**User Story:** As a DBA, I want to be able to start index tool procedures with time constraints (e.g.  finish within x minutes or run between x and y clock times).

#### Acceptance Criteria

1. The tool should let me specify duration or wall clock times when calling procedures or functions or use them from a central look up which can be updated as requried.
2. Procedures and functions should not tasks that don't finish in time and skip such tasks and end gracefully.