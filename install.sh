#!/bin/bash

systemctl stop unattended-upgrades

[[ -z "${CLOUD_PROVIDER}" ]] && CLOUD_PROVIDER='aws' || CLOUD_PROVIDER="${CLOUD_PROVIDER}"
echo "Cloud provider is ${CLOUD_PROVIDER}"

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

apt-get -o DPkg::Lock::Tieout=-1 update -qq
curl -fsSL https://get.docker.com -o get-docker.sh

while ! command_exists htpasswd
do
    apt-get install -y apache2-utils
done

while ! command_exists /sbin/mount.nfs
do
    echo "Installing nfs-common"
    apt-get install -y nfs-common
done

while ! command_exists docker
do
    echo "installing docker engine"
    /bin/sh get-docker.sh
done

while ! command_exists jq
do
    apt-get update
    apt-get install -y jq
done

#default image
SEGRID_IMAGE="public.ecr.aws/orienlabs/segrid-router"

if [ $CLOUD_PROVIDER == "aws" ]; then
  while ! command_exists aws
  do
    echo "installing aws command line toos"
    apt-get install -y awscli
  done
  AWS_TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
  inst_id=`curl -H "X-aws-ec2-metadata-token: $AWS_TOKEN" -v http://169.254.169.254/latest/meta-data/instance-id`
  inst_ip=`curl -H "X-aws-ec2-metadata-token: $AWS_TOKEN" -v http://169.254.169.254/latest/meta-data/local-ipv4`
  availability_zone=`curl -H "X-aws-ec2-metadata-token: $AWS_TOKEN" -v http://169.254.169.254/latest/meta-data/placement/availability-zone| sed 's/.$//'`

  #enable host access from container
  aws ec2 modify-instance-metadata-options --instance-id $inst_id --http-put-response-hop-limit 2 --http-endpoint enabled
fi

if [ $CLOUD_PROVIDER == "azure" ]; then
  SEGRID_IMAGE="orienlabs.azurecr.io/segrid-router"
  while ! command_exists az
  do
    echo "installing azure command line tool"
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  done
  curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" > instanceMetadata.json
  inst_id=`cat instanceMetadata.json | jq -r '.compute.resourceId'`
  subscription_id=`cat instanceMetadata.json | jq -r '.compute.subscriptionId'`
  inst_ip=`cat instanceMetadata.json | jq -r '.. | .privateIpAddress? // empty'`
  inst_role=`cat instanceMetadata.json | jq -r '.. | .tagsList? //empty | .[] | select(.name=="GridRole") | .value'`
  availability_zone=`cat instanceMetadata.json | jq -r '.compute.location'`

  [[ ! -z "${inst_role}" ]] && SEGRID_ROLE="$inst_role"
  [[ ! -z "${SEGRID_ROLE}" ]] && echo "Starting in $SEGRID_ROLE role"

  curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/" > instanceToken.json
  access_token=`cat instanceToken.json | jq -r '.access_token'`
  client_id=`cat instanceToken.json | jq -r '.client_id'`
fi

echo "Current Instance ID : $inst_id, IP: $inst_ip, Availability Zone: $availability_zone" 

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

docker rm `docker ps -a -q --filter name=segrid-router` -f
docker rm `docker ps -a -q --filter name=sgr` -f

docker network create segrid
[[ -z "${SEGRID_VERSION}" ]] && SEGRID_VERSION='latest' || SEGRID_VERSION="${SEGRID_VERSION}"
[[ -z "${LOGGER}" ]] && LOGGER='INFO' || LOGGER="${LOGGER}"

echo "starting segrid router version $SEGRID_VERSION"
docker pull public.ecr.aws/orienlabs/segrid-router:$SEGRID_VERSION
docker run -d \
    --restart no                                 \
	  -v /var/run/docker.sock:/var/run/docker.sock \
    -p 8080:8080 			                           \
    --name sgr          	                       \
    -e CLOUD_PROVIDER=$CLOUD_PROVIDER            \
    -e INSTANCE_ID=$inst_id                      \
    -e INSTANCE_IP=$inst_ip                      \
    -e INSTANCE_REGION=$availability_zone        \
    -e AWC_EC2_METADATA_DISABLED=false           \
    -e DOCKER_HOST=unix:///var/run/docker.sock 	 \
    -e GGR_DIR=/home/segrid/config/grid-router 	 \
    -e GGR_QUOTA_USER=$GGR_USER 	               \
    -e GGR_QUOTA_PASSWORD=$GGR_PASSWORD 	       \
    -e CONFIG_DIR=/home/segrid/config            \
    -e SEGRID_VERSION=$SEGRID_VERSION 	         \
    -e _JAVA_OPTIONS=-Dlogging.level.com.orienlabs=$LOGGER 	                         \
    --net=host                                   \
    --pull always 			                         \
    -v /home/segrid:/home/segrid:rw              \
    -v /:/host:ro                                \
    --env-file <(env | grep SEGRID)              \
    $SEGRID_IMAGE:$SEGRID_VERSION

#keep it connected from a Jenkins machine    
#docker logs --follow sgr