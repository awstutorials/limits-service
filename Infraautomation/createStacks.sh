#!/bin/bash

#if [[ -z ${AWS_PROFILE} ]]; then
#    echo "Unknown AWS Profile!"
#    exit 1
if [[ -z $1 ]]; then
    echo "Please provide a stack prefix!"
    exit 1
elif [[ -z $2 ]]; then
    echo "No keypair provided!"
    exit 1
elif [[ -z $3 ]]; then
    echo "No team name provided!"
    exit 1
fi

CF_BUCKET=$1-cf-bucket

aws s3api head-bucket --bucket ${CF_BUCKET}
if [[ $? > 0 ]]; then
    aws s3api create-bucket --bucket ${CF_BUCKET} --create-bucket-configuration LocationConstraint=eu-west-1
fi

aws cloudformation package --template-file master-stack.yaml --s3-bucket ${CF_BUCKET} --output-template-file packaged-stack.yml


STACK_NAME=$1-stack

echo $2
echo $3

aws cloudformation deploy --template-file ./packaged-stack.yml --stack-name ${STACK_NAME}  --parameter-overrides KeyPair=$2 TeamName=$3 --capabilities CAPABILITY_IAM


exit 0