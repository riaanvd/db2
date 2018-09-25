#!/bin/ksh
#set -x
clear

echo "Create Database"
echo $0
echo `date`

 if [ ${#} -lt 1 ]
  then
    echo " ERROR : Not enough parameters, need at least 1"
    echo "Usage : $0 <DBNAME>"
    exit 1
  else
    echo Load DB2 Profile...
    . ~/sqllib/db2profile
    RETCODE=$?
    if [ "$RETCODE" -ne 0 ]; then
      echo "Could not load db2 profile"
      exit 1
    else
      export DBNAME=`echo $1 |tr [A-Z] [a-z]`
    fi
  fi
  

	
	
DB_EXISTS=$(db2 list db directory | grep -i "${DBNAME}" | grep -i "Database name" | wc -l)
	
if [ "$DB_EXISTS" == "1" ]; then
echo "Create Database"		
	   echo "the database "${DBNAME}" already exists"
echo $0		
	   exit 0

echo `date`			
fi

TMSTAMP=`date +%Y%m%d_%H%M`
HOSTNAME=`hostname -s`
HOSTNAME=`echo $HOSTNAME |tr [A-Z] [a-z]`

WASUSER="$DBNAME"

if [ -s /ramdisk ]
then
    echo "Set DBDIRECTORY to ramdisk"
    DBDIRECTORY="/ramdisk/db2data/"
else    
    if [ -s /db2 ]
    then
        echo "Set DBDIRECTORY to /db2"
        DBDIRECTORY="/db2/data/"
    else 
        echo "Set DBDIRECTORY to home"
        DBDIRECTORY=`echo ~/`
    fi
fi

DB2STORAGEPATH="${DBDIRECTORY}AMS"
DB2ACTIVELOG="${DBDIRECTORY}log/${DBNAME}"
DB2ARCHIVELOG="${DB2ACTIVELOG}/archive"
LOGARCHMETH1="'DISK:${DB2ARCHIVELOG}'"

SCRIPTLOG=/tmp/create_database_"$HOSTNAME".log
 
OSTYPE=`uname`

OSUSER="$WASUSER"
OSGROUP="$WASUSER"g
 
IFEXIST=`db2 list db directory |grep  'Database' |grep -v 'entry' |grep -v 'level'|grep -i $DBNAME|wc -l`
echo "Number of existing databases with name : $DBNAME =  $IFEXIST" |tee -a $SCRIPTLOG
 
 
db2 get dbm config |grep "(SVCENAME)" |cut -c60-65 |read DB2PORT

if [ "$IFEXIST" -gt 0  ]
then
  echo "Database with name $DBNAME already exists"                             |tee -a $SCRIPTLOG
  echo "Drop database first and restart"
  echo "Press ENTER to continue"
  exit 1
fi
 
CODESET="UTF-8"
#CODESET="ISO8859-1"
 
echo "Creating paths"	 
mkdir -p $DBDIRECTORY
mkdir -p $DB2STORAGEPATH
mkdir -p $DB2ACTIVELOG
mkdir -p $DB2ARCHIVELOG
 
echo "Parameter Summary"                                                                   
echo "================="                                                                   
echo "Instance               : $DB2INSTANCE"                                              |tee -a $SCRIPTLOG
echo "Port                   : $DB2PORT"                                                  |tee -a $SCRIPTLOG
echo "Database               : $DBNAME"                                                   |tee -a $SCRIPTLOG
echo "Codeset                : $CODESET"                                                  |tee -a $SCRIPTLOG
echo "Database directory     : $DBDIRECTORY"                                              |tee -a $SCRIPTLOG
echo "Storage path           : $DB2STORAGEPATH"                                           |tee -a $SCRIPTLOG
echo "Active log path        : $DB2ACTIVELOG"                                             |tee -a $SCRIPTLOG
echo "Archive log path       : $DB2ARCHIVELOG"                                            |tee -a $SCRIPTLOG

 
time db2 -v "create db $DBNAME AUTOMATIC STORAGE YES ON '$DB2STORAGEPATH' DBPATH ON '$DBDIRECTORY'
                using codeset $CODESET territory us collate using system pagesize 32768 DFT_EXTENT_SZ 64 restrictive
                CATALOG TABLESPACE MANAGED BY AUTOMATIC STORAGE PREFETCHSIZE 64 NO FILE SYSTEM CACHING
                TEMPORARY TABLESPACE MANAGED BY AUTOMATIC STORAGE PREFETCHSIZE 64 NO FILE SYSTEM CACHING" |tee -a $SCRIPTLOG
db2 connect to $DBNAME
RC=$?
if [ "$RC" -gt 0 ]
then
    if [ -s /db2 ]
    then
        echo "Set DBDIRECTORY to /db2"
        DBDIRECTORY="/db2/data/"
    else
        echo "Set DBDIRECTORY to home"
        DBDIRECTORY=`echo ~/`
    fi
DB2STORAGEPATH="${DBDIRECTORY}AMS"
DB2ACTIVELOG="${DBDIRECTORY}log/${DBNAME}"
DB2ARCHIVELOG="${DB2ACTIVELOG}/archive"
LOGARCHMETH1="'DISK:${DB2ARCHIVELOG}'"

echo "Creating paths"    
mkdir -p $DBDIRECTORY
mkdir -p $DB2STORAGEPATH
mkdir -p $DB2ACTIVELOG
mkdir -p $DB2ARCHIVELOG


time db2 -v "create db $DBNAME AUTOMATIC STORAGE YES ON '$DB2STORAGEPATH' DBPATH ON '$DBDIRECTORY'
                using codeset $CODESET territory us collate using system pagesize 32768 DFT_EXTENT_SZ 64 restrictive
                CATALOG TABLESPACE MANAGED BY AUTOMATIC STORAGE PREFETCHSIZE 64 NO FILE SYSTEM CACHING
                TEMPORARY TABLESPACE MANAGED BY AUTOMATIC STORAGE PREFETCHSIZE 64 NO FILE SYSTEM CACHING" |tee -a $SCRIPTLOG

fi
db2 connect to $DBNAME
RETCODE=$?
if [ "$RETCODE" -gt 0 ]
then
    echo "Error connecting to database"
    read DUMMY
    exit 2
fi

echo "Create BP"
db2 -v CREATE BUFFERPOOL BP_16K SIZE automatic PAGESIZE 16K;
db2 -v CREATE BUFFERPOOL BP_16K_I SIZE automatic PAGESIZE 16K;
db2 -v CREATE BUFFERPOOL BP_TEMP4K IMMEDIATE  SIZE  automatic PAGESIZE 4K;
db2 -v CREATE BUFFERPOOL BP_TEMP16K IMMEDIATE  SIZE automatic PAGESIZE 16K;
db2 -v CREATE BUFFERPOOL BP_TEMP32K IMMEDIATE  SIZE automatic PAGESIZE 32K;
db2 -v CREATE BUFFERPOOL BP_32K IMMEDIATE SIZE automatic PAGESIZE 32K;
db2 -v alter bufferpool IBMDEFAULTBP size automatic;

db2 -v "DROP TABLESPACE USERSPACE1" |tee -a $SCRIPTLOG
 
echo "Create SPs"
db2 -v "CREATE USER TEMPORARY TABLESPACE TEMPSPACE_16K PAGESIZE 16 K MANAGED BY automatic storage
EXTENTSIZE 8 OVERHEAD 10.5 PREFETCHSIZE 8 TRANSFERRATE 0.14 BUFFERPOOL BP_TEMP16K"
db2 -v "CREATE SYSTEM TEMPORARY TABLESPACE TEMPSPACE_32K PAGESIZE 32 K MANAGED BY automatic storage
EXTENTSIZE 8 OVERHEAD 10.5 PREFETCHSIZE 8 TRANSFERRATE 0.14 BUFFERPOOL BP_TEMP32K"



db2 -v "CREATE OR REPLACE PROCEDURE dbatb.CREATE_data_TS (@TS_NAME VARCHAR(100))
LANGUAGE SQL
BEGIN

DECLARE @sqlTEXT VARCHAR(1000);--
DECLARE @stop INT;--
DECLARE V_COUNT INT DEFAULT 0;--

SELECT COUNT(*) INTO v_Count FROM SYSCAT.TABLESPACES WHERE TBSPACE = UPPER(@TS_NAME);--

IF (v_count = 0) THEN
SET @sqlTEXT = 'CREATE REGULAR TABLESPACE ' || @TS_NAME || '
PAGESIZE 16384
MANAGED BY AUTOMATIC STORAGE
EXTENTSIZE 64 
PREFETCHSIZE AUTOMATIC
BUFFERPOOL BP_16K
AUTORESIZE YES
INITIALSIZE 1 M
INCREASESIZE 1 M
MAXSIZE NONE
NO FILE SYSTEM CACHING
DROPPED TABLE RECOVERY ON';--

PREPARE s1 FROM @sqlTEXT;--
EXECUTE s1;--
END IF;--
END"

db2 -v "CREATE OR REPLACE PROCEDURE dbatb.CREATE_data_TS32K (@TS_NAME VARCHAR(100))
LANGUAGE SQL
BEGIN

DECLARE @sqlTEXT VARCHAR(1000);--
DECLARE @stop INT;--
DECLARE V_COUNT INT DEFAULT 0;--

SELECT COUNT(*) INTO v_Count FROM SYSCAT.TABLESPACES WHERE TBSPACE = UPPER(@TS_NAME);--

IF (v_count = 0) THEN
SET @sqlTEXT = 'CREATE REGULAR TABLESPACE ' || @TS_NAME || '
PAGESIZE 32768 
MANAGED BY AUTOMATIC STORAGE 
EXTENTSIZE 64
PREFETCHSIZE AUTOMATIC
BUFFERPOOL BP_32K
AUTORESIZE YES
INITIALSIZE 1 M
INCREASESIZE 1 M
MAXSIZE NONE
NO FILE SYSTEM CACHING
DROPPED TABLE RECOVERY ON';--

PREPARE s1 FROM @sqlTEXT;--
EXECUTE s1;--
END IF;--
END"
 

db2 -v "CREATE OR REPLACE PROCEDURE dbatb.CREATE_ix_ts (@TS_NAME VARCHAR(100))
LANGUAGE SQL
BEGIN

DECLARE @sqlTEXT VARCHAR(1000);--
DECLARE @stop INT;--
DECLARE V_COUNT INT DEFAULT 0;--

SELECT COUNT(*) INTO v_Count FROM SYSCAT.TABLESPACES WHERE TBSPACE = UPPER(@TS_NAME);--

IF (v_count = 0) THEN
SET @sqlTEXT = 'CREATE REGULAR TABLESPACE ' || @TS_NAME || '
PAGESIZE 16384
MANAGED BY AUTOMATIC STORAGE 
EXTENTSIZE 64
PREFETCHSIZE AUTOMATIC
BUFFERPOOL BP_16K_I
AUTORESIZE YES
INITIALSIZE 1 M
INCREASESIZE 1 M
MAXSIZE NONE
NO FILE SYSTEM CACHING
DROPPED TABLE RECOVERY ON';--

PREPARE s1 FROM @sqlTEXT;--
EXECUTE s1;--
END IF;--
END"

db2 -v "CREATE OR REPLACE PROCEDURE dbatb.CREATE_blob_TS (@TS_NAME VARCHAR(100))
LANGUAGE SQL
BEGIN

DECLARE @sqlTEXT VARCHAR(1000);--
DECLARE @stop INT;--
DECLARE V_COUNT INT DEFAULT 0;--

SELECT COUNT(*) INTO v_Count FROM SYSCAT.TABLESPACES WHERE TBSPACE = UPPER(@TS_NAME);--

IF (v_count = 0) THEN
SET @sqlTEXT = 'CREATE LARGE TABLESPACE ' || @TS_NAME || '
PAGESIZE 16384
MANAGED BY AUTOMATIC STORAGE 
EXTENTSIZE 64
PREFETCHSIZE AUTOMATIC
BUFFERPOOL BP_16K
AUTORESIZE YES
INITIALSIZE 1 M
INCREASESIZE 1 M
MAXSIZE NONE
FILE SYSTEM CACHING
DROPPED TABLE RECOVERY ON';--

PREPARE s1 FROM @sqlTEXT;--
EXECUTE s1;--
END IF;--
END"

db2 -v "CREATE OR REPLACE PROCEDURE dbatb.CREATE_data_TS (@TS_NAME VARCHAR(100), @TS_TYPE VARCHAR(1)
, @TS_PGSZ INT) 
LANGUAGE SQL
SPECIFIC CREATE_TS_DATATYPE
BEGIN
DECLARE @DATATYPE VARCHAR(20);--
DECLARE @PGSIZE VARCHAR(5);--
DECLARE @BPNAME VARCHAR(20);--
DECLARE @sqlTEXT VARCHAR(1000);--
DECLARE @EXISTFLAG INT DEFAULT 0;--

IF @TS_TYPE NOT IN ('A', 'L')
THEN
SIGNAL SQLSTATE '80000'
SET MESSAGE_TEXT='Not a Valid TBSpace Type';--
END IF;--

IF @TS_PGSZ NOT IN (4096, 16384, 32768)
THEN
SIGNAL SQLSTATE '80000'
SET MESSAGE_TEXT='Not a Valid TBSpace PageSize';--
END IF;--

IF @TS_TYPE = 'L'
THEN SET @DATATYPE = 'LARGE';--
ELSE SET @DATATYPE = 'REGULAR';--
END IF;--
IF @TS_PGSZ = 4096
THEN  SET @BPNAME = 'BP_4K';--
ELSEIF @TS_PGSZ = 16384
THEN SET @BPNAME = 'BP_16K';--
ELSEIF @TS_PGSZ = 32768
THEN SET @BPNAME = 'BP_32K';--
END IF;--

SELECT COUNT(*) INTO @EXISTFLAG FROM SYSCAT.TABLESPACES WHERE TBSPACE = UPPER(@TS_NAME);--

IF (@EXISTFLAG = 0) THEN
SET @sqlTEXT = 'CREATE '||@DATATYPE ||' TABLESPACE ' || @TS_NAME || '
PAGESIZE '||@TS_PGSZ||' 
MANAGED BY AUTOMATIC STORAGE
EXTENTSIZE 64
PREFETCHSIZE AUTOMATIC
BUFFERPOOL '||@BPNAME||' 
AUTORESIZE YES
INITIALSIZE 1 M
INCREASESIZE 1 M
MAXSIZE NONE
NO FILE SYSTEM CACHING
DROPPED TABLE RECOVERY ON';--

PREPARE s1 FROM @sqlTEXT;--
EXECUTE s1;--
END IF;--
END"

db2 "select substr(BPNAME,1,15) as BP_NAME, npages, pagesize from syscat.bufferpools"        |tee -a $SCRIPTLOG
db2 list tablespaces                                                                      |tee -a $SCRIPTLOG

echo "Update DBM config"

db2 -v "UPDATE DBM CONFIG USING DFT_MON_SORT ON"                                          |tee -a $SCRIPTLOG
db2 -v "UPDATE DBM CONFIG USING DFT_MON_LOCK ON"                                          |tee -a $SCRIPTLOG
db2 -v "UPDATE DBM CONFIG USING DFT_MON_BUFPOOL ON"                                       |tee -a $SCRIPTLOG
db2 -v "UPDATE DBM CONFIG USING DFT_MON_TABLE ON"                                         |tee -a $SCRIPTLOG
db2 -v "UPDATE DBM CONFIG USING DFT_MON_STMT ON"                                          |tee -a $SCRIPTLOG
db2 -v "UPDATE DBM CONFIG USING DFT_MON_UOW ON"                                           |tee -a $SCRIPTLOG
db2 -v "UPDATE DBM CONFIG USING DFT_MON_TIMESTAMP ON"                                     |tee -a $SCRIPTLOG

echo "Update DB config"
db2 -v update db CONFIG using CATALOGCACHE_SZ 260 immediate;
db2 -v update db CONFIG using LOGBUFSZ 4096 immediate;
db2 -v update db CONFIG using NUM_IOCLEANERS automatic immediate;
db2 -v update db CONFIG using NUM_IOSERVERS automatic immediate;
db2 -v update db CONFIG using PCKCACHESZ 1024 immediate ;
db2 -v update db CONFIG using APPLHEAPSZ 4096 immediate;
db2 -v update db CONFIG using LOCKLIST automatic immediate;
db2 -v update db CONFIG using MAXLOCKS automatic immediate;
db2 -v update db CONFIG using LOCKTIMEOUT 60 immediate;
db2 -v update db CONFIG using LOGPRIMARY 10 immediate;
db2 -v update db CONFIG using LOGSECOND 225 immediate;
db2 -v update db CONFIG using STMTHEAP 4096 immediate;
db2 -v update db CONFIG using LOGFILSIZ 5000 immediate;
db2 -v update db CONFIG using DBHEAP 3000 immediate;

echo "Update log paths"
db2 -v "update db CONFIG using NEWLOGPATH $DB2ACTIVELOG"                                    |tee -a $SCRIPTLOG
db2 -v "update db CONFIG using LOGARCHMETH1 $LOGARCHMETH1 immediate" |tee -a $SCRIPTLOG
db2 -v "update db CONFIG using AUTO_MAINT ON immediate" |tee -a $SCRIPTLOG

db2set DB2COMM=TCPIP
db2set DB2AUTOSTART=YES
db2set DB2_CAPTURE_LOCKTIMEOUT=ON
db2set DB2_SKIPINSERTED=ON
db2set DB2_EVALUNCOMMITTED=ON
db2set DB2_SKIPDELETED=ON
db2set DB2_PARALLEL_IO=*
db2pdcfg -catch clear
db2pdcfg -catch -911,68
db2pdcfg -catch -911,2


db2 -v "connect reset"
echo "The following applications are running on $DBNAME"                        |tee -a $SCRIPTLOG
db2 -v "list applications" |grep -i $DBNAME                                     |tee -a $SCRIPTLOG
echo "Performing backup of database...."                                        |tee -a $SCRIPTLOG
db2 -v "backup db $DBNAME to /dev/null"                                         |tee -a $SCRIPTLOG
db2 -v "connect to $DBNAME"                                                     |tee -a $SCRIPTLOG
db2 -v "activate database $DBNAME"                                              |tee -a $SCRIPTLOG
db2 -v "grant connect, dbadm on database to user ${WASUSER}"                           |tee -a $SCRIPTLOG
db2 connect reset
 
#curl -o db2ese_v10.5_c.lic root@ict-repo:/bakery/binary_content/db2/db2ese_v10.5_c.lic ; db2licm -l ; db2licm -a db2ese_v10.5_c.lic ; db2licm -l
curl -o db2ese_v11.1_c.lic root@ict-repo:/bakery/binary_content/db2/Licenses/db2ese_v11.1_c.lic; db2licm -l ; db2licm -a db2ese_v11.1_c.lic ; db2licm -l

echo ""                                                                          |tee -a $SCRIPTLOG
echo "Connect details for this database"                                         |tee -a $SCRIPTLOG
echo "Host         : `hostname`"                                                 |tee -a $SCRIPTLOG
echo "DB Instance  : $DB2INSTANCE (port $DB2PORT)"                               |tee -a $SCRIPTLOG
echo "DB Name      : $DBNAME"                                                    |tee -a $SCRIPTLOG
echo "App User ID  : $WASUSER"                                                   |tee -a $SCRIPTLOG
echo "App User PWD : password"                                                   |tee -a $SCRIPTLOG
echo ""

db2 connect to $DBNAME
RETCODE=$?
if [ "$RETCODE" -gt 0 ]
then
    echo "Error connecting to database"
    read DUMMY
    exit 2
else
    db2 "call dbatb.create_data_ts('default')"
    db2 -tvf /db2dba/scripts/RELEASES/disable_BSON.sql
    db2 -stvf /db2dba/scripts/RELEASES/enable_BSON.sql
    RETCODE=$?
    if [ "$RETCODE" -gt 0 ]
    then
        echo "Error enabling BSON"
    fi

    db2 connect reset 
fi

cd 
#cd ./sqllib/json/bin/
#./db2nosql.sh -user $DB2INSTANCE -hostName $HOSTNAME -port 60000 -db $DBNAME -password password -setup enable


exit 0
