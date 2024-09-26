REM $Header: sitedba.sql,v 1.1 2003/02/20 10:34:20 oracle Exp $
REM Desc: Create sitedba userid for installation of sitedba tools
REM $Log:	sitedba.sql,v $
REM Revision 1.1  2003/02/20  10:34:20  10:34:20  oracle ()
REM Initial revision
REM 
UNDEFINE data_tablespace
create user sitedba
identified by &password
default tablespace &&data_tablespace
temporary tablespace &temp_tablespace
quota unlimited on &&data_tablespace
quota unlimited on &index_tablespace;
REM Carry out grants
grant create session, analyze any, alter any table to sitedba;
grant select any table, alter any index to sitedba;
REM additional grant for 9i 
grant select any dictionary to sitedba; 
