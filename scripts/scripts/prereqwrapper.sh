#!/bin/bash

echo -en "\e[94mEnter Ambari server host name : \e[0m"
read "ambarihost"
AMBARI_HOST=$ambarihost
echo -en "\e[94mEnter Ambari server port : \e[0m"
read "ambariport"
PORT=$ambariport
echo -en "\e[94mIs SSL enabled for $AMBARI_HOST (yes/no) : \e[0m"
read  "ssl"
SSL=$ssl

echo -en "\e[94mEnter Ambari admin's User Name: \e[0m"
read "username"
echo -en "\e[94mEnter Password for $username : \e[0m"
read -s "pwd"
LOGIN=$username
PASSWORD=$pwd

if  [ "$SSL" == "no" ];then
 export PROTOCOL=http
else
 export PROTOCOL=https
fi

echo -e "\n"


# confirming ambari credentials
cluster_name=$(curl -s -u $LOGIN:$PASSWORD --insecure "$PROTOCOL://$AMBARI_HOST:$PORT/api/v1/clusters" | grep cluster_name | awk -F':' '{print $2}' | awk -F'"' '{print $2}')

if [ -z "$cluster_name" ]
then
      echo -e "\e[31mAmbari details entered are \n AmbariHost: $AMBARI_HOST \n AmbariPort: $PORT \n AdminUser: $LOGIN \n Password: $PASSWORD \e[0m \n"
      echo -e "\e[31mPlease check the Ambari details entered !!!! \e[0m"
   exit
fi


#HDPVERSION=`hdp-select versions | awk -F'-' '{print $1}'`



# Initial Dir Structure :
today="$(date +"%Y%m%d%H%M")"
USER=`whoami`
mkdir -p /upgrade/files 
mkdir -p /upgrade/review/hive
mkdir -p /upgrade/review/os
mkdir -p /upgrade/review/servicecheck
mkdir -p /upgrade/scripts
mkdir -p /upgrade/hivechecks
mkdir -p /upgrade/logs
mkdir -p /upgrade/backup

INTR=/upgrade
HIVECFG=/upgrade/hivechecks
SCRIPTDIR=/upgrade/scripts
REVIEW=/upgrade/review
LOGDIR=/upgrade/logs
BKP=/upgrade/backup


#To check if config.yaml file exists

if [ ! -f /upgrade/hivechecks/config.yaml ]; then
    echo -e "\e[31mconfig.yaml file missing in /upgrade/hivechecks/  \n Download template and configure it https://github.com/dstreev/cloudera_upgrade_utils/blob/master/hive-sre/configs/driver.yaml.template \e[0m"
    exit
fi

if [ ! -f /upgrade/hivechecks/hive-sre-shaded.jar ]; then
 echo -e "\e[31mPlease dowbload hive-sre-shaded.jar file from : https://github.com/dstreev/cloudera_upgrade_utils/releases \e[0m"
  exit
fi


#############################################################################################################

# BACKPUP : Ambari-DB / ambari.properites / ambari-env.sh
# Password less ssh is mush
# works with PGSQL and MYSQL
# Need to test to for mariadb and oracle


echo -e "\e[96mPREREQ - Ambari Backup :\e[0m  DB | ambari.properties | ambari-env.sh"
sh $SCRIPTDIR/ambaribkp.sh $AMBARI_HOST $BKP $today &> $LOGDIR/ambaribkp-$today.log &

echo -e "\e[32mYou can check the logs in $LOGDIR/ambaribkp-$today.log \e[0m  \n"

sleep 60

#############################################################################################################



# Running hive upgrade check :
echo -e "\e[96mPREREQ - Running Hive table  check which includes:\e[0m  \n 1. Hive 3 Upgrade Checks - Locations Scan \n 2. Hive 3 Upgrade Checks - Bad ORC Filenames \n 3. Hive 3 Upgrade Checks - Managed Table Migrations ( Ownership check & Conversion to ACID tables) \n 4. Hive 3 Upgrade Checks - Compaction Check \n 5. Questionable Serde's Check \n 6. Managed Table Shadows \n"

# In case of kerberos, add a section to kint as hdfs user 
# In case of no kerberos, enable acls, give pemission to root user on all hdfs paths
# Set ACL for root user
# hdfs dfs -setfacl -R -m user:root:rwx /

sh $SCRIPTDIR/hiveprereq.sh $INTR/files/hive_databases.txt $HIVECFG  $REVIEW/hive  &> $LOGDIR/hiveprereq-$today.log &

echo -e "\e[32mOutput is available in $REVIEW/hive directory \e[0m"
echo -e "\e[32mYou can check the logs in $LOGDIR/hiveprereq-$today.log file  \e[0m \n"


#############################################################################################################
sleep 20
echo -e "\e[96mPREREQ - \e[0m Services Installed - to be deleted before upgrade"

curl -s -u $LOGIN:$PASSWORD --insecure "$PROTOCOL://$AMBARI_HOST:$PORT/api/v1/clusters/$cluster_name/services?fields=ServiceInfo/service_name" | python -mjson.tool | perl -ne '/"service_name":.*?"(.*?)"/ && print "$1\n"' > $INTR/files/services.txt

services=`egrep -i "storm|ACCUMULO|SMARTSENSE|Superset|Flume|Mahout|Falcon|Slider|WebHCat|spark" $INTR/files/services.txt | grep -v -i spark2 | tr -s '\n ' ','`
services=${services%,} 

echo -e "\e[31m Below services are installed in cluster\e[0m \e[96m $cluster_name\e[0m \e[31m and will be deleted as a part of upgrade:\e[0m  \n $services"

# NEED TO ADD SR SAM !!!!!!!
isnifi=`egrep -i "NIFI" $INTR/files/services.txt | grep -v -i spark2 | tr -s '\n ' ','`
isnifi=${isnifi%,}

if [ -z "$isnifi" ]
then
echo -e "\e[32m HDF mpack check completed\e[0m"
else
echo -e "\e[31m HDF Mpack is installed in $cluster_name \n Please remove it before upgrade\e[0m"
echo -e "\e[31m HDF Mpack is installed in $cluster_name \n Please remove it before upgrade\e[0m" > $REVIEW/servicecheck/RemoveServices-$today.out
echo -e "\e[31m HDF mpack check completed\e[0m\n"
fi

echo -e "\n \e[31mYou can plan to remove these services before upgarde\e[0m"

echo -e "\e[31m Removing the Druid and Accumulo services cause data loss\e[0m"
echo -e "\e[31m Do not proceed with the upgrade to HDP 7.1.1.0 if you want to continue with Druid and Accumulo services.\e[0m\n"


echo -e "\e[31mStorm can be replaced with Cloudera Streaming Analytics (CSA) powered by Apache Flink. Contact your Cloudera account team for more information about moving from Storm to CSA\e[0m\n"

echo -e "\e[31mFlume workloads can be migrated to Cloudera Flow Management (CFM). CFM is a no-code data ingestion and management solution powered by Apache NiFi.\e[0m \n"


echo -e "Below services are installed in cluster $cluster_name and will be deleted as a part of upgrade:  \n $services \n - You can plan to remove these services before upgarde \n - Removing the Druid and Accumulo services cause data loss \n -  Do not proceed with the upgrade to HDP 7.1.1.0 if you want to continue with Druid and Accumulo services \n -  Storm can be replaced with Cloudera Streaming Analytics (CSA) powered by Apache Flink. Contact your Cloudera account team for more information about moving from Storm to CSA \n - Flume workloads can be migrated to Cloudera Flow Management (CFM). CFM is a no-code data ingestion and management solution powered by Apache NiFi\n"  >>  $REVIEW/servicecheck/RemoveServices-$today.out



echo -e "\e[32m Please check the output at $REVIEW/servicecheck/RemoveServices-$today.out for the actions to take on components installed in cluster $cluster_name\e[0m \n"

#############################################################################################################
echo -e "\e[96mPREREQ - \e[0m Third Party Services - to be deleted before upgrade"

# ADD MORE SERVICES forex: SR, SAM etc... Mpacks
thirdparty=`egrep -vi "AMBARI_INFRA|AMBARI_METRICS|ATLAS|FLUME|HBASE|HDFS|HIVE|KAFKA|MAPREDUCE2|PIG|RANGER|RANGER_KMS|SLIDER|SMARTSENSE|SPARK|SPARK2|SQOOP|TEZ|YARN|ZOOKEEPER|NIFI|KERBEROS|KNOX|ACCUMULO|DRUID|MAHOUT|SUPERSET" $INTR/files/services.txt | grep -v -i spark2 | tr -s '\n ' ','`
thirdparty=${thirdparty%,}

if [ -z "$thirdparty" ];then
echo -e "\e[32m There are no Third Party Services installed on this cluster $cluster_name\e[0m\n"

else 

echo -e "\e[31m Below Third Party services are installed in cluster\e[0m \e[96m $cluster_name\e[0m \n \e[31m Please remove this before  upgrade:\e[0m  \n $thirdparty"

 echo -e "\e[31m Below Third Party services are installed in cluster\e[0m \e[96m $cluster_name\e[0m \n \e[31m Please remove this before  upgrade:\e[0m  \n $thirdparty"  >> $REVIEW/servicecheck/third-party-$today.out
fi

#############################################################################################################
echo -e "\n\e[96mPREREQ - \e[0m Checking OS compatibility and running service check"
sh $SCRIPTDIR/run_all_service_check.sh $AMBARI_HOST $PORT $LOGIN $PASSWORD $REVIEW/os $REVIEW/servicecheck $today $INTR/files/ $PROTOCOL  &> $LOGDIR/os-servicecheck-$today.log  &

echo -e "\e[32m Output is available in $REVIEW/os  directory \e[0m"
echo -e "\e[32m You can check the logs in $LOGDIR/os-servicecheck-$today.log  \e[0m \n"
