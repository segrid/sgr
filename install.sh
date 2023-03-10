#!/bin/bash

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

docker rm `docker ps -a -q --filter name=segrid-router` -f

AWS_TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
inst_id=`curl -H "X-aws-ec2-metadata-token: $AWS_TOKEN" -v http://169.254.169.254/latest/meta-data/instance-id`
availability_zone=`curl -H "X-aws-ec2-metadata-token: $AWS_TOKEN" -v http://169.254.169.254/latest/meta-data/placement/availability-zone| sed 's/.$//'`

echo "Current Instance ID : $inst_id, Availability Zone: $availability_zone" 

#enable host access from container
aws ec2 modify-instance-metadata-options --instance-id $inst_id --http-put-response-hop-limit 2 --http-endpoint enabled

#allow port access from outside the instance
docker network prune -f
systemctl daemon-reload
systemctl stop docker
systemctl enable --now docker
systemctl start docker

iptables -I INPUT 5 -p tcp -m tcp --dport 8080 -j ACCEPT	#sgr
iptables -I INPUT 5 -p tcp -m tcp --dport 8081 -j ACCEPT	#selenoid ui
iptables -I INPUT 5 -p tcp -m tcp --dport 8082 -j ACCEPT	#ggr-ui
iptables -I INPUT 5 -p tcp -m tcp --dport 4444 -j ACCEPT	#selenoid
iptables -I INPUT 5 -p tcp -m tcp --dport 4445 -j ACCEPT	#ggr (status endpoint)

chmod a+rw /var/run/docker.sock

GGR_USER=segrid
GGR_PASSWORD=aa801ea6-87be-4ea8-ab27-ef45b248c17e

mkdir -p /home/segrid/config
mkdir -p /home/segrid/config/grid-router
htpasswd -bc /home/segrid/config/grid-router/users.htpasswd $GGR_USER $GGR_PASSWORD

chmod -R 777 /home/segrid
docker network create segrid
[[ -z "${SEGRID_VERSION}" ]] && SEGRID_VERSION='latest' || SEGRID_VERSION="${SEGRID_VERSION}"
echo "starting segrid router version $SEGRID_VERSION"
docker run -d \
    --restart no                                 \
	-v /var/run/docker.sock:/var/run/docker.sock \
    -p 8080:8080 			                     \
    --name segrid-router 	                     \
    -e CLOUD_PROVIDER=aws 	                     \
    -e INSTANCE_ID=$inst_id                      \
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
#docker logs -f segrid-router