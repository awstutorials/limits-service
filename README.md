![build-status](https://codebuild.eu-west-1.amazonaws.com/badges?uuid=eyJlbmNyeXB0ZWREYXRhIjoiKzBuNjJCUFk2STRvbDZENXlMUFJOenF2V2EyQ3FMbEtuWDlQeVp6TWlxdXhNMGVOZGo5bG9jdTl1YU16RmZIVVNxa3VqTVg3V3drSnJxOUQwSmhqV2g0PSIsIml2UGFyYW1ldGVyU3BlYyI6IlJJRE4wZGJaS25LL0s0dzkiLCJtYXRlcmlhbFNldFNlcmlhbCI6MX0%3D&branch=master)

# Deploying Microservices with Amazon ECS, AWS CloudFormation, and an Application Load Balancer

In this tutorial we are going to deploy a spring boot micro service in to Amazon ECS. We will setup a Amazon ECS cluster from the scratch and deploy the application in to the cluster.

## Overview

![infrastructure-overview](images/architecture-overview.png)

## AWS fundamentals

### VPC

Virtual Private Cloud (VPC) is a way provided by AWS to isolate your infrastructure in the AWS Cloud. When you deploy your infrastructure inside the VPC it is not accessible for anyone outside the VPC. The VPC will have its own IP address range.

### Internet Gateway
Internet Gateway as the name implies allows systems within VPC to connect to Internet. 

### NAT Gateway
You can use a network address translation (NAT) gateway to enable instances in a private subnet to connect to the internet or other AWS services, but prevent the internet from initiating a connection with those instances

### Availability Zones
AWS services are available in multiple regions and each region has few availability zones. An availability zone is a physically seperate datacenter with in the region to enable disaster recovery. This is setup this way to enable customers to keep their data in their region and also to provide disaster recovery. It is important to choose a region closer to your current location for better performance.

### Subnets (Public and Private)
A VPC has one or more subnets. The subnet can be either private or public subnet.Subnet is nothing but a sub network with in the VPC with a specific IP range. Public subnet as the name implies can be accessed from internet through the internet gateway. Private subnet can't be accessed from internet and it can only be accessed by the systems placed in the public subnet. Normally the webservers are placed in the public subnet and database servers are placed in the private subnet. This way only the webserver can access the database and no other systems from the internet can access the database server.

### ALB
Application load balancer is a load balancing service provided by AWS for applications. 

### ECS Cluster
ECS cluster is a service provided by AWS to run containers in scale. It is similar to Kubernetes or Docker swarm in comparison.

The repository consists of a set of nested templates that deploy the following:

 - A tiered [VPC](http://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/VPC_Introduction.html) with public and private subnets, spanning an AWS region.
 - A highly available ECS cluster deployed across two [Availability Zones](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html) in an [Auto Scaling](https://aws.amazon.com/autoscaling/) group and that are AWS SSM enabled.
 - A pair of [NAT gateways](http://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/vpc-nat-gateway.html) (one in each zone) to handle outbound traffic.
 - One microservices deployed as [ECS services](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_services.html) (limits-service). 
 - An [Application Load Balancer (ALB)](https://aws.amazon.com/elasticloadbalancing/applicationloadbalancer/) to the public subnets to handle inbound traffic.
 - ALB path-based routes for each ECS service to route the inbound traffic to the correct service.
 - Centralized container logging with [Amazon CloudWatch Logs](http://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/WhatIsCloudWatchLogs.html).

## Why use AWS CloudFormation with Amazon ECS?

Using CloudFormation to deploy and manage services with ECS has a number of nice benefits over more traditional methods ([AWS CLI](https://aws.amazon.com/cli), scripting, etc.). 

### Understand the Microservice

This Microservice is a simple limit-service created from the previous articles. 

```
package com.in28minutes.microservices.limitsservice;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import com.in28minutes.microservices.limitsservice.bean.LimitConfiguration;

@RestController
public class LimitsConfigurationController {

	@Autowired
	private Configuration configuration;

	@GetMapping("/limits")
	public LimitConfiguration retrieveLimitsFromConfigurations() {
		LimitConfiguration limitConfiguration = new LimitConfiguration(configuration.getMaximum(), 
				configuration.getMinimum());
		return limitConfiguration;
	}

}
```
Configuration.java

```
package com.in28minutes.microservices.limitsservice;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties("limits-service")
public class Configuration {
	
	private int minimum;
	private int maximum;

	public void setMinimum(int minimum) {
		this.minimum = minimum;
	}

	public void setMaximum(int maximum) {
		this.maximum = maximum;
	}

	public int getMinimum() {
		return minimum;
	}

	public int getMaximum() {
		return maximum;
	}

}
```
application.properties

```
spring.application.name=limits-service
limits-service.minimum=10
limits-service.maximum=100
```


You can run this service locally and it will show the limits. Now to scale this microservice or to deploy this in AWS, we need to prepare the microservice by Containerizing it. To containerize a Microservice all you need to do is crate a Dockerfile.

```
FROM frolvlad/alpine-oraclejdk8:slim
VOLUME /tmp
ADD target/limits-service-0.0.1-SNAPSHOT.jar app.jar
RUN sh -c 'touch /app.jar'
ENV JAVA_OPTS=""
ENTRYPOINT [ "sh", "-c", "java -jar /app.jar" ]

```
1. Line 1: Pick up a image from the docker repository with name frolvlad/alpine-oraclejdk8:slim
2. Line 2: Create a volume called /tmp inside the image
3. Line 3: Copy the limits-service-0.0.1-SNAPSHOT.jar and rename it to app.jar
4. Line 6: Command to run this container ie. sh -c java -jar /app.jar

### Creating a buildspec file

Buildspec file is nothing but instructions to build the application by AWS code build.

```
version: 0.2
phases:
  pre_build:
    commands:
    - $(aws ecr get-login --region $AWS_DEFAULT_REGION --no-include-email)
    - TAG="$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | head -c 8)"
    - IMAGE_URI="${REPOSITORY_URI}:${TAG}"
  build:
    commands:
    - echo Build started on `date`
    - mvn clean install --debug		  [usual mvn clean build. This generates the jar file in the target directory]
    - docker build --tag "$IMAGE_URI" .  [docker build command to build the docker image using above dockerfile]
  post_build:
    commands:
    - printenv
    - echo Build completed on `date`
    - echo $(docker images)
    - echo Pushing docker image
    - docker push "$IMAGE_URI"
    - echo push completed
    - printf '{"tag":"%s"}' $TAG > build.json
    - cat service-cf.yaml > service-def.yaml
artifacts:
  files:
  - service-def.yaml
  - build.json
  
 ```

### Cloudformation template to create ECS service

The source code contains the cloud formation template to define the ECS service in the ECS cluster we already created.

```
Parameters:

  ECSCluster:
    Type: String
  VpcId:
    Type: String
  Path:
    Type: String
  ALBListener:
    Type: String
  Priority:
    Type: Number
  DesiredCount:
    Type: Number
  ContainerMemorySize:
    Type: Number
  ContainerPort:
    Type: Number

  # ECR Repo name
  ECRRepository:
    Type: String
  ECRImageTag:
    Type: String

Resources:
  ECSServiceRole:
    Type: AWS::IAM::Role
    Properties:
      Path: /
      AssumeRolePolicyDocument: |
        {
            "Statement": [{
                "Effect": "Allow",
                "Principal": { "Service": [ "ecs.amazonaws.com" ]},
                "Action": [ "sts:AssumeRole" ]
            }]
        }
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole

  TaskDefinitionServiceRole:
    Type: AWS::IAM::Role
    Properties:
      Path: /
      AssumeRolePolicyDocument: |
        {
            "Statement": [{
                "Effect": "Allow",
                "Principal": { "Service": [ "ecs-tasks.amazonaws.com" ]},
                "Action": [ "sts:AssumeRole" ]
            }]
        }
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

#### your micro service
  Service:
    Type: AWS::ECS::Service
    Properties:
      Cluster: !Ref ECSCluster
      Role: !Ref ECSServiceRole
      DesiredCount: !Ref DesiredCount
      TaskDefinition: !Ref TaskDefinition
      PlacementStrategies:
        - Type: "spread"
          Field: "attribute:ecs.availability-zone"
      LoadBalancers:
        - ContainerName: !Sub ${ECRRepository}
          ContainerPort: !Ref ContainerPort
          TargetGroupArn: !Ref TargetGroup
  TaskDefinition:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Family: !Sub ${ECRRepository}
      TaskRoleArn: !Ref TaskDefinitionServiceRole
      ContainerDefinitions:
        - Name: !Sub ${ECRRepository}
          Image: !Sub ${AWS::AccountId}.dkr.ecr.${AWS::Region}.amazonaws.com/${ECRRepository}:${ECRImageTag}
          LogConfiguration:
            LogDriver: awslogs
            Options:
              awslogs-region: !Sub ${AWS::Region}
              awslogs-group: !Ref ECSCluster
              # awslogs-stream-prefix: !Sub ${ECRImageTag}-${ECRRepository}
              awslogs-stream-prefix: !Sub ${ECRImageTag}
          Essential: true
          Memory: !Ref ContainerMemorySize
          PortMappings:
            - ContainerPort: !Ref ContainerPort
          Environment:
            - Name: AWS_Region
              Value: !Sub ${AWS::Region}

  TargetGroup:
      Type: AWS::ElasticLoadBalancingV2::TargetGroup
      Properties:
          VpcId: !Ref VpcId
          Port: 80
          Protocol: HTTP
          Matcher:
              HttpCode: 200-299
          HealthCheckIntervalSeconds: 10
          HealthCheckPath: "/actuator/health/"
          HealthCheckProtocol: HTTP
          HealthCheckTimeoutSeconds: 5
          HealthyThresholdCount: 2
  ListenerRule:
      Type: AWS::ElasticLoadBalancingV2::ListenerRule
      Properties:
          ListenerArn: !Ref ALBListener
          Priority: !Ref Priority
          Conditions:
              - Field: path-pattern
                Values:
                  - !Ref Path
          Actions:
              - TargetGroupArn: !Ref TargetGroup
                Type: forward


Outputs:
  EcsServiceName:
    Description: ECS Service Name
    Value: !GetAtt Service.Name
```

## How do I...?

### Pre-requisites

1. Account in AWS
2. Setup AWS Command Line Interface in your system to connect to your aws account through command line [AWS CLI Installation](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html)

### Get started and deploy this into my AWS account

### Customize the templates

1. [Fork](https://github.com/awstutorials/limits-service) this GitHub repository.
2. Clone the forked GitHub repository to your local machine.
3. Modify the pipeline template and import the pipeline in the cloudformation

```
  BranchName:
    Description: GitHub branch name
    Type: String
    Default: master
  RepositoryName:
    Description: GitHub repository name
    Type: String
    Default: springbootaws [change this]
  GitHubOwner:
    Type: String
    Default: awstutorial [change this]
  GitHubSecret:
    Type: String
    Default: xxxxxxx [change this]
    #NoEcho: true
  GitHubOAuthToken:
    Type: String
    Default: xxxxxxx [change this]
```
4. Run createStacks.sh to create the complete infrastructure including the pipeline [./createStacks.sh sb1-trial ec2-aws-28minutes 28minutes]
5. Access the service using the loadbalancer URL.


