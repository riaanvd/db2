#!/bin/ksh
# This script deploys the DB2 database scripts for a release
# usage : ReleaseControl.sh <DBNAME> <VERSION>
#
#
#=============================================================================================

clear

if [ $# -lt 2 ]
then
    echo "ERROR : Not enough parameters."
    echo "Usage : ReleaseControl.sh <DBNAME> <VERSION>"
    exit 1
fi

echo Load DB2 Profile...
CURRENT_UID=`whoami`

if [ "$CURRENT_UID" != "cmsdepl" ]
then
    echo Load DB2 Profile...
    . ~/sqllib/db2profile
    RETCODE=$?
    if [ "$RETCODE" -ne 0 ]
    then
        echo "Could not load db2 profile"
        exit 1
    fi
fi

DBNAME="$1"
DBNAME=`echo $DBNAME | tr [A-Z] [a-z]`

REL_VERSION="$2"
REL_VERSION=`echo $REL_VERSION | tr [A-Z] [a-z]`

HOSTNAME=`hostname -s`
HOSTNAME=`echo $HOSTNAME | tr [A-Z] [a-z]`

OSTYPE=`uname`

PROD_FLAG=N

TMSTAMP=`date +%Y%m%d_%H%M`

EXISTFLAG=0
DROP_ALL_INDICATOR="xxXX DROP ALL XXxx"                                             #The string to search for in dbatb.releasecontrol to identify when the db was last rebuilt

HOSTNAME_DESCRIPTION="UNKNOWN HOST"

cd /db2dba/scripts/RELEASES
chmod 777 .

###Added Riaan 2013-08-22

COMPRESS_FILE="$REL_VERSION".tar.gz
echo "Compress file : $COMPRESS_FILE"

if [ -s "$COMPRESS_FILE" ]
then
    echo "Unzip archive $COMPRESS_FILE"                                               |tee -a $SCRIPTLOG
    gunzip -f "$COMPRESS_FILE"                                                             |tee -a $SCRIPTLOG
else
    echo "Zip archive not found"
fi

if [ -s "$REL_VERSION".tar ]
then
    echo "Extract archive "$REL_VERSION".tar"                                                |tee -a $SCRIPTLOG
    tar xvfm "$REL_VERSION".tar
    if [ "$?" -ne 0 ]
    then
        echo " ERROR : Can't extract archive : "$REL_VERSION".tar"                                                    
        exit 1
    else
        chmod -R 777 ./${REL_VERSION}/*
    fi
    echo "Deleting Archive : "$REL_VERSION".tar"                                          |tee -a $SCRIPTLOG
    rm "$REL_VERSION".tar
fi

###

cd "/db2dba/scripts/RELEASES/$REL_VERSION"
RETCODE=$?

if [ "$RETCODE" -ne 0 ]
then
    echo "Invalid release version for this target server : $HOSTNAME , $REL_VERSION"
    echo "Scripts have not been copied to target database server"
    exit 99
fi

ERR_FLAG=N

APP_NAME=`echo ${REL_VERSION} | awk -F"_" {'print $1'}`
RO_USER=cmsdepl
APP_USER=$DBNAME,tatusr
DBNAME_DESCRIPTION="Customs Management System"


if [ ${APP_NAME} = 'cms' ]
then 
    DBDIR="cms"
else
    DBDIR="scripts"
fi

#Force the use of the "./scripts" DBDIR RvD 2016-07-28
if [ -d /db2dba/scripts/RELEASES/${REL_VERSION}/cms/ ]; then
    mkdir -p /db2dba/scripts/RELEASES/${REL_VERSION}/scripts/
    mv /db2dba/scripts/RELEASES/${REL_VERSION}/cms/* /db2dba/scripts/RELEASES/${REL_VERSION}/scripts/
    DBDIR="scripts"
fi


MAILTO_DEFAULT=""
MAILTO_DBA=""  #  ,wayman@bbd.co.za,DB2DBA@sars.gov.za,rjames@sars.gov.za"
MAILTO_PM=""
MAILTO_RELMNGMNT="" #ReleaseMngt2@sars.gov.za

MAILSUBJECT_PM="DB2 Release Control Report : $HOSTNAME_DESCRIPTION ,Database: $DBNAME_DESCRIPTION : $REL_VERSION"
MAILSUBJECT_RELMNGMNT="DB2 Release Archive : $HOSTNAME_DESCRIPTION ,Database: $DBNAME_DESCRIPTION : $REL_VERSION"

SCRIPT_EXEDIR=/db2dba/scripts/RELEASES                                                        #Where executable scripts are
SCRIPT_LOGDIR="$SCRIPT_EXEDIR"/"$REL_VERSION"                                                 #Where all logs will be written 
SCRIPT_DIR="$SCRIPT_EXEDIR"/"$REL_VERSION"/"$DBDIR"                                           #Where scripts for specific database are
#SCRIPT_COMPLETEDIR="$SCRIPT_DIR"/complete                                                     #Where scripts are moved to after successfull execution

SCRIPTLOG="$SCRIPT_LOGDIR"/ReleaseControl_"$HOSTNAME"_"$DBNAME".log                           #Name of log file 
SCRIPTOUT="$SCRIPT_LOGDIR"/ReleaseControl_"$HOSTNAME"_"$DBNAME".out                           #Temp out file to capture output of script being run
SCRIPTREP="$SCRIPT_LOGDIR"/ReleaseControl_Report_"$HOSTNAME"_"$DBNAME".rep                    #Name of Project manager report which shows durations of script execution 
GRANTOUT="$SCRIPT_LOGDIR"/ReleaseControl_GrantPrivileges_"$HOSTNAME"_"$DBNAME".out            #Name of temp file used to perform db grants 
SCRIPTDDL="$SCRIPT_LOGDIR/db2look_"$HOSTNAME"_"$DBNAME"_"$TMSTAMP".ddl"
SCRIPTCTRL="$SCRIPT_DIR/verify.ctrl"
REL_MNGMNT_ARCHIVE="$SCRIPT_EXEDIR/"$REL_VERSION"/DML_Archive_"$HOSTNAME"_"$DBNAME"_"$TMSTAMP".tar"
REL_MNGMNT_MAILBODY_TMP="/tmp/db2_releasecontrol.tmp"


cd $SCRIPT_DIR
RETCODE=$?
if [ "$RETCODE" -ne 0 ]
then
    echo "ERROR : Cant find directory : $SCRIPT_DIR"                                |tee -a $SCRIPTLOG
    echo "Scripts have not been copied to target database server"                   |tee -a $SCRIPTLOG
    exit 1
fi

mkdir -p $SCRIPT_LOGDIR                                                        |tee -a $SCRIPTLOG
RETCODE=$?
if [ "$RETCODE" -ne 0 ]
then
    echo "ERROR : Cant create complete directory : $SCRIPT_LOGDIR"             |tee -a $SCRIPTLOG
    exit 1
fi

TITLE="DB2 Release Control : $HOSTNAME : $DBNAME : $REL_VERSION"
SUBTITLE="Starting at `date`"

echo "$TITLE"                                                                       |tee -a $SCRIPTLOG
echo "$SUBTITLE"                                                                    |tee -a $SCRIPTLOG
echo "Release version              : $REL_VERSION"                                  |tee -a $SCRIPTLOG
echo "Hostname                     : $HOSTNAME"                                     |tee -a $SCRIPTLOG
echo "Host description             : $HOSTNAME_DESCRIPTION"                         |tee -a $SCRIPTLOG
echo "Database name                : $DBNAME"                                       |tee -a $SCRIPTLOG
echo "OS on host                   : $OSTYPE"                                       |tee -a $SCRIPTLOG
echo "Script log directory         : $SCRIPT_LOGDIR"                                |tee -a $SCRIPTLOG
echo "Script directory             : $SCRIPT_DIR"                                   |tee -a $SCRIPTLOG
echo "DDL output                   : $SCRIPTDDL"                                    |tee -a $SCRIPTLOG
echo ""                                                                             |tee -a $SCRIPTLOG
echo "Log written                  : $SCRIPTLOG"                                    |tee -a $SCRIPTLOG
echo "CTRL file                    : $SCRIPTCTRL"                                   |tee -a $SCRIPTLOG


if [ -s  $SCRIPTCTRL ]
then
    cat $SCRIPTCTRL |grep MAILTO |read VAR MAILTO_ALL
fi

if [ "$MAILTO_ALL" != "" ]
then 
    echo "Reset mailto from ctrl file"
    MAILTO="$MAILTO_ALL"
    echo "MAILTO                       : $MAILTO"                                       |tee -a $SCRIPTLOG
else
    MAILTO="$MAILTO_DEFAULT"
    echo "MAILTO                       : $MAILTO"                                       |tee -a $SCRIPTLOG
fi


S_TIME=`date +%Y-%m-%d-%H.%M.%S`
echo "\n S_TIME $S_TIME"                                                               |tee -a $SCRIPTREP

db2 -v activate database $DBNAME                                                    |tee -a $SCRIPTLOG
db2 connect to $DBNAME                                                              >> $SCRIPTLOG
RETCODE=$?
if [ "$RETCODE" -ne 0 ]
then
    echo "ERROR : Cant connect to database, $DBNAME"                                |tee -a $SCRIPTLOG
    exit 2
else
    ##----------------------------------------------------------------------
    ##--0. Perform DB sanity check
    ##----------------------------------------------------------------------
    echo "Perform sanity checks"                                                    |tee -a $SCRIPTLOG
    DB2_SQL_CHECK_RC_TBL="SELECT COUNT(*) 
                          FROM SYSCAT.TABLES 
                          WHERE TABNAME ='RELEASECONTROL' AND TABSCHEMA='DBATB'"
    
    DB2_DDL_CRT_RC_TS1="call dbatb.create_data_ts('DBATBS_DATA')"
    DB2_DDL_CRT_RC_TS2="call dbatb.create_IX_ts('DBATBS_IDX')"
    DB2_DDL_CRT_RC_TBL="CREATE TABLE DBATB.RELEASECONTROL  (
                        DBNAME CHAR(15) NOT NULL ,
                        HOSTNAME VARCHAR(100) NOT NULL ,
                        RELEASE_VERSION VARCHAR(50) NOT NULL ,
                        STEP VARCHAR(20) ,
                        SCRIPTNAME VARCHAR(100) ,
                        SCRIPTDESCRIPTION VARCHAR(200) ,
                        STARTTIME TIMESTAMP ,
                        ENDTIME TIMESTAMP ,
                        EXECUTION_DURATION DECIMAL(10,3) ,
                        RETCODE CHAR(5) )
                        IN DBATBS_DATA INDEX IN DBATBS_IDX"
    DB2_DDL_CRT_RC_IX="CREATE INDEX DBATB.RELEASECONTROL_IX1 ON DBATB.RELEASECONTROL
                (RELEASE_VERSION ASC,
                 SCRIPTNAME ASC,
                 EXECUTION_DURATION ASC,
                 STARTTIME ASC)
                 COMPRESS NO ALLOW REVERSE SCANS"

    db2 -x "$DB2_SQL_CHECK_RC_TBL" | read EXISTFLAG DUMMY      

    if [ "$EXISTFLAG" -eq 0 ]
    then
        echo "Creating DBATB.ReleaseControl table"                                  |tee -a SCRIPTLOG
        db2 -v "$DB2_DDL_CRT_RC_TS1"                                                |tee -a SCRIPTLOG
        db2 -v "$DB2_DDL_CRT_RC_TS2"                                                |tee -a SCRIPTLOG
        db2 -v "$DB2_DDL_CRT_RC_TBL"                                                |tee -a SCRIPTLOG
        db2 -v "$DB2_DDL_CRT_RC_IX"                                                 |tee -a SCRIPTLOG
    else
         echo "DBATB.RELEASECONTROL already exists"                                   |tee -a $SCRIPTLOG
    fi

    DB2_SQL_INSERT="insert into dbatb.releasecontrol 
             (DBNAME,HOSTNAME,RELEASE_VERSION,STEP,STARTTIME,RETCODE)
             values
             ('$DBNAME','$HOSTNAME','$REL_VERSION','START RELCTRL',current timestamp,'$RETCODE')" 
    #echo $DB2_SQL_INSERT
    db2 -v $DB2_SQL_INSERT                                                          |tee -a $SCRIPTLOG
	
	DB2_SQL_LAST_DROPALL="SELECT case when MAX(STARTTIME) is null then '0001-01-01-00.00.00.000000' else MAX(STARTTIME) end FROM DBATB.RELEASECONTROL WHERE SCRIPTDESCRIPTION LIKE '%"$DROP_ALL_INDICATOR"%'"
	#echo $DB2_SQL_LAST_DROPALL
	#db2 -v $DB2_SQL_LAST_DROPALL  
	#db2 -x $DB2_SQL_LAST_DROPALL |read LAST_DROPALL_TMSTAMP DUMMY
       
       export LAST_DROPALL_TMSTAMP=`db2 -x $DB2_SQL_LAST_DROPALL`

       #echo "DROPALL_TS : ${LAST_DROPALL_TMSTAMP}"

	#if [ "x${LAST_DROPALL_TMSTAMP}" = "x-" -o "x${LAST_DROPALL_TMSTAMP}" = "x" -o ${LAST_DROPALL_TMSTAMP} = "" ]
	#then
	#    echo "Drop all has never been performed on this database"
       #     LAST_DROPALL_TMSTAMP="0001-01-01-00.00.00.000000"
       #fi
       #echo "LAST DROPALL set to : $LAST_DROPALL_TMSTAMP"

    db2 -x "select 'INFO : LAST DB2 BACKUP : Started at '||TIMESTAMP_FORMAT(start_time,'YYYY-MM-DD HH24:MI:SS')
					||', and took '||TIMESTAMPDIFF(4,CHAR(end_time - start_time))||' minutes to complete : '||comment
			from   sysibmadm.DB_HISTORY
			where  comment like '%BACKUP%' and start_time =
							(select max(start_time)
							from   sysibmadm.DB_HISTORY
							where  comment like '%BACKUP%' and sqlcode is null)
			and location <> '/dev/null' fetch first row only with ur"         |tee -a $SCRIPTLOG
     db2 -x list applications |wc -l |read CONNECTIONS DUMMY                                                 #Determine the number of connections to the DB
     echo "INFO : There are $CONNECTIONS connections to the database $DBNAME"       |tee -a $SCRIPTLOG        #Alert number of connections to the DB

  
fi

SCRIPTCOUNT=0                                                                                                 #Counter to keep track of progress
EXECORDERCOUNT=0                                                                                              #Counter to keep track of progress
TOT_EXEC_TIME=0                                                                                              #Counter to keep track of progress
let "SCRIPTCOUNT=$SCRIPTCOUNT+0"													  #Initialize Counter
let "EXECORDERCOUNT=$EXECORDERCOUNT+0"												  #Initialize Counter
let "TOT_EXEC_TIME=$TOT_EXEC_TIME+0"												  #Initialize Counter
##----------------------------------------------------------------------
##--0. For now: Just list the number of DDL & SQL Scripts to process
##----------------------------------------------------------------------
FILE_TO_PROCESS_EXEC=`ls *"execution_order"*.txt|wc -l`                                                 #Show how many execution files to process
echo "Exec Orders to process : $FILE_TO_PROCESS_EXEC"                               |tee -a $SCRIPTLOG #How many Exec Order .txt files are there to process

FILE_TO_PROCESS_DDL=`ls *.ddl|wc -l`                                                                   #Show how many to process
echo "DDL Files to process   : $FILE_TO_PROCESS_DDL"                                  |tee -a $SCRIPTLOG #How many .ddl files are there to process

FILE_TO_PROCESS_SQL=`ls *.sql|wc -l`                                                                   #Show how many to process
echo "SQL Files to process   : $FILE_TO_PROCESS_SQL"                                  |tee -a $SCRIPTLOG #How many .sql files are there to process

(( TOT_SCRIPTCOUNT = FILE_TO_PROCESS_SQL + FILE_TO_PROCESS_DDL))                      #===>> 

echo "Total files to process : $TOT_SCRIPTCOUNT"                                    |tee -a $SCRIPTLOG #Total number of files to process

##----------------------------------------------------------------------
##--1. For each Execution Order Process DDL & SQL Scripts by reading Execution Order line by line
##----------------------------------------------------------------------
if [ "$ERR_FLAG" = "N" ]
then
	for EXEC_ORDER in `ls *"execution_order"*.txt |grep -i exec`                                 #List all exec order files and process 1 by 1
	do
         db2 connect to $DBNAME |tee -a $SCRIPTLOG
         RETCODE=$?
         if [ "$RETCODE" -ne 0 ]
         then
             echo "ERROR : Cant connect to database to grant permissions : $HOSTNAME, $DBNAME"                                             |tee -a $SCRIPTLOG
             exit 2
         	fi
	  echo "Remove blank lines from Execution Order File: $EXEC_ORDER"    |tee -a $SCRIPTLOG
	  cp "$EXEC_ORDER" "$EXEC_ORDER".orig
	  sed 's/  *$//;/^$/d' "$EXEC_ORDER".orig > "$EXEC_ORDER"                                   # remove all blank lines
	  #mv "$EXEC_ORDER".orig ./complete
          ### Riaan 2013-08-27
          rm "$EXEC_ORDER".orig 
	  echo "Processing Scripts in Exec Order : $EXEC_ORDER at `date`"     |tee -a $SCRIPTLOG
	  # Ignore blank lines and lines starting with a # or blanks and then a #
	  cat "$EXEC_ORDER" | awk 'NF != 0 && $0 !~ "^[[:blank:]]*#" {print $0}' | while read FILENAME SCRIPT_DESCRIPTION
	  do 
           echo "Check val : ${FILENAME} ${SCRIPT_DESCRIPTION}"
 
	    echo "Check if script was applied to database since last drop all"
		DB2_SQL_COUNT_EXECUTIONS="SELECT COUNT("\*") FROM DBATB.RELEASECONTROL WHERE SCRIPTNAME = '"$FILENAME"' and RETCODE in (0,1) AND STARTTIME > '"$LAST_DROPALL_TMSTAMP"' AND NOT (SCRIPTNAME LIKE '%.rerun.sql' OR SCRIPTNAME LIKE '%.rerun.ddl') "
		 
              echo $DB2_SQL_COUNT_EXECUTIONS
 

		db2 -x ${DB2_SQL_COUNT_EXECUTIONS} |read DB2_SQL_COUNT_EXECUTIONS DUMMY
 
		echo "DB2_SQL_COUNT_EXECUTIONS : $DB2_SQL_COUNT_EXECUTIONS"

		if [ "$DB2_SQL_COUNT_EXECUTIONS" -gt 0 ]
		then
		    echo "This script ran successful before... Skipping!"
			DB2_SQL_EXECUTION_DETAIL="SELECT COUNT("\*") FROM DBATB.RELEASECONTROL WHERE SCRIPTNAME = '"$FILENAME"' and STARTTIME > '"$LAST_DROPALL_TMSTAMP"' AND NOT (SCRIPTNAME LIKE '%.rerun.sql' OR SCRIPTNAME LIKE '%.rerun.ddl') "
			db2 "$DB2_SQL_EXECUTION_DETAIL"
		else
			#SCRIPT_DESCRIPTION=$DUMMY
			SCRIPTCOUNT=`expr "$SCRIPTCOUNT" + 1`
			if [ -f $FILENAME ]
			then
	 
			echo "Processing  : $FILENAME ($SCRIPTCOUNT of $TOT_SCRIPTCOUNT)"                             |tee -a $SCRIPTLOG
				echo "Script Description : $DUMMY"                                                            |tee -a $SCRIPTLOG
				echo "Start `date`"                                                                           |tee -a $SCRIPTLOG
				#db2 -x "values (current_timestamp)" | read START_TIME
				db2 -v connect to $DBNAME
				START_TIME=`db2 -x "values (current_timestamp)"`
                            echo "$START_TIME"                             |tee -a $SCRIPTLOG	
				SCRIPT_STIME=$SECONDS
				db2 -stvf $FILENAME                                         > $SCRIPTOUT           #Execute the script via db2 client
				RETCODE=$?
				SCRIPT_ETIME=$SECONDS
				((SCRIPT_DURATION=SCRIPT_ETIME - SCRIPT_STIME))
				echo "=======================================================================================" |tee -a $SCRIPTLOG
				cat $SCRIPTOUT                                              |tee -a $SCRIPTLOG
				echo "=======================================================================================" |tee -a $SCRIPTLOG
				if [ "$RETCODE" -eq 2 ]
				then
					cat $SCRIPTOUT |grep "DB21007E" |wc -l | read SQLCODE_CNT DUMMY
					if [ "$SQLCODE_CNT" -gt 0 ]        # Cater for certain SQL Warning Messages (e.g.SQL0598W) which results in RC=2
					then
						RETCODE=$RETCODE
					else
						RETCODE=1
					fi
			fi
			if [ "$RETCODE" -gt 1 ]   # Cater for certain SQL Warning Messages (e.g.SQL0598W) which results in RC=2
			then
				ERR_FLAG=Y
				#echo "ERROR   : $FILENAME : returncode $RETCODE"      |tee -a $SCRIPTREP
				#db2 -x "values (current_timestamp)" | read END_TIME
                            END_TIME=`db2 -x "values (current_timestamp)"`

				DB2_SQL_INSERT="insert into dbatb.releasecontrol
							   (DBNAME,HOSTNAME,RELEASE_VERSION,STEP,SCRIPTNAME,SCRIPTDESCRIPTION,STARTTIME,ENDTIME,EXECUTION_DURATION,RETCODE)
							   values
							   ('$DBNAME','$HOSTNAME','$REL_VERSION','FAIL:Apply Script','$FILENAME','$SCRIPT_DESCRIPTION','$START_TIME','$END_TIME',$SCRIPT_DURATION,'$RETCODE')"
				#echo $DB2_SQL_INSERT
				db2 -v $DB2_SQL_INSERT                                                                         |tee -a $SCRIPTLOG
 
				E_TIME=`date +%Y-%m-%d-%H.%M.%S`
				echo "\n E_TIME $E_TIME"                                                                       |tee -a $SCRIPTREP
				break
			else
				echo "End `date`"                                     |tee -a $SCRIPTLOG
				#db2 -x "values (current_timestamp)" | read END_TIME
                            END_TIME=`db2 -x "values (current_timestamp)"`
				echo "SUCCESS : $FILENAME : $SCRIPTCOUNT of $TOT_SCRIPTCOUNT ($SCRIPT_DURATION sec) : RC=$RETCODE"     |tee -a $SCRIPTLOG
				DB2_SQL_INSERT="insert into dbatb.releasecontrol
								(DBNAME,HOSTNAME,RELEASE_VERSION,STEP,SCRIPTNAME,SCRIPTDESCRIPTION,STARTTIME,ENDTIME,EXECUTION_DURATION,RETCODE)
								values
								('$DBNAME','$HOSTNAME','$REL_VERSION','SUCCESS:Apply Script','$FILENAME','$SCRIPT_DESCRIPTION','$START_TIME','$END_TIME',$SCRIPT_DURATION,'$RETCODE')"
				#echo $DB2_SQL_INSERT
				db2 -v $DB2_SQL_INSERT                                                                        |tee -a $SCRIPTLOG


				#echo "Script $FILENAME :: Started at $START_TIME :: Ended at $END_TIME"   |tee -a $SCRIPTLOG
				#echo "\n SUCCESS : $DUMMY"                                                   |tee -a $SCRIPTREP
				#echo "          $FILENAME ran in $SCRIPT_DURATION sec : returncode $RETCODE" |tee -a $SCRIPTREP
				#mv $FILENAME $SCRIPT_COMPLETEDIR                                          |tee -a $SCRIPTLOG 2>&1 #Move file to complete folder
				#RETCODE=$?
				#if [ "$RETCODE" -ne 0 ]
				#then
				#				ERR_FLAG="Y"
				#	echo "ERROR : Cant move $FILENAME to $SCRIPT_COMPLETEDIR"                 |tee -a $SCRIPTLOG
									 E_TIME=`date +%Y-%m-%d-%H.%M.%S`
				#					 echo "\n E_TIME $E_TIME"                                                    |tee -a $SCRIPTREP
				#	exit 2
				#fi
			fi
			else 
				#if [ -f "$SCRIPT_COMPLETEDIR"/"$FILENAME" ]                                                             #File not found but might be in complete folder
				#then 
				#	echo "Skipping file $FILENAME, already processed"                         |tee -a $SCRIPTLOG
				#else
				ERR_FLAG=Y
				echo "ERROR : Script $FILENAME not found in $SCRIPT_DIR. Stopping. Call DB2 DBA...."     |tee -a $SCRIPTLOG      #File not in complete folder either
				E_TIME=`date +%Y-%m-%d-%H.%M.%S`
				#echo "\n E_TIME $E_TIME"                                                                   |tee -a $SCRIPTREP
				break
				#fi
			fi 
		fi
	  done                          #End of WHILE loop - Finished reading through one single exec order file
	if [ "$ERR_FLAG" = "N" ] 
	then 
		EXECORDERCOUNT=`expr "$EXECORDERCOUNT" + 1`
		echo "Finished Processing scripts in Exec Order : $EXEC_ORDER :: $EXECORDERCOUNT of $FILE_TO_PROCESS_EXEC at `date`"                   |tee -a $SCRIPTLOG
		#mv $EXEC_ORDER $SCRIPT_COMPLETEDIR							              |tee -a $SCRIPTLOG #Move Exec Order File to complete folder
		#RETCODE=$?
		#if [ "$RETCODE" -ne 0 ]
		#then
		#	ERR_FLAG="Y"
		#	echo "ERROR : Cant move $EXEC_ORDER to $SCRIPT_COMPLETEDIR"                                         |tee -a $SCRIPTLOG
			E_TIME=`date +%Y-%m-%d-%H.%M.%S`
			#echo "\n E_TIME $E_TIME"                                                                              |tee -a $SCRIPTREP
		#	exit 2
		#fi
	else #if any error has occurred whilst executing a particular DDL/SQL script then stop all processing
		break
	fi
	done #End of FOR Loop - Completed processing all exec order files
fi

##----------------------------------------------------------------------
##--3. Grant Privileges on newly created objects
##----------------------------------------------------------------------
if [ "$ERR_FLAG" = "N" ]
then
    db2 connect to $DBNAME |tee -a $SCRIPTLOG
    RETCODE=$?
    if [ "$RETCODE" -ne 0 ]
    then
        echo "ERROR : Cant connect to database to grant permissions : $HOSTNAME, $DBNAME"                                             |tee -a $SCRIPTLOG
        exit 2
    fi

    echo "Grant permissions on new Tables, UserTemp TBSpaces, Procedures, Functions and Views"                                        |tee -a $SCRIPTLOG
    DB2_SQL_INSERT="insert into dbatb.releasecontrol
                    (DBNAME,HOSTNAME,RELEASE_VERSION,STEP,STARTTIME)
                    values
                    ('$DBNAME','$HOSTNAME','$REL_VERSION','START DB PERMISSIONS',current timestamp)"
     #echo $DB2_SQL_INSERT
     db2 -v $DB2_SQL_INSERT                                                          >> $SCRIPTLOG
    db2 -x "SELECT 'GRANT SELECT ON TABLE '||rtrim(TABSCHEMA)||'.'||rtrim(TABNAME)||' TO USER $RO_USER;' 
            FROM SYSCAT.TABLES 
            WHERE CREATE_TIME > CURRENT TIMESTAMP - 2 DAYS 
                  AND TABSCHEMA NOT LIKE 'SYS%' 
                  AND TABSCHEMA NOT LIKE 'SQL%' 
                  AND TABSCHEMA NOT LIKE 'REPL%' WITH UR"                                                                             > $GRANTOUT 
    db2 -x "SELECT 'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE '||rtrim(TABSCHEMA)||'.'||rtrim(TABNAME)||' TO USER $APP_USER;' 
            FROM SYSCAT.TABLES 
            WHERE CREATE_TIME > CURRENT TIMESTAMP - 2 DAYS 
                  AND TABSCHEMA NOT LIKE 'SYS%' 
                  AND TABSCHEMA NOT LIKE 'SQL%' 
                  AND TABSCHEMA NOT LIKE 'REPL%' WITH UR"                                                                             >> $GRANTOUT 
    db2 -x "SELECT 'GRANT SELECT ON SYSIBM.SYSDUMMY1 TO USER $RO_USER, $APP_USER;'
            FROM SYSIBM.SYSDUMMY1 WITH UR"                  								                          >> $GRANTOUT 
    db2 -x "SELECT 'GRANT USE OF TABLESPACE '||rtrim(TBSPACE)||' TO USER $APP_USER;'
            FROM SYSCAT.TABLESPACES 
            WHERE DATATYPE = 'U' WITH UR"                  				                                                        >> $GRANTOUT 
    db2 -x "SELECT 'GRANT USAGE on SEQUENCE '||rtrim(SEQSCHEMA)||'.'||rtrim(SEQNAME)||' TO USER $APP_USER;'
            FROM SYSCAT.SEQUENCES 
            WHERE SEQSCHEMA NOT LIKE 'SYS%' 
                  AND SEQTYPE = 'S' 
                  AND CREATE_TIME > CURRENT TIMESTAMP - 200 DAYS WITH UR"                                                             >> $GRANTOUT 
    db2 -x "SELECT 'GRANT EXECUTE ON SPECIFIC PROCEDURE '|| RTRIM(PROCSCHEMA)||'.'||RTRIM(SPECIFICNAME)||' TO USER $APP_USER;'
            FROM SYSCAT.PROCEDURES 
            WHERE PROCSCHEMA NOT LIKE 'SYS%' 
                  AND PROCSCHEMA NOT LIKE 'SQL%' 
                  AND CREATE_TIME > CURRENT TIMESTAMP - 200 DAYS WITH UR"                                                             >> $GRANTOUT 
    db2 -x "SELECT 'GRANT EXECUTE ON FUNCTION '|| RTRIM(FUNCSCHEMA)||'.'||RTRIM(FUNCNAME)||' TO USER $APP_USER;'
            FROM SYSCAT.FUNCTIONS 
            WHERE FUNCSCHEMA  NOT LIKE 'SYS%' 
                  AND CREATE_TIME > CURRENT TIMESTAMP - 200 DAYS WITH UR"                                                             >> $GRANTOUT 

    db2 -stvf $GRANTOUT                                                                                                               |tee -a $SCRIPTLOG
 
    RETCODE=$?
    DB2_SQL_INSERT="insert into dbatb.releasecontrol
                   (DBNAME,HOSTNAME,RELEASE_VERSION,STEP,STARTTIME,RETCODE)
                   values
                   ('$DBNAME','$HOSTNAME','$REL_VERSION','END DB PERMISSIONS',current timestamp,'$RETCODE')"
    #echo $DB2_SQL_INSERT
    db2 -v $DB2_SQL_INSERT                                                          |tee -a $SCRIPTLOG
    E_TIME=`date +%Y-%m-%d-%H.%M.%S`                                                                
    echo "\n E_TIME $E_TIME"                                                                                                             |tee -a $SCRIPTREP
    
    #db2 -v deactivate database $DBNAME                                                                                                |tee -a $SCRIPTLOG

    #db2 connect reset
fi

if [ "$ERR_FLAG" = "Y" ]
then
    echo "$ERROR_MSG"                                                                                                                 |tee -a $SCRIPTLOG #Notify OPS of error
    #uuencode "$SCRIPTLOG" RELEASE_"$REL_VERSION"_"$HOSTNAME"_"$DBNAME".log |mail -s "ERROR : $TITLE" $MAILTO_DBA          #Mail log to DBA
    #tail -30 "$SCRIPTLOG" | mail -s "ERROR : $TITLE" $MAILTO_DBA 
    exit 3
else
    echo "The END at `date`"                                                                                                      |tee -a $SCRIPTLOG
    ##----------------------------------------------------------------------
    ##--4. Check if any files were missed
    ##----------------------------------------------------------------------

    FILE_TO_PROCESS_EXEC=`ls "*execution_order"*.txt|wc -l`                                                                            
    echo "Exec Orders NOT processed : $FILE_TO_PROCESS_EXEC"                                                                      |tee -a $SCRIPTLOG #How many Exec Order .txt files were missed

    FILE_TO_PROCESS_DDL=`ls *.ddl|wc -l`                                                                                              
    echo "DDL Files NOT processed   : $FILE_TO_PROCESS_DDL"                                                                       |tee -a $SCRIPTLOG #How many .ddl files were missed

    FILE_TO_PROCESS_SQL=`ls *.sql|wc -l`                                                                                              
    echo "SQL Files NOT processed   : $FILE_TO_PROCESS_SQL"                                                                       |tee -a $SCRIPTLOG #How many .sql files were missed
    
    cd $SCRIPT_LOGDIR 
    #echo "Creating 'CREATE TS' Calls"                                                                                             |tee -a $SCRIPTLOG
    #db2 -txf DB2_CreateTBSpaceSPCalls.sql >$SCRIPTDDL
    #echo "Creating DDL file via db2look"                                                                                          |tee -a $SCRIPTLOG
    #db2look -d $DBNAME -e >> $SCRIPTDDL

    #echo "Sending mail to $MAILTO_DBA re ddl : $SCRIPTDDL"                                                                         |tee -a $SCRIPTLOG 
    #uuencode $SCRIPTDDL "$HOSTNAME"_"$DBNAME"_"$REL_VERSION"_"$TMSTAMP".ddl |mail -s "$TITLE : DDL" $MAILTO_DBA     #Mail latest DDL to DBA
    #mail -s "$TITLE : DDL" $MAILTO_DBA < "DDL Available on server : $SCRIPTDDL"


    cat $SCRIPTREP
    echo ""

    DB2_SQL_REPORT="SELECT STEP,substr(SCRIPTNAME,1,55) as SCRIPT_NAME,substr(SCRIPTDESCRIPTION,1,60) as DESCRIPTION,
                         TIME(STARTTIME) as time,EXECUTION_DURATION as duration,RETCODE           
                  from   dbatb.releasecontrol 
                  where RELEASE_VERSION = '$REL_VERSION' and date(starttime) = current date and STEP like '%Apply%'
                  order by DURATION DESC" 

    DB2_SQL_ENV="SELECT DISTINCT DBNAME, HOSTNAME,RELEASE_VERSION, DATE(STARTTIME) 
                  from   dbatb.releasecontrol
                  where RELEASE_VERSION = '$REL_VERSION' and date(starttime) = current date "

    DB2_SQL_REPORT_SUMMARY="SELECT MIN(EXECUTION_DURATION) as MIN, MAX(EXECUTION_DURATION) as MAX , AVG(EXECUTION_DURATION) as AVG
                            from   dbatb.releasecontrol
                            where RELEASE_VERSION = '$REL_VERSION' and date(starttime) = current date "

  echo ""
  db2 -v $DB2_SQL_ENV
  db2 -x $DB2_SQL_ENV | read REP_DBNAME REP_HOSTNAME REP_RELEASE_VERSION RELEASE_DATE DUMMY
  echo "==================================================================================================================================" |tee $SCRIPTREP
  echo ""                                                                                            |tee -a $SCRIPTREP
  echo "HOSTNAME : $REP_HOSTNAME"                                                                    |tee -a $SCRIPTREP
  echo "DBNAME   : $REP_DBNAME"                                                                      |tee -a $SCRIPTREP
  echo "RELEASE  : $REP_RELEASE_VERSION"                                                             |tee -a $SCRIPTREP
  echo "DATE     : $RELEASE_DATE"                                                                    |tee -a $SCRIPTREP
  echo ""                                                                                            |tee -a $SCRIPTREP
  echo "Report Detail"                                                                               |tee -a $SCRIPTREP
  echo "============="                                                                               |tee -a $SCRIPTREP
  echo ""                                                                                            |tee -a $SCRIPTREP
  db2 $DB2_SQL_REPORT                                                                                |tee -a $SCRIPTREP
  echo ""                                                                                            |tee -a $SCRIPTREP
  echo "Report Summary (seconds)"                                                                    |tee -a $SCRIPTREP
  echo "========================"                                                                    |tee -a $SCRIPTREP
  echo ""                                                                                            |tee -a $SCRIPTREP
  db2 $DB2_SQL_REPORT_SUMMARY                                                                        |tee -a $SCRIPTREP
  echo ""                                                                                            |tee -a $SCRIPTREP

    #echo "Sending mail to $MAILTO re script Duration : $SCRIPTREP"                                                             |tee -a $SCRIPTLOG
    #echo "Calculate total Release duration"
    #mail -s "$MAILSUBJECT_PM" $MAILTO,$MAILTO_DBA < $SCRIPTREP

    if [ "$PROD_FLAG" = "Y" ]
    then
         DB2_SQL_INSERT="insert into dbatb.releasecontrol
              (DBNAME,HOSTNAME,RELEASE_VERSION,STEP,STARTTIME)
              values
              ('$DBNAME','$HOSTNAME','$REL_VERSION','START DMLPACKAGE',current timestamp)"
     #echo $DB2_SQL_INSERT
     db2 -v $DB2_SQL_INSERT                                                          |tee -a $SCRIPTLOG

    echo "Creating archive for Release Management : $REL_MNGMNT_ARCHIVE"                                                          |tee -a $SCRIPTLOG
    cd $SCRIPT_DIR
    echo `pwd`
    tar cvf $REL_MNGMNT_ARCHIVE .                                                                                                 |tee -a $SCRIPTLOG
    echo "This mail was generated automatically by the DB2 Release control process. \n"                                           |tee $REL_MNGMNT_MAILBODY_TMP
    echo "An Archive of all DB2 script has been prepared for the Software library. \n"                                            |tee -a $REL_MNGMNT_MAILBODY_TMP
    echo "Database name   : $DBNAME \n"                                                                                           |tee -a $REL_MNGMNT_MAILBODY_TMP
    echo "Archive source  : $HOSTNAME:$REL_MNGMNT_ARCHIVE \n"                                                                     |tee -a $REL_MNGMNT_MAILBODY_TMP
    echo "Archive target  : '\\\\ptabrfap01\SIReleaseMngtProjDoc' \n"                                                             |tee -a $REL_MNGMNT_MAILBODY_TMP 
    echo ""                                                                                                                       |tee -a $REL_MNGMNT_MAILBODY_TMP
    echo "For further assistance, contact the DB2DBAs at DB2DBA@sars.gov.za"                                                      |tee -a $REL_MNGMNT_MAILBODY_TMP
    echo ""                                                                                                                       |tee -a $REL_MNGMNT_MAILBODY_TMP
    echo "Archive contents \n"                                                                                                    |tee -a $REL_MNGMNT_MAILBODY_TMP
    echo "================"                                                                                                       |tee -a $REL_MNGMNT_MAILBODY_TMP
    tar tvf $REL_MNGMNT_ARCHIVE                                                                                                   |tee -a $REL_MNGMNT_MAILBODY_TMP
  
        echo "Sending mail to $MAILTO_RELMNGMNT re DML Archive file : $REL_MNGMNT_MAILBODY_TMP"                                     |tee -a $SCRIPTLOG 
        #mail -s "$MAILSUBJECT_RELMNGMNT" $MAILTO_RELMNGMNT < $REL_MNGMNT_MAILBODY_TMP

         DB2_SQL_INSERT="insert into dbatb.releasecontrol
              (DBNAME,HOSTNAME,RELEASE_VERSION,STEP,STARTTIME)
              values
              ('$DBNAME','$HOSTNAME','$REL_VERSION','END DMLPACKAGE',current timestamp)"
     #echo $DB2_SQL_INSERT
     db2 -v $DB2_SQL_INSERT                                                         |tee -a $SCRIPTLOG

    if [ "$MAILTO_EDW" != "" ]
    then 
        echo "Notify EDW team"
        echo "Sending mail to $MAILTO_EDW re script Duration : $SCRIPTREP"                                                             |tee -a $SCRIPTLOG
        #mail -s "$MAILSUBJECT_PM" $MAILTO_EDW < $SCRIPTREP
    fi
 
    fi

    #Very last action : mail the DBAs
    echo "Sending mail to $MAILTO_DBA re Release Control log : "$SCRIPTLOG""                                                      |tee -a $SCRIPTLOG
    #uuencode "$SCRIPTLOG" RELEASE_"$REL_VERSION"_"$HOSTNAME"_"$DBNAME".log |mail -s "SUCCESS : $TITLE" $MAILTO_DBA                #Mail log to DBA
         DB2_SQL_INSERT="insert into dbatb.releasecontrol
              (DBNAME,HOSTNAME,RELEASE_VERSION,STEP,STARTTIME,RETCODE)
              values
              ('$DBNAME','$HOSTNAME','$REL_VERSION','END RELCTRL',current timestamp,'0')"
     #echo $DB2_SQL_INSERT
     db2 -v $DB2_SQL_INSERT                                                          |tee -a $SCRIPTLOG

     db2 -v deactivate database $DBNAME                                                                                                |tee -a $SCRIPTLOG

     db2 connect reset

    exit 0
fi

