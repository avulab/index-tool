REM $Header: indxtool.sql,v 1.1 2003/02/20 10:19:42 oracle Exp $
REM Desc: Script to install index analysis tool
REM Author: Bala Avula - Kinetic Software Ltd
REM Install: sqlplus /nolog @indxtool.sql
REM $Log:	indxtool.sql,v $
REM Revision 1.1  2003/02/20  10:19:42  10:19:42  oracle ()
REM Initial revision
REM 
REM
REM    Rev 1.15   Sep 09 2002 14:46:06   655246
REM ..
REM
REM    Rev 1.14   Mar 18 2002 11:52:06   858016
REM  Move index build after creat table stmt
REM
REM    Rev 1.13   Nov 16 2001 17:30:02   655246
REM  Checking reference feature in PVCS
REM
REM    Rev 1.12   Nov 15 2001 12:43:00   655244
REM  Remove index bebuilds based on blk_gets_per_access as the
REM  field trials proved that this is not a valid criteria to use in field.
REM
REM    Rev 1.11   Sep 28 2001 16:59:26   655244
REM  Change Collect proedure to use dba_segments
REM
REM    Rev 1.10   Sep 27 2001 17:04:36   655244
REM  Tested with Oracle 9i.  Noticed that script can not
REM  handle partitioned indexes and index organised tables.
REM  Currently IOTs are ignored with messages and partitions are
REM  ignored in "collect" procedure. These objects can be handled in the
REM  future versions of index tool.
REM
REM    Rev 1.9   Sep 12 2001 17:20:02   655244
REM  Functionality added to move indexes between tablespaces.
REM  Turn on functionality using site_parameters tables.
REM  Set parameter MOVE_INDEXES to TRUE
REM  Specify source and target tablespaces in site_index_moves
REM
REM    Rev 1.8   Sep 04 2001 12:09:30   655244
REM  Improvements to handle PCT Used differently. Only rebuild when
REM  PCT_USED drops less than average by a threshold.
REM
REM    Rev 1.7   Aug 28 2001 15:01:14   655244
REM  Additional code added for session kill
REM
REM    Rev 1.6   Jun 05 2001 12:20:32   655244
REM  Lack of space errors ORA-1652 is handled similar to resource busy.
REM  Attempt to rebuild for three times 
REM  and fail on third attempt if space can not be found.
REM
REM    Rev 1.5   May 22 2001 18:18:40   655244
REM  Version with soft coded parameters and simple installation.
REM
REM    Rev 1.4   May 14 2001 14:47:18   655244
REM  Improved error handling. Pass errors to job queue so that they
REM  can be captured by alert log monitoring tools liks Iwatch
REM
REM    Rev 1.3   May 14 2001 13:08:38   655244
REM  Added blocks column as it is NOT NULL in Oracle 7x
REM
REM    Rev 1.2   May 11 2001 10:17:10   655244
REM  Typo on index_tablespace variable
REM
REM    Rev 1.1   May 01 2001 15:38:10   655244
REM  First production version
REM
REM    Rev 1.0   Apr 24 2001 16:28:12   655244
REM  Index rebuild script. First version
REM  Possible improvements.
REM  1.  Analysis and Report improvements
REM  2.  List tablespaces for placement of objects
REM  3.  Move indexes to different tablespaces
REM  4.  Hardcoded variables (e.g. six months) 
REM 	 to be softcoded from a control table
REM  5.  Logic like (e.g. schedule procedure) to be softcoded in a control table
REM
REM 
REM OS Authentication should bet setup
connect / as sysdba

REM  Alter current schema to procedure owner for creation of objects
ALTER SESSION SET current_schema=sitedba
/

REM Create Objects in the procedure owner

create sequence index_tool_seq
/
PROMPT List of tablespaces with enough free space
SELECT DISTINCT tablespace_name
  FROM user_free_space
WHERE bytes >= 65536 /* 64KB */
/
create table site_index_stats
tablespace &&data_tablespace
storage(initial 64K next 64K pctincrease 0)
PCTFREE 40 /* To allow updates from index_stats */
as select index_tool_seq.nextval record_id,
		user owner,
		sysdate timestamp,
		'1234567890'status,
		9 runcount,
		'12345678901234567890123456789012345678901234567890123456789012345678901234567890' message, /* VARCHAR2(80) */
		a.*
     from index_stats a
    where rownum < 1
/
alter table site_index_stats
	add constraint site_index_stats_pk
		primary key (record_id)
		using index tablespace &&index_tablespace
			storage(initial 16K next 16K pctincrease 0)
/

create table site_index_moves (source_tablespace VARCHAR2(30),
			       destination_tablespace VARCHAR2(30))
tablespace &&data_tablespace
storage(initial 64K next 64K pctincrease 0)
PCTFREE 5 /* There should not be any big updates */
/
alter table site_index_moves
	add constraint site_index_moves_pk
		primary key (source_tablespace, destination_tablespace)
		using index tablespace &&index_tablespace
			storage(initial 16K next 16K pctincrease 0)
/

CREATE INDEX site_index_stats_n1 ON site_index_stats(owner, name)
TABLESPACE &&index_tablespace
STORAGE (INITIAL 16K NEXT 16K PCTINCREASE 0)
/
CREATE BITMAP INDEX site_index_stats_n2 ON site_index_stats(STATUS)
TABLESPACE &&index_tablespace
STORAGE (INITIAL 16K NEXT 16K PCTINCREASE 0)
/
create table site_index_rebuilds(record_id NUMBER,
				 owner VARCHAR2(30)  NOT NULL,
				 name VARCHAR2(30) NOT NULL,
                              	 status VARCHAR2(10) NOT NULL,
                                 concat CHAR(1) DEFAULT 'N' NOT NULL,
				 reason VARCHAR2(80),
				 timestamp date default SYSDATE NOT NULL,
				 runcount NUMBER DEFAULT 0,
				 message VARCHAR2(100)
                         )
tablespace &&data_tablespace
storage(initial 64K next 64K pctincrease 0)
PCTFREE 0
/
alter table site_index_rebuilds
	add constraint site_index_rebuilds_pk
		primary key (record_id)
		using index tablespace &&index_tablespace
			storage(initial 16K next 16K pctincrease 0)
/
CREATE INDEX site_index_rebuilds_n1 ON site_index_rebuilds(owner, name)
TABLESPACE &&index_tablespace
STORAGE (INITIAL 16K NEXT 16K PCTINCREASE 0)
/

REM Changed from BITMAP INDEX to B-Tree index to avoid ORA-01410 errors
CREATE INDEX site_index_rebuilds_n2 ON site_index_rebuilds(status)
TABLESPACE &&index_tablespace
STORAGE (INITIAL 16K NEXT 16K PCTINCREASE 0)
/


create table index_tool_control(program_id VARCHAR2(10),
				 status VARCHAR2(10) NOT NULL,
				 timestamp date DEFAULT SYSDATE NOT NULL,
				 message VARCHAR2(100))
tablespace &&data_tablespace
storage(initial 64K next 64K pctincrease 0)
PCTFREE 0
/
alter table index_tool_control
	add constraint index_tool_control_pk
		primary key (program_id)
		using index tablespace &&index_tablespace
			storage(initial 16K next 16K pctincrease 0)
/
REM Create control records where control is required
INSERT INTO index_tool_control(program_id, status) values('COLLECT', 'IDLE')
/
INSERT INTO index_tool_control(program_id, status) values('REBUILD', 'IDLE')
/

create table site_parameters(domain VARCHAR2(30),
				 name VARCHAR2(30) NOT NULL,
				 value VARCHAR2(30))
tablespace &&data_tablespace
storage(initial 64K next 64K pctincrease 0)
PCTFREE 0
/
alter table site_parameters
	add constraint site_parameters_pk
		primary key (domain,name)
		using index tablespace &&index_tablespace
			storage(initial 16K next 16K pctincrease 0)
/
REM Create entries for parameters where hard coding can be reduced
INSERT INTO site_parameters(domain, name, value)
	/* The threshold of %change from average PCT_USED figures */
	VALUES('INDEX_TOOL', 'PCT_USED_CHANGE_THRESHOLD', '10')
/
INSERT INTO site_parameters(domain, name, value)
	/* This threshold can be 20 if too many rebuilds are happening */
	VALUES('INDEX_TOOL', 'PCT_DELETE_THRESHOLD', '10')
/
INSERT INTO site_parameters(domain, name, value)
	/* This threshold can be 5 if too many rebuilds are happening */
	VALUES('INDEX_TOOL', 'BTREE_HEIGHT_THRESHOLD', '4')
/
INSERT INTO site_parameters(domain, name, value)
	/* This threshold can be increased if you want to reduce rebuild 
frequencey*/
	VALUES('INDEX_TOOL', 'AGE_THRESHOLD', '90' /* Value in Days */)
/
INSERT INTO site_parameters(domain, name, value)
	/* This threshold can be reduced if you want to reduce rebuild frequencey*/
	VALUES('INDEX_TOOL', 'DISTINCTIVENESS_THRESHOLD', '30')
/

INSERT INTO site_parameters(domain, name, value)
	/* Should indexes be moved to another tablespace */
	VALUES('INDEX_TOOL', 'MOVE_INDEXES', 'TRUE')
/


CREATE OR REPLACE PACKAGE index_tool IS

-- Variables for use in the package
v_buff VARCHAR2(10000);
v_revision VARCHAR2(100) := '$Revision: 1.1 $';
v_status index_tool_control.status%TYPE;
v_retcode NUMBER;
v_concat CHAR(1);
v_cur_handle INTEGER;
v_move_indexes VARCHAR2(10);
resource_busy EXCEPTION;
PRAGMA EXCEPTION_INIT(resource_busy, -54);
lack_of_space EXCEPTION;
PRAGMA EXCEPTION_INIT(lack_of_space, -1652);
instance_shutdown EXCEPTION;
PRAGMA EXCEPTION_INIT(instance_shutdown, -1089);
session_killed EXCEPTION;
PRAGMA EXCEPTION_INIT(session_killed, -28);
index_organised_table EXCEPTION;
PRAGMA EXCEPTION_INIT(index_organised_table, -28650);


  CURSOR cur_rebuild IS /* Cursor for rebuilds */
	SELECT a.record_id,
                a.owner,
                a.name,
                a.runcount,
                DECODE(v_move_indexes,
		       'TRUE', NVL(d.destination_tablespace, b.tablespace_Name),
			b.tablespace_name) tablespace_name,
		c.initial_extent,
		b.bytes,
		/* for the bizzare cases where next_extent is NULL in
			dba_indexes view */
		NVL(c.next_extent, c.initial_extent) next,
                c.min_extents minimum,
                c.max_extents maximum,
		/* for the bizzare cases where pct_increase is NULL in
			dba_indexes view */
                NVL(c.pct_increase, 0) incr
          FROM site_index_rebuilds a,
               dba_segments b,
               dba_indexes c,
	       site_index_moves d
         WHERE a.status NOT IN ('COMPLETED', 'FAILED')
           AND a.owner = b.owner
           AND a.name = b.segment_name
           AND a.owner = c.owner
           AND a.name = c.index_name
           AND b.tablespace_name=d.source_tablespace (+)
	   AND b.segment_type = 'INDEX';

   CURSOR cur_collect
		 IS SELECT record_id, owner, name index_name, runcount
		     FROM site_index_stats  /* Cursor for collect */
		    WHERE status IN ('SUBMITTED', 'RETRY');

   CURSOR cur_schedule
		 IS SELECT MAX(record_id) record_id
		     FROM site_index_stats  /* Cursor for schdule */
		    GROUP BY owner,name;


   CURSOR cur_index_tool_control(v_program_id IN VARCHAR2) IS
            SELECT STATUS /* Cursor retrieving module status */
              FROM index_tool_control
             WHERE program_id = v_program_id;

   CURSOR cur_site_parameters(v_domain IN VARCHAR2, v_name IN VARCHAR2) IS
            SELECT value /* Cursor retrieving site parameters */
              FROM site_parameters
             WHERE domain = v_domain
               AND name = v_name;

   CURSOR cur_rpt IS
	 SELECT a.owner,
		a.name,
		a.height,
		a.del_lf_rows/
		   DECODE(a.lf_rows,0,1,a.lf_rows)*100 "%Deletes - Current",
		(a.lf_rows-a.distinct_keys)*100/
		   DECODE(a.lf_rows,0,1,a.lf_rows)  "Distinveness - Current",
		b.avg_deletes "%Deletes - Average",
		b.min_deletes "%Deletes - Minimum",
		b.max_deletes "%Deletes - Maximum",
		a.pct_used "%Used - Current",
		b.avg_pct_used "%Used - Average",
		b.min_pct_used "%Used - Minimum",
		b.max_pct_used "%Used - Maximum"
	  FROM site_index_stats a,
               (SELECT owner,
			name,
			avg(pct_used) avg_pct_used,
			min(pct_used) min_pct_used,
			max(pct_used) max_pct_used,
                        avg(del_lf_rows/
				DECODE(lf_rows,0,1,lf_rows))*100 avg_deletes,
                        min(del_lf_rows/
				DECODE(lf_rows,0,1,lf_rows))*100 min_deletes,
                        max(del_lf_rows/
				DECODE(lf_rows,0,1,lf_rows))*100 max_deletes
                  FROM site_index_stats
                GROUP BY owner, name) b
	 WHERE a.record_id = (SELECT max(c.record_id)
				FROM site_index_stats c
			       WHERE a.owner = c.owner
				 AND a.name = c.name) /* Get current record */
           AND a.owner = b.owner
           AND a.name = b.name;

   procedure collect (v_schema VARCHAR2 DEFAULT NULL,
                   v_table  VARCHAR2 DEFAULT NULL,
                   v_idx    VARCHAR2 DEFAULT NULL,
                   v_trace_lvl  NATURAL := 0); /* Collect index stats */

   -- Following three modules not yet implemented
   procedure analyse (v_schema VARCHAR2 DEFAULT NULL,
                   v_table  VARCHAR2 DEFAULT NULL,
                   v_idx    VARCHAR2 DEFAULT NULL,
                   v_trace_lvl  NATURAL := 0); /* Analyse collected data */
   procedure report (v_schema VARCHAR2 DEFAULT NULL,
                   v_table  VARCHAR2 DEFAULT NULL,
                   v_idx    VARCHAR2 DEFAULT NULL,
                   v_trace_lvl  NATURAL := 0); /* Reports from analysis */
   procedure confirm (v_schema VARCHAR2 DEFAULT NULL,
                   v_table  VARCHAR2 DEFAULT NULL,
                   v_idx    VARCHAR2 DEFAULT NULL,
                   v_trace_lvl  NATURAL := 0); /* Confirm index rebuilds */
   -- Following modules are implemented
   procedure schedule (v_schema VARCHAR2 DEFAULT NULL,
                   v_table  VARCHAR2 DEFAULT NULL,
                   v_idx    VARCHAR2 DEFAULT NULL,
                   v_trace_lvl  NATURAL := 0); /* Schedule index rebuilds */
   procedure rebuild (v_schema VARCHAR2 DEFAULT NULL,
                   v_table  VARCHAR2 DEFAULT NULL,
                   v_idx    VARCHAR2 DEFAULT NULL,
                   v_trace_lvl  NATURAL := 0); /* Rebuild indexes */

   PROCEDURE purge (v_purge_date DATE DEFAULT add_months(SYSDATE,-24),
                   v_trace_lvl  NATURAL := 0); /* Purge index tool data */

   PROCEDURE select_tablespaces (v_trace_lvl  NATURAL := 0); 
	/* Select tablespaces for
	index move and pouplate site_index_moves table */

	-- Return set value for a given parameter
   FUNCTION get_site_param_value (v_domain VARCHAR2,
                                      v_name  VARCHAR2)
			RETURN VARCHAR2;

   PROCEDURE update_index_tool_control (v_program_id VARCHAR2,
				      v_message VARCHAR2);
		-- Utility procedure for updating status
  /* Same procedure with operator overloading */
   PROCEDURE update_index_tool_control (v_program_id VARCHAR2,
				      v_status VARCHAR2,
				      v_message VARCHAR2);
		-- Utility procedure for updating status
END index_tool;
/

CREATE OR REPLACE PACKAGE BODY index_tool IS


				/* Verify index for free space */
   FUNCTION verify (v_record_id NUMBER,
		    v_tablespace_name VARCHAR2,
		    v_concat IN OUT CHAR,
                    v_trace_lvl  NATURAL := 0) RETURN BOOLEAN;

	-- Report module status from control table
   FUNCTION index_tool_control_status (v_program_id VARCHAR2,
                                      v_trace_lvl  NATURAL := 0)
			RETURN VARCHAR2;
   procedure collect (v_schema VARCHAR2 DEFAULT NULL,
                   v_table  VARCHAR2 DEFAULT NULL,
                   v_idx    VARCHAR2 DEFAULT NULL,
                   v_trace_lvl  NATURAL := 0)
/*
Procedure which collects statistics for given or ALL index(s)
Set serveroutput on and pass trace level value of 1 or more for listing
of analyzed indexes.
*/
      IS
      BEGIN

          IF index_tool_control_status('COLLECT')  
			IN ('QUIT', 'FAILED') THEN
             update_index_tool_control('COLLECT', 
					'Status set to QUIT or FAILED');
             COMMIT WORK;
	     RETURN;
	  ELSE
		update_index_tool_control('COLLECT','RUNNING', 
						'Starting collection');
		INSERT INTO site_index_stats(record_id,
					  owner,
					  name,
					  blocks,
					  status,
					  timestamp,
					  runcount)
		 SELECT index_tool_seq.nextval,
			a.owner,
			a.segment_name,
			0, /* Added for Oracle7 as BLOCKS column is NOT NULL*/
			'SUBMITTED',
			SYSDATE,
			0 /* Initialise runcount */
		     FROM dba_segments a /* Cursor for collect */
		    WHERE a.owner LIKE NVL(v_schema, '%')
		      AND a.segment_name  LIKE NVL(v_idx, '%')
                      AND a.segment_type = 'INDEX'
		      AND a.owner NOT IN ('SYS', 'SYSTEM')
		      AND NOT EXISTS (SELECT 'x'
		     			FROM site_index_stats b
		    		       WHERE b.owner = a.owner
				         AND b.name  = a.segment_name
					 AND b.status IN ('SUBMITTED','RETRY'));
	 	COMMIT WORK;
	     	v_cur_handle := dbms_sql.open_cursor;
          END IF;

	  FOR each_rec IN cur_collect
	  LOOP
	     IF v_trace_lvl > 0 THEN
		dbms_output.put_line('Validating index '||each_rec.owner||'.'||
				     each_rec.index_name);
	     END IF;

	     /* ONLINE keyword added for 9i+ databases */
	     v_buff := 'ANALYZE INDEX '||each_rec.owner||'.'||
		       each_rec.index_name||' VALIDATE STRUCTURE ONLINE';


	     IF v_trace_lvl > 1 THEN
		dbms_output.put_line(v_buff);
	     END IF;

             IF index_tool_control_status('COLLECT')  =  'QUIT' THEN
		     update_index_tool_control('COLLECT', 'Quiting on message');
		     COMMIT WORK;
		     RETURN;
	     END IF;

             BEGIN
		     dbms_sql.parse(v_cur_handle, v_buff, dbms_sql.native);
		     v_retcode := dbms_sql.execute(v_cur_handle);
                     DELETE FROM site_index_stats
			    WHERE record_id=each_rec.record_id;
		     INSERT INTO site_index_stats
			/* This statement would not work if index_stats */
	      		SELECT index_tool_seq.nextval, /* view changes */
				each_rec.owner,
				SYSDATE,
				'COMPLETED',
				each_rec.runcount+1,
				'SUCCESSFUL Collect',
				a.*
			from index_stats a;

	             COMMIT WORK;

             EXCEPTION
                 WHEN resource_busy THEN /* We should see none of these after ONLINE operations in 9i+ */
			UPDATE site_index_stats
			   SET status = DECODE(each_rec.runcount,
						2,'FAILED', 'RETRY'),
			       timestamp = SYSDATE,
			       runcount = runcount+1,
			       message = DECODE(each_rec.runcount,
						2, 
					'Three tries failed due to lock',
					        'Resource busy - retry')
			 WHERE record_id=each_rec.record_id;
                 WHEN OTHERS THEN
			RAISE; /* Pass exception handling to next level */
	     END; -- End of Anonymous block


	  END LOOP; -- Cur_Collect for loop

	  dbms_sql.close_cursor(v_cur_handle);
          update_index_tool_control('COLLECT','IDLE', 
						'Completed Collection');
	  COMMIT WORK; /* Close cursor and COMMIT any changes */

      EXCEPTION
	  WHEN instance_shutdown OR session_killed THEN
	      update_index_tool_control('COLLECT', 'IDLE', 
			'Collection stopped due to instance shutdown');
              IF dbms_sql.is_open(v_cur_handle) THEN
			dbms_sql.close_cursor(v_cur_handle);
	      END IF;
	      COMMIT WORK;
          WHEN OTHERS THEN
              IF dbms_sql.is_open(v_cur_handle) THEN
			dbms_sql.close_cursor(v_cur_handle);
	      END IF;
              update_index_tool_control('COLLECT','FAILED', SQLERRM);
              COMMIT WORK;
	      RAISE; /* Once recorded in control table pass it to Job Queue */
      END collect;

/* This procedure is not yet implemented */
   procedure analyse (v_schema VARCHAR2 DEFAULT NULL,
                   v_table  VARCHAR2 DEFAULT NULL,
                   v_idx    VARCHAR2 DEFAULT NULL,
                   v_trace_lvl  NATURAL := 0) IS
   BEGIN
	null;
   END analyse;

   PROCEDURE purge (v_purge_date    DATE DEFAULT add_months(SYSDATE, -24),
                   v_trace_lvl  NATURAL := 0) IS
   BEGIN

	LOOP /* Delete 10000 rows at a time */
		DELETE 
		  FROM site_index_stats
		 WHERE timestamp <v_purge_date
		   AND ROWNUM <=10000;

		IF SQL%NOTFOUND THEN
			EXIT;
		END IF;

	END LOOP;

	LOOP /* Delete 10000 rows at a time */
		DELETE 
		  FROM site_index_rebuilds
		 WHERE timestamp <v_purge_date
		   AND ROWNUM <=10000;

		IF SQL%NOTFOUND THEN
			EXIT;
		END IF;

	END LOOP;

   END purge;

/* This procedure is not yet implemented */
   PROCEDURE select_tablespaces (v_trace_lvl  NATURAL := 0) IS
   BEGIN
	
	NULL; -- To be implemented with care

	/* Select source and destination tablespaces based on
	         tablespace usage and tablespace name */
	/* Some example logic to use here would ...
	 1. Select source and destination tablespaces based on segment types
	      E.g. High table segments mean source tablespace and
		   High index segments mean target tablespace
	 2. Select source and destination tablespaces based on names
	      E.g. %INDEX%, %IDX%, %INDX%, and %X are target tablespaces
	      E.g. %DATA% and %D are source tablespaces
       */

   END select_tablespaces;

/* This procedure is not yet implemented */
   procedure confirm (v_schema VARCHAR2 DEFAULT NULL,
                    v_table  VARCHAR2 DEFAULT NULL,
                   v_idx    VARCHAR2 DEFAULT NULL,
                   v_trace_lvl  NATURAL := 0) IS
    BEGIN
        null;
    END confirm;

/* This procedure is not yet implemented */
   procedure report (v_schema VARCHAR2 DEFAULT NULL,
                   v_table  VARCHAR2 DEFAULT NULL,
                   v_idx    VARCHAR2 DEFAULT NULL,
                   v_trace_lvl  NATURAL := 0) IS
   BEGIN
        FOR each_rec IN cur_rpt LOOP
		NULL;
	END LOOP;
   END report;

/* Function to retrieve status from index_tool_control table */

   FUNCTION index_tool_control_status (v_program_id VARCHAR2,
                                      v_trace_lvl  NATURAL := 0)
			RETURN VARCHAR2 IS
   BEGIN

          OPEN cur_index_tool_control(v_program_id);
          FETCH cur_index_tool_control INTO v_status;
          CLOSE cur_index_tool_control;
          RETURN v_status;
   END index_tool_control_status;

/* Procedure to update control table entry */
   PROCEDURE update_index_tool_control (v_program_id VARCHAR2,
				      v_status VARCHAR2,
				      v_message VARCHAR2) IS
   BEGIN

          UPDATE index_tool_control
             SET status =v_status,
                 timestamp = SYSDATE,
                 message = v_message
           WHERE program_id = v_program_id;

   END update_index_tool_control;

/* Overloaded procedure to update control table entry */
   PROCEDURE update_index_tool_control (v_program_id VARCHAR2,
				      v_message VARCHAR2) IS
   BEGIN

          UPDATE index_tool_control
             SET timestamp = SYSDATE,
                 message = v_message
           WHERE program_id = v_program_id;

   END update_index_tool_control;

/* Verify a given index for free space in target tablespace
					and update rebuild table 
   THIS FUNCTION NEEDS TO CHANGE FOR LOCALLY MANAGED TABLESPACES WITH AUTOMATCIC SPACE MANAGEMENT */

   FUNCTION verify (v_record_id NUMBER,
		    v_tablespace_name VARCHAR2,
		    v_concat IN OUT CHAR,
                    v_trace_lvl  NATURAL := 0) RETURN BOOLEAN IS
   BEGIN
	UPDATE site_index_rebuilds a
           SET a.concat='Y',
		 /* If not enough space for concat set it to false */
               a.timestamp=SYSDATE,
               a.message = 'Concat verified',
               a.status = 'VERIFIED'
         WHERE a.record_id = v_record_id
           AND EXISTS (SELECT 'x'
			     FROM dba_free_space b,
				  dba_segments c
			    WHERE b.tablespace_name=v_tablespace_name
			      AND a.owner = c.owner
			      AND a.name = c.segment_name
			      AND c.segment_type = 'INDEX'
			      AND b.blocks >= c.blocks);

        IF SQL%ROWCOUNT > 1 THEN
		RAISE too_many_rows;
	END IF;

        IF SQL%ROWCOUNT = 1 THEN
		v_concat := 'Y';
		RETURN TRUE;
	END IF;

	UPDATE site_index_rebuilds a
           SET a.status = 'VERIFIED',
		 /* If not enough space for concat set it to false */
               a.timestamp=SYSDATE,
               a.message = 'Free space verified'
         WHERE a.record_id = v_record_id
           AND a.concat = 'N'
           AND EXISTS (SELECT 'x' 
				/* Check that space exists for initial extent */
			     FROM dba_free_space b,
				  dba_segments c
			    WHERE b.tablespace_name=v_tablespace_name
			      AND a.owner = c.owner
			      AND a.name = c.segment_name
			      AND c.segment_type = 'INDEX'
			      AND b.bytes >= c.initial_extent)
           AND EXISTS (SELECT 'x' 
			/* Check that space exists for next extent */
			     FROM dba_free_space b,
				  dba_segments c
			    WHERE b.tablespace_name=v_tablespace_name
			      AND a.owner = c.owner
			      AND a.name = c.segment_name
			      AND c.segment_type = 'INDEX'
			      AND b.bytes >= c.next_extent)
           AND EXISTS (SELECT 'x' 
			/* Check that enough free space exists for rebuild */
			     FROM (SELECT tablespace_name,
				          SUM(blocks) ts_free_blocks
                                     FROM dba_free_space
				    GROUP BY tablespace_name) b,
				  dba_segments c
			    WHERE b.tablespace_name=v_tablespace_name
			      AND a.owner = c.owner
			      AND a.name = c.segment_name
			      AND c.segment_type = 'INDEX'
			      AND b.ts_free_blocks >= c.blocks);

        IF SQL%ROWCOUNT > 1 THEN
		RAISE too_many_rows;
	END IF;

        IF SQL%ROWCOUNT = 1 THEN
		v_concat := 'N';
		RETURN TRUE;

	ELSE
		UPDATE site_index_rebuilds a
		   SET status = DECODE(runcount, 2,'FAILED', 'RETRY'),
		       timestamp = SYSDATE,
		       runcount = runcount+1,
		       message = DECODE(runcount,
					2, 
				'Three tries failed due to lack of space',
					'Lack of space - retry')
	         WHERE a.record_id = v_record_id;
	        RETURN FALSE;
	END IF;

   END verify;


/* Function to retrieve site_param_value from site_parameters table */

   FUNCTION get_site_param_value (v_domain VARCHAR2, v_name VARCHAR2)
			RETURN VARCHAR2 IS
	v_value site_parameters.value%TYPE;
   BEGIN
	  OPEN cur_site_parameters(v_domain, v_name);
	  FETCH cur_site_parameters INTO v_value;
	  IF cur_site_parameters%NOTFOUND THEN
		CLOSE cur_site_parameters;
		raise_application_error (-20000, 'Parameter '||v_name||
		' for '||v_domain||' not found in configuration table ');
	  END IF;
	  CLOSE cur_site_parameters;
          RETURN v_value;
   END get_site_param_value;

/* Schedules indexes for rebuild */
   procedure schedule (v_schema VARCHAR2 DEFAULT NULL,
                   v_table  VARCHAR2 DEFAULT NULL,
                   v_idx    VARCHAR2 DEFAULT NULL,
                   v_trace_lvl  NATURAL := 0) IS
	v_pct_used_change_threshold NUMBER := 
			get_site_param_value('INDEX_TOOL', 
						'PCT_USED_CHANGE_THRESHOLD');
	v_pct_delete_threshold NUMBER := 
			get_site_param_value('INDEX_TOOL', 
						'PCT_DELETE_THRESHOLD');
        v_distinctiveness_threshold NUMBER := 
			get_site_param_value('INDEX_TOOL', 
						'DISTINCTIVENESS_THRESHOLD');
        v_age_threshold NUMBER := 
			get_site_param_value('INDEX_TOOL', 
						'AGE_THRESHOLD');
        v_btree_height_threshold NUMBER := 
			get_site_param_value('INDEX_TOOL', 
						'BTREE_HEIGHT_THRESHOLD');
   BEGIN

	INSERT INTO site_index_rebuilds
		(record_id, owner, name, status, timestamp, reason)
          SELECT index_tool_seq.nextval, a.owner, a.index_name,
		'SUBMITTED', SYSDATE, 'Index being moved on request'
            FROM dba_indexes a
           WHERE v_move_indexes = 'TRUE'
	     AND a.tablespace_name IN (SELECT source_tablespace
				         FROM site_index_moves)
             AND NOT EXISTS (SELECT 'x'
        		       FROM site_index_rebuilds b
			      WHERE a.index_name = b.name
				AND b.owner = a.owner
				AND b.status != 'COMPLETED');
	COMMIT WORK;

     FOR each_rec IN cur_schedule LOOP

	INSERT INTO site_index_rebuilds
		(record_id, owner, name, status, timestamp, reason)
          SELECT index_tool_seq.nextval, a.owner, a.name, 'SUBMITTED', 
SYSDATE,
		 'Blevel higher than '||v_btree_height_threshold
            FROM site_index_stats a
           WHERE a.record_id = each_rec.record_id
	     AND a.height > v_btree_height_threshold
             AND NOT EXISTS (SELECT 'x'
        		       FROM site_index_rebuilds b
			      WHERE a.name = b.name
				AND b.owner = a.owner
				AND b.status != 'COMPLETED');

	INSERT INTO site_index_rebuilds
		(record_id, owner, name, status, timestamp, reason)
          SELECT index_tool_seq.nextval, a.owner, a.name, 'SUBMITTED', 
		 SYSDATE,
		 'PCT deleted more than '||
		 v_pct_delete_threshold||
		' and distintiveness less than '||v_distinctiveness_threshold
            FROM site_index_stats a
           WHERE a.record_id = each_rec.record_id
             AND a.del_lf_rows/
		   DECODE(a.lf_rows,0,1,a.lf_rows)*100 > 
			v_pct_delete_threshold /* PCT del > threshold% */
	     AND (a.lf_rows-a.distinct_keys)*100/
	   DECODE(a.lf_rows,0,1,a.lf_rows)  < v_distinctiveness_threshold
	     AND NOT EXISTS (SELECT 'x'
        		       FROM site_index_rebuilds b
			      WHERE a.name = b.name
				AND b.owner = a.owner
				AND b.status != 'COMPLETED');

	INSERT INTO site_index_rebuilds
		(record_id, owner, name, status, timestamp, reason)
          SELECT index_tool_seq.nextval, a.owner, a.name, 'SUBMITTED', 
SYSDATE,
		 'PCT Used less than average by'||
			v_pct_used_change_threshold||' %'
            FROM site_index_stats a
           WHERE a.record_id = each_rec.record_id
             AND a.pct_used /* PCT USED less than average by % threshold */
			< (SELECT avg(d.pct_used)*
					(1-v_pct_used_change_threshold/100)
			     FROM site_index_stats d
			    WHERE d.owner=a.owner
			      AND d.name=a.name)
	     AND NOT EXISTS (SELECT 'x'
        		       FROM site_index_rebuilds b
			      WHERE a.name = b.name
				AND b.owner = a.owner
				AND b.status != 'COMPLETED');

	INSERT INTO site_index_rebuilds
		(record_id, owner, name, status, timestamp, reason)
          SELECT index_tool_seq.nextval, a.owner, a.name, 'SUBMITTED', 
		SYSDATE,
		 'Index not rebuilt for more than '||v_age_threshold
            FROM site_index_stats a
           WHERE a.record_id = each_rec.record_id
             AND NOT EXISTS
			(SELECT 'x'
			   FROM site_index_rebuilds b
			  WHERE b.timestamp >= SYSDATE - v_age_threshold
				/* No rebuild for threshold days */
                            AND b.owner = a.owner
			    AND a.name = b.name);

      END LOOP; -- For each_rec in cur_schedule

	COMMIT WORK;

   END schedule;

/* Rebuild scheduled indexes */

   procedure rebuild (v_schema VARCHAR2 DEFAULT NULL,
                   v_table  VARCHAR2 DEFAULT NULL,
                   v_idx    VARCHAR2 DEFAULT NULL,
                   v_trace_lvl  NATURAL := 0) IS
   BEGIN
      IF index_tool_control_status('REBUILD')  IN ('FAILED', 'QUIT') THEN
             update_index_tool_control('REBUILD', 'Status set to QUIT or 
FAILED');
             COMMIT WORK;
	     RETURN;
      ELSE
	update_index_tool_control('REBUILD','RUNNING', 'Starting rebuild');
	COMMIT WORK;
	v_cur_handle := dbms_sql.open_cursor;
      END IF;

      FOR each_rec IN cur_rebuild
      LOOP
	     IF v_trace_lvl > 0 THEN
		dbms_output.put_line('Verifying index '||each_rec.owner||'.'||
				     each_rec.name);
	     END IF;

            /* THIS MAY BE UNNECESSARY FOR LOCALLY MANAGED TABLESPACES AUTOMATIC SEGMENT MANAGEMENT */
            v_buff := 'ALTER TABLESPACE '||each_rec.tablespace_name
		||' COALESCE';

	     dbms_sql.parse(v_cur_handle, v_buff, dbms_sql.native);
	     v_retcode := dbms_sql.execute(v_cur_handle);


            IF NOT verify(each_rec.record_id,
				each_rec.tablespace_name,v_concat) THEN
                    NULL; -- Skip this record If not verified
            ELSE
		   IF index_tool_control_status('REBUILD')  =  'QUIT' THEN
		     update_index_tool_control('REBUILD', 'Quiting on message');
		     COMMIT WORK;
		     RETURN;
   		   END IF;
                     /* ONLINE KEYWORD ADDED FOR 9i+ */
		     v_buff := 'ALTER INDEX '||each_rec.owner||'.'||
				each_rec.name
				||' REBUILD UNRECOVERABLE ONLINE TABLESPACE '
				||each_rec.tablespace_name;
		     v_buff := v_buff||' STORAGE (INITIAL ';
		     IF v_concat = 'Y' THEN
			 v_buff := v_buff||each_rec.bytes;
	             ELSE
			 v_buff := v_buff||each_rec.initial_extent;
		     END IF;
	             v_buff := v_buff||' NEXT '||each_rec.next
				||' MINEXTENTS '||each_rec.minimum||
				' MAXEXTENTS '||each_rec.maximum||
				' PCTINCREASE '||
				each_rec.incr||')';

	     		IF v_trace_lvl > 1 THEN
				dbms_output.put_line(v_buff);
		     END IF;

                     BEGIN
			     dbms_sql.parse(v_cur_handle, v_buff, 
							dbms_sql.native);
			     v_retcode := dbms_sql.execute(v_cur_handle);
			     UPDATE site_index_rebuilds
        		        SET status='COMPLETED',
                		    timestamp=SYSDATE,
				    runcount=runcount+1,
	                	    message='SUCCESSFUL REBUILD'
	        	      WHERE record_id = each_rec.record_id;
		             COMMIT WORK;
                     EXCEPTION
			WHEN resource_busy THEN
			     UPDATE site_index_rebuilds
			        SET status = DECODE(each_rec.runcount,
							2,'FAILED',
					        'RETRY'),
				    runcount = runcount+1,
			            timestamp = SYSDATE,
			            message = DECODE(each_rec.runcount,
						2, 
				'Unable to obtain lock on third attempt',
					        'Resource busy - retry')
	        	      WHERE record_id = each_rec.record_id;
		             COMMIT WORK;
			WHEN lack_of_space THEN
			     UPDATE site_index_rebuilds
			        SET status = DECODE(each_rec.runcount,
							2,'FAILED',
					        'RETRY'),
				    runcount = runcount+1,
			            timestamp = SYSDATE,
			            message = DECODE(each_rec.runcount,
						2, 
				'Unable to obtain space on third attempt',
					        'Lack of space - retry')
	        	      WHERE record_id = each_rec.record_id;
		             COMMIT WORK;
			WHEN index_organised_table THEN
			     UPDATE site_index_rebuilds
			        SET status = 'FAILED',
			            timestamp = SYSDATE,
			            message = 
	'Index Organised Table rebuilds not yet implemented'
	        	      WHERE record_id = each_rec.record_id;
		             COMMIT WORK;
                 	WHEN OTHERS THEN
			     RAISE; /* Pass it to next level */
		   END;

            END IF;

      END LOOP;
      update_index_tool_control('REBUILD','IDLE', 'Completed Rebuilds');
      dbms_sql.close_cursor(v_cur_handle);
      COMMIT WORK;
   EXCEPTION
	  WHEN instance_shutdown OR session_killed THEN
	      update_index_tool_control('REBUILD', 'IDLE', 
			'Rebuild stopped due to instance shutdown');
              IF dbms_sql.is_open(v_cur_handle) THEN
			dbms_sql.close_cursor(v_cur_handle);
	      END IF;
	      COMMIT WORK;
          WHEN OTHERS THEN
              IF dbms_sql.is_open(v_cur_handle) THEN
			dbms_sql.close_cursor(v_cur_handle);
	      END IF;
              update_index_tool_control('REBUILD','FAILED', SQLERRM);        
                  COMMIT WORK;
	      RAISE; /* Once recorded in control table pass it to Job Queue */
   END rebuild;
BEGIN /* Package body initialisation */
   v_move_indexes := get_site_param_value('INDEX_TOOL',
							'MOVE_INDEXES');

END index_tool;
/

EXECUTE dbms_job.isubmit(600,- 
'sitedba.index_tool.collect;sitedba.index_tool.schedule;sitedba.index_tool.rebuild;',- 
NEXT_DAY(TRUNC(SYSDATE), 'SAT')+9/24 /* 9AM on Saturday */, -
'NEXT_DAY(TRUNC(SYSDATE), ''SAT'')+9/24' /* Every Saturday */)

REM ****** Undefine variables set in the script *****
UNDEFINE  data_tablespace
UNDEFINE  index_tablespace

REM ******* End of file **************

