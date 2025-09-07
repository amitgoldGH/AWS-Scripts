#!/bin/bash
set -e
echo "Script for creating an EC2 instance, then attaching a EBS GP3 Volume, and allocating and assigning an Elastic IP"
echo "Make sure you already used AWS Configure before this!"
echo "Creating Suffixed Tags and names"
SUFFIX=$(date +%s)
KEY_NAME="MyKeyPair-$SUFFIX"
SG_NAME="MySecurityGroup-$SUFFIX"
INSTANCE_TAG="MyTestServer-$SUFFIX"
VOLUME_TAG="MyVolume-$SUFFIX"
EIP_TAG="MyElasticIP-$SUFFIX"

echo "Step: Creating key pair $KEY_NAME"
aws ec2 create-key-pair --key-name $KEY_NAME --query "KeyMaterial" --output text > $KEY_NAME.pem
chmod 400 $KEY_NAME.pem

echo "Step: Creating security group $SG_NAME"
SG_ID=$(aws ec2 create-security-group --group-name $SG_NAME --description "Allow SSH and HTTP access for $INSTANCE_TAG" --query 'GroupId' --output text)

echo "Step: Modifying security group to allow SSH (ID: $SG_ID)"
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

echo "Step: Modifying security group to allow HTTP (ID: $SG_ID)"
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0

echo "Step: Getting Amazon Linux 2023 latest AMI ID"
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-*" "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --output text)

echo "Step: Creating EC2 Instance (Tag - $INSTANCE_TAG) with AMI ID: $AMI_ID"
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --count 1 \
  --instance-type t3.micro \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_TAG}]" \
  --query "Instances[0].InstanceId" --output text)

#INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$INSTANCE_TAG" --query "Reservations[0].Instances[0].InstanceId" --output text)

AZ=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].Placement.AvailabilityZone" --output text)

echo "Step: Creating EBS Volume - 5GB, GP3) - Tag: $VOLUME_TAG"
VOL_ID=$(aws ec2 create-volume --size 5 --availability-zone $AZ --volume-type gp3 --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=$VOLUME_TAG}]" --query "VolumeId" --output text)

#VOL_ID=$(aws ec2 describe-volumes --filters "Name=tag:Name,Values=$VOLUME_TAG" --query "Volumes[0].VolumeId" --output text)

echo "Step: Waiting for resources to be ready (Instance and volume)"
aws ec2 wait instance-running --instance-ids $INSTANCE_ID
aws ec2 wait volume-available --volume-ids $VOL_ID

echo "Resources ready!"

echo "Step: Attaching created volume (ID: $VOL_ID) to instance (ID: $INSTANCE_ID)"
aws ec2 attach-volume --volume-id $VOL_ID --instance-id $INSTANCE_ID --device /dev/sdf

echo "Step: Creating Elastic IP - Tag: $EIP_TAG"
EIP_ID=$(aws ec2 allocate-address --domain vpc --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$EIP_TAG}]" --query "AllocationId" --output text)
#EIP_ID=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=$EIP_TAG" --query "Addresses[0].AllocationId" --output text)
INSTANCE_EIP=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=$EIP_TAG" --query "Addresses[0].PublicIp" --output text)

echo "Step: Associating Elastic IP (ID: $EIP_ID, IP: $INSTANCE_EIP) to Instance(ID: $INSTANCE_ID)"
aws ec2 associate-address --instance-id $INSTANCE_ID --allocation-id $EIP_ID

echo "Results: Instance name: $INSTANCE_TAG, Volume name: $VOLUME_TAG, Public IP: $INSTANCE_EIP"
echo "To connect via ssh use: ssh -i $KEY_NAME.pem ec2-user@$INSTANCE_EIP"
