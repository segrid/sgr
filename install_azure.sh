#!/bin/bash

systemctl stop unattended-upgrades

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

apt-get -o DPkg::Lock::Tieout=-1 update -qq
curl -fsSL https://get.docker.com -o get-docker.sh

while ! command_exists htpasswd
do
    apt-get install -y apache2-utils
done

while ! command_exists docker
do
    echo "installing docker engine"
    /bin/sh get-docker.sh
done

while ! command_exists az
do
    echo "installing azure command line tool"
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
done

while ! command_exists jq
do
    apt-get update
    apt-get install -y jq
done

docker rm `docker ps -a -q --filter name=segrid-router` -f

curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" > instanceMetadata.json
inst_id=`cat instanceMetadata.json | jq -r '.compute.vmId'`
inst_ip=`cat instanceMetadata.json | jq -r '.. | .privateIpAddress? // empty'`

availability_zone=`cat instanceMetadata.json | jq -r '.compute.location'`
echo "Current Instance ID : $inst_id, Availability Zone: $availability_zone"

echo "Ensure Identity is created and assigned"
curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/" > instanceToken.json
access_token=`cat instanceToken.json | jq -r '.access_token'`
client_id=`cat instanceToken.json | jq -r '.client_id'`

#enable host access from container
#aws ec2 modify-instance-metadata-options --instance-id $inst_id --http-put-response-hop-limit 2 --http-endpoint enabled

#allow port access from outside the instance
docker network prune -f
systemctl daemon-reload
systemctl stop docker
systemctl enable --now docker
systemctl start docker

iptables -I INPUT -p tcp -m tcp --dport 8080 -j ACCEPT	#sgr
iptables -I INPUT -p tcp -m tcp --dport 8081 -j ACCEPT	#selenoid ui
iptables -I INPUT -p tcp -m tcp --dport 8082 -j ACCEPT	#ggr-ui-status
iptables -I INPUT -p tcp -m tcp --dport 8083 -j ACCEPT	#ggr-ui-selenoid
iptables -I INPUT -p tcp -m tcp --dport 4444 -j ACCEPT	#selenoid
iptables -I INPUT -p tcp -m tcp --dport 4445 -j ACCEPT	#ggr (status endpoint)

chmod a+rw /var/run/docker.sock

GGR_USER=segrid
GGR_PASSWORD=aa801ea6-87be-4ea8-ab27-ef45b248c17e

mkdir -p /home/segrid/config
mkdir -p /home/segrid/config/grid-router
htpasswd -bc /home/segrid/config/grid-router/users.htpasswd $GGR_USER $GGR_PASSWORD

echo "Stopping legacy SeGrid"
service SeGridRouter stop
service SeGridRouter disable

chmod -R 777 /home/segrid
docker network create segrid
SEGRID_VERSION=1.2.0
[[ -z "${SEGRID_VERSION}" ]] && SEGRID_VERSION='latest' || SEGRID_VERSION="${SEGRID_VERSION}"
echo "starting segrid router version $SEGRID_VERSION"
docker pull public.ecr.aws/orienlabs/segrid-router:$SEGRID_VERSION
docker run -d \
    --restart no                                 \
	-v /var/run/docker.sock:/var/run/docker.sock \
    -p 8080:8080 			                     \
    --name segrid-router 	                     \
    -e CLOUD_PROVIDER=azure	                     \
    -e INSTANCE_ID=$inst_id                      \
    -e INSTANCE_IP=$inst_ip                      \
    -e AWS_REGION=$availability_zone             \
    -e AWC_EC2_METADATA_DISABLED=false           \
    -e DOCKER_HOST=unix:///var/run/docker.sock 	 \
    -e GGR_DIR=/home/segrid/config/grid-router 	 \
    -e GGR_QUOTA_USER=$GGR_USER 	             \
    -e GGR_QUOTA_PASSWORD=$GGR_PASSWORD 	     \
    -e CONFIG_DIR=/home/segrid/config            \
    -e SEGRID_VERSION=$SEGRID_VERSION 	         \
    --net=host                                   \
    --pull always 			                     \
    -v /home/segrid:/home/segrid:rw              \
    public.ecr.aws/orienlabs/segrid-router:$SEGRID_VERSION

#keep it connected from a Jenkins machine    
docker logs -f segrid-router