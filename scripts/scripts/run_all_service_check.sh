#!/bin/bash


AMBARI_HOST=$1
PORT=$2
LOGIN=$3
PASSWORD=$4 
OSOUT=$5
SERCHK=$6
date=$7
intr=$8
protocol=$9


# Configuring cluster name
cluster_name=$(curl -s -u $LOGIN:$PASSWORD --insecure "$protocol://$AMBARI_HOST:$PORT/api/v1/clusters"  | python -mjson.tool | perl -ne '/"cluster_name":.*?"(.*?)"/ && print "$1\n"')


# Condition to check cluster name exists
if [ -z "$cluster_name" ]; then
    exit
fi

# OS version check 
echo -e "\nChecking if OS version of the nodes in cluster $cluster_name is compatible for upgrade"
curl -s -u $LOGIN:$PASSWORD --insecure "$protocol://$AMBARI_HOST:$PORT/api/v1/clusters/$cluster_name/hosts" | grep host_name | awk -F ':' '{print $2}' |  awk -F '"' '{print $2}' >  $intr/hosts.txt


while IFS= read -r host
do
os=$(curl -s -u $LOGIN:$PASSWORD --insecure "$protocol://$AMBARI_HOST:$PORT/api/v1/clusters/$cluster_name/hosts/$host?fields=Hosts/os_type" | grep os_type | grep -v href | awk -F ':' '{print $2}' |  awk -F '"' '{print $2}')

if [ "$os" != "centos7" ]; then
 echo -e "Operating system for $host is NOT compatible for upgrade" >> $OSOUT/oscheck-$date.out
else
 echo -e "Operating system for $host is compatible for upgrade" >> $OSOUT/oscheck-$date.out
fi

done < $intr/hosts.txt

echo -e "\nOS compatibility check completed for$cluster_name. \n please check the output in $OSOUT/oscheck-$date.out"
# OS version check COMPLETED !!!!!



echo -e "\nCluster name to run service check on is: $cluster_name"
 
running_components=$(curl -s -u $LOGIN:$PASSWORD --insecure "$protocol://$AMBARI_HOST:$PORT/api/v1/clusters/$cluster_name/services?fields=ServiceInfo/service_name&ServiceInfo/maintenance_state=OFF" | python -mjson.tool | perl -ne '/"service_name":.*?"(.*?)"/ && print "$1\n"')
if [ -z "$running_components" ]; then
    exit
fi
#echo "There are following running services :
#$running_components"
 
post_body=
for s in $running_components; do
    if [ "$s" == "ZOOKEEPER" ]; then
        post_body="{\"RequestInfo\":{\"context\":\"$s Service Check\",\"command\":\"${s}_QUORUM_SERVICE_CHECK\"},\"Requests/resource_filters\":[{\"service_name\":\"$s\"}]}"
 
    else
        post_body="{\"RequestInfo\":{\"context\":\"$s Service Check\",\"command\":\"${s}_SERVICE_CHECK\"},\"Requests/resource_filters\":[{\"service_name\":\"$s\"}]}"
    fi
    curl -s -u $LOGIN:$PASSWORD --insecure -H "X-Requested-By:X-Requested-By" -X POST --data "$post_body"  "$protocol://$AMBARI_HOST:$PORT/api/v1/clusters/$cluster_name/requests"

echo -e "Please check ambariUI to confirm the status of ServiceCheck"
done

