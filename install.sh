#!/bin/bash

systemctl stop unattended-upgrades

[[ -z "${SEGRID_CLOUD_PROVIDER}" ]] && export SEGRID_CLOUD_PROVIDER='aws' || export SEGRID_CLOUD_PROVIDER="${SEGRID_CLOUD_PROVIDER}"
echo "Cloud provider is ${SEGRID_CLOUD_PROVIDER}"

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

apt-get -o DPkg::Lock::Tieout=-1 update -qq

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
    curl -fsSL https://get.docker.com -o get-docker.sh
    /bin/sh get-docker.sh
done

while ! command_exists jq
do
    apt-get update
    apt-get install -y jq
done

#default image
export SEGRID_IMAGE="public.ecr.aws/orienlabs/segrid-router"

if [[ $SEGRID_CLOUD_PROVIDER == "aws" ]]; then
  echo "querying aws services"
  while ! command_exists aws
  do
    echo "installing aws command line toos"
    apt-get install -y awscli
  done
  AWS_TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
  export SEGRID_INSTANCE_ID=`curl -H "X-aws-ec2-metadata-token: $AWS_TOKEN" -v http://169.254.169.254/latest/meta-data/instance-id`
  export SEGRID_INSTANCE_IP=`curl -H "X-aws-ec2-metadata-token: $AWS_TOKEN" -v http://169.254.169.254/latest/meta-data/local-ipv4`
  export SEGRID_INSTANCE_REGION=`curl -H "X-aws-ec2-metadata-token: $AWS_TOKEN" -v http://169.254.169.254/latest/meta-data/placement/availability-zone| sed 's/.$//'`

  #enable host access from container
  aws ec2 modify-instance-metadata-options --instance-id $SEGRID_INSTANCE_ID --http-put-response-hop-limit 2 --http-endpoint enabled
fi

if [[ $SEGRID_CLOUD_PROVIDER == "azure" ]]; then
  echo "querying azure services"
  export SEGRID_IMAGE="orienlabs.azurecr.io/segrid-router"
  while ! command_exists az
  do
    echo "installing azure command line tool"
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  done
  curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" > instanceMetadata.json
  export SEGRID_INSTANCE_ID=`cat instanceMetadata.json | jq -r '.compute.resourceId'`
  export SEGRID_INSTANCE_IP=`cat instanceMetadata.json | jq -r '.. | .privateIpAddress? // empty'`
  export SEGRID_ROLE=`cat instanceMetadata.json | jq -r '.. | .tagsList? //empty | .[] | select(.name=="SEGRID_ROLE") | .value'`
  export SEGRID_INSTANCE_REGION=`cat instanceMetadata.json | jq -r '.compute.location'`

  [[ ! -z "${SEGRID_ROLE}" ]] && echo "Starting in $SEGRID_ROLE role"

  export SEGRID_VERSION=`cat instanceMetadata.json | jq -r '.. | .tagsList? //empty | .[] | select(.name=="SEGRID_VERSION") | .value'`

  curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/" > instanceToken.json
  access_token=`cat instanceToken.json | jq -r '.access_token'`
  client_id=`cat instanceToken.json | jq -r '.client_id'`
fi

echo "Current Instance ID : $SEGRID_INSTANCE_ID, IP: $SEGRID_INSTANCE_IP, Availability Zone: $SEGRID_INSTANCE_REGION" 

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

export GGR_USER=segrid
export GGR_PASSWORD=aa801ea6-87be-4ea8-ab27-ef45b248c17e

mkdir -p /home/segrid/config
mkdir -p /home/segrid/config/grid-router
htpasswd -bc /home/segrid/config/grid-router/users.htpasswd $GGR_USER $GGR_PASSWORD

echo "Stopping legacy SeGrid"
service SeGridRouter stop
service SeGridRouter disable

chmod -R 777 /home/segrid

docker rm `docker ps -a -q --filter name=segrid-router` -f
docker rm `docker ps -a -q --filter name=sgr` -f

[[ -z "${SEGRID_VERSION}" ]] && export SEGRID_VERSION='latest' || export SEGRID_VERSION="${SEGRID_VERSION}"
[[ -z "${LOGGER}" ]] && export LOGGER='INFO' || export LOGGER="${LOGGER}"

echo "Starting router with following environment variables"
echo `env | grep SEGRID`

export MAX_MEM_JDK_MB=$(expr `vmstat -s | grep 'total memory' | tr -s " " " " | cut -d " " -f2` / 1024 / 8 "*" 5)
export MAX_MEM_CON_MB=$(expr `vmstat -s | grep 'total memory' | tr -s " " " " | cut -d " " -f2` / 1024 / 8 "*" 6)

echo "starting segrid router version $SEGRID_VERSION"
docker pull public.ecr.aws/orienlabs/segrid-router:$SEGRID_VERSION
docker run -d \
    --restart no                                 \
	  -v /var/run/docker.sock:/var/run/docker.sock \
    -p 8080:8080 			                           \
    --name sgr          	                       \
    -e AWC_EC2_METADATA_DISABLED=false           \
    --memory ${MAX_MEM_CON_MB}m                  \
    -e DOCKER_HOST=unix:///var/run/docker.sock 	 \
    -e GGR_DIR=/home/segrid/config/grid-router 	 \
    -e GGR_QUOTA_USER=$GGR_USER 	               \
    -e GGR_QUOTA_PASSWORD=$GGR_PASSWORD 	       \
    -e CONFIG_DIR=/home/segrid/config            \
    -e _JAVA_OPTIONS=-Dlogging.level.com.orienlabs=$LOGGER 	                         \
    -e JAVA_TOOL_OPTIONS="-Xms100M -Xmx${MAX_MEM_JDK_MB}M"    \
    --net=host                                   \
    --pull always 			                         \
    -v /home/segrid:/home/segrid:rw              \
    -v /:/host:ro                                \
    --env-file <(env | grep SEGRID)              \
    $SEGRID_IMAGE:$SEGRID_VERSION

#keep it connected from a Jenkins machine    
#docker logs --follow sgr
