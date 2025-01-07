#!/bin/bash

# Variables
dir=$1
ECR_REPO="053376294935.dkr.ecr.us-east-1.amazonaws.com/demo-proxy-app"
TAG="latest"
IMAGE_NAME="demo-proxy-app"


cd $dir
# Step 1: Authenticate Docker to the ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO

# Step 2: Build the Docker image
docker build -t $IMAGE_NAME .

# Step 3: Tag the Docker image with the ECR repository URL
docker tag $IMAGE_NAME:latest $ECR_REPO:$TAG

# Step 4: Push the Docker image to ECR
docker push $ECR_REPO:$TAG

# Confirmation
echo "Docker image '$IMAGE_NAME' with tag '$TAG' has been pushed to ECR repository '$ECR_REPO'"
