#!/bin/bash

su - hdfs

hive -e 'show databases' > /tmp/upgrade/hive_databases.txt
if [ $? != 0 ]; then                   # last command: echo
  echo "Waiting to get list of all Databases"
else
OUTPUT=/root/upgradepresteps/review
#cat hive_databases.txt | awk '{if(NR>4)print}' | grep -v "Time taken:" > dbs.txt
DBS=`tr -s '\n ' ',' < /tmp/upgrade/hive_databases.txt`
DBS=${DBS%,}

echo "/usr/jdk64/jdk1.8.0_112/bin/java -cp $SRE_CP com.streever.hive.Sre u3 -db $DBS -cfg  config.yaml -o $OUTPUT "

fi
