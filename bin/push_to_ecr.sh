repo=$1
dir=$2
service=$3
tag=$4
aws_key=$5
aws_secret=$6
args=$7

cd $dir
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 053376294935.dkr.ecr.us-east-1.amazonaws.com
docker build -t $service --build-arg GITHUB_SHA=${GITHUB_SHA} --build-arg GITHUB_TAG_NAME=${GIT_TAG_NAME} \
       --build-arg AWS_ACCESS_KEY_ID=$aws_key --build-arg AWS_SECRET_ACCESS_KEY=$aws_secret $BULID_ARGS .
docker tag $service:latest 053376294935.dkr.ecr.us-east-1.amazonaws.com/$repo:$tag
docker push 053376294935.dkr.ecr.us-east-1.amazonaws.com/$repo:$tag
docker tag 053376294935.dkr.ecr.us-east-1.amazonaws.com/$repo:$tag 053376294935.dkr.ecr.us-east-1.amazonaws.com/$repo:$tag
docker push 053376294935.dkr.ecr.us-east-1.amazonaws.com/$repo:$tag
