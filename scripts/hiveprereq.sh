#!/bin/bash


db=$1
CFG=$2

 hive -e 'show databases' > $db

if [ $? != 0 ]; then                   # last command: echo
  echo "Waiting to get list of all Databases"
else

OUTPUT=$3
#cat hive_databases.txt | awk '{if(NR>4)print}' | grep -v "Time taken:" > dbs.txt
DBS=`tr -s '\n ' ',' < $db`
DBS=${DBS%,}

echo -e "Checking all the tables in databases :$BDS"

# Based on Metasore DB config connector JAR
export SRE_CP=$CFG/hive-sre-shaded.jar:$CFG/mysql-connector-java.jar


echo -e "Running hive preupgrade checks!!!"
/usr/jdk64/jdk1.8.0_112/bin/java -cp $SRE_CP com.streever.hive.Sre u3 -db $DBS -cfg  $CFG/config.yaml -o $OUTPUT 

fi
