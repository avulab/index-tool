REM $Header: itstatus.sql,v 1.1 2003/02/20 10:35:36 oracle Exp $
REM DESC: Script to report the status of Index tool
REM Usage: Run as sysdba or sitedba
REM Author: Bala Avula - Kinetic Software Ltd
REM Notes: Be aware of ROWNUM
REM $Log:	itstatus.sql,v $
REM Revision 1.1  2003/02/20  10:35:36  10:35:36  oracle ()
REM Initial revision
REM 
REM
COLUMN message FORMAT A40
SET LINESIZE 100
SELECT *
  FROM sitedba.index_tool_control
/
PROMPT First ten collect failures
SELECT name, status, message
  FROM sitedba.site_index_stats
WHERE status != 'COMPLETED'
   AND ROWNUM < 11
/
PROMPT First ten rebuild failures
SELECT name, status, message
  FROM sitedba.site_index_rebuilds
WHERE status != 'COMPLETED'
   AND ROWNUM < 11
/
select to_char(min(timestamp), 'dd-mon-yy hh24:mi') "Collect Start",
       to_char(max(timestamp), 'dd-mon-yy hh24:mi') "Collect End"
  from sitedba.site_index_stats
group by trunc(timestamp)
/
select to_char(min(timestamp), 'dd-mon-yy hh24:mi') "Rebuild Start",
       to_char(max(timestamp), 'dd-mon-yy hh24:mi') "Rebuild End"
  from sitedba.site_index_rebuilds
group by trunc(timestamp)
/
REM ************** End of file ****************

