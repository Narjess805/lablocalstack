AWSTemplateFormatVersion: "2010-09-09"

Description: >
  Le Café complete infrastructure stack.
  Defines IAM roles, S3 buckets, SQS queues, and SNS topics
  for the Le Café ordering and notification platform.

Parameters:
  EnvironmentName:
    Type: String
    Default: development
    AllowedValues:
      - development
      - staging
      - production
    Description: The environment this stack is being deployed into.

  LogRetentionDays:
    Type: Number
    Default: 30
    MinValue: 1
    MaxValue: 365
    Description: Number of days before log objects are automatically expired.

  OrderQueueVisibilityTimeout:
    Type: Number
    Default: 30
    Description: Seconds a received message is hidden from other consumers.

Resources:
  # IAM Role for the application
  LeCafeAppRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "lecafe-app-role-${EnvironmentName}"
      Description: Assumed by EC2 instances running the Le Cafe ordering app
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: LeCafeAppPermissions
          PolicyDocument:
            Version: "2012-10-17"
            Statement:
              - Sid: AllowS3AssetRead
                Effect: Allow
                Action:
                  - s3:GetObject
                  - s3:ListBucket
                Resource:
                  - !Sub "arn:aws:s3:::lecafe-assets-${EnvironmentName}"
                  - !Sub "arn:aws:s3:::lecafe-assets-${EnvironmentName}/*"
              - Sid: AllowSQSOrderWrite
                Effect: Allow
                Action:
                  - sqs:SendMessage
                  - sqs:GetQueueUrl
                  - sqs:GetQueueAttributes
                Resource: !GetAtt LeCafeKitchenOrders.Arn

  LeCafeAppInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      InstanceProfileName: !Sub "lecafe-app-profile-${EnvironmentName}"
      Roles:
        - !Ref LeCafeAppRole

  # S3 Buckets
  LeCafeAssetsBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub "lecafe-assets-${EnvironmentName}"
      VersioningConfiguration:
        Status: Enabled

  LeCafeLogsBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub "lecafe-logs-${EnvironmentName}"
      LifecycleConfiguration:
        Rules:
          - Id: DeleteOldLogs
            Status: Enabled
            Prefix: ""
            ExpirationInDays: !Ref LogRetentionDays

  # SQS Queues
  LeCafeKitchenOrdersDLQ:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: !Sub "lecafe-kitchen-orders-dlq-${EnvironmentName}"
      MessageRetentionPeriod: 1209600

  LeCafeKitchenOrders:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: !Sub "lecafe-kitchen-orders-${EnvironmentName}"
      VisibilityTimeout: !Ref OrderQueueVisibilityTimeout
      MessageRetentionPeriod: 86400
      ReceiveMessageWaitTimeSeconds: 20
      RedrivePolicy:
        deadLetterTargetArn: !GetAtt LeCafeKitchenOrdersDLQ.Arn
        maxReceiveCount: 3

  LeCafeInventoryUpdates:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: !Sub "lecafe-inventory-updates-${EnvironmentName}"

  LeCafeLoyaltyPoints:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: !Sub "lecafe-loyalty-points-${EnvironmentName}"

  LeCafeManagerAlerts:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: !Sub "lecafe-manager-alerts-${EnvironmentName}"

  # SNS Topic
  LeCafeOrdersTopic:
    Type: AWS::SNS::Topic
    Properties:
      TopicName: !Sub "lecafe-orders-topic-${EnvironmentName}"

  # SNS Subscriptions
  InventorySubscription:
    Type: AWS::SNS::Subscription
    Properties:
      TopicArn: !Ref LeCafeOrdersTopic
      Protocol: sqs
      Endpoint: !GetAtt LeCafeInventoryUpdates.Arn

  LoyaltySubscription:
    Type: AWS::SNS::Subscription
    Properties:
      TopicArn: !Ref LeCafeOrdersTopic
      Protocol: sqs
      Endpoint: !GetAtt LeCafeLoyaltyPoints.Arn

  ManagerAlertSubscription:
    Type: AWS::SNS::Subscription
    Properties:
      TopicArn: !Ref LeCafeOrdersTopic
      Protocol: sqs
      Endpoint: !GetAtt LeCafeManagerAlerts.Arn
      FilterPolicy: '{"Priority": ["high"]}'

Outputs:
  AssetsBucketName:
    Description: Name of the S3 bucket storing application assets
    Value: !Ref LeCafeAssetsBucket

  KitchenQueueUrl:
    Description: URL of the kitchen orders SQS queue
    Value: !Ref LeCafeKitchenOrders

  OrdersTopicArn:
    Description: ARN of the central SNS orders topic
    Value: !Ref LeCafeOrdersTopic

  AppRoleArn:
    Description: ARN of the IAM role for EC2 instances
    Value: !GetAtt LeCafeAppRole.Arn