#!/usr/bin/env bash

AWS_REGION=$1
DEPLOY_ENVIRONMENT=$2
CAMM7_ENVIRONMENT=$3

CSV="config/${AWS_REGION}/${DEPLOY_ENVIRONMENT}/s3-${CAMM7_ENVIRONMENT}.csv"

if [ ! -f "${CSV}" ]; then
  echo "Configuration file ${CSV} not found. Exiting."
  exit 1
fi

MNEMONICS=($(tail -n +2 $CSV | awk -F, '{print $1}'))
DOMAINS=($(tail -n +2 $CSV | awk -F, '{print $2}'))
BUCKETS=($(tail -n +2 $CSV | awk -F, '{print $3}'))
TENANTIDS=($(tail -n +2 $CSV | awk -F, '{print $4}'))

echo "AWSTemplateFormatVersion: '2010-09-09'"
echo 'Description: CAMM 7 S3 Bucket Creation'
echo 'Parameters:'
echo '  KMSKeyId:'
echo '    Type: String'
echo '    Description: KMS key Id to encrypt the S3 buckets.'
echo '    Default: ""'
echo '  Environment:'
echo '    Type: String'
echo '    Description: Name of Environment the Bucket(s) will be used for.'
echo '    Default: "sandboxus"'
echo '  Role:'
echo '    Type: String'
echo '    Description: Name of the Role which has permission to the bucket.'
echo '    Default: "CAMM7NonProdUSFedidpEngineer"'
echo '  EnableBucketEncryption:'
echo '    Type: String'
echo '    Description: To Enable or disable bucket encryption using KMS key.'
echo '    Default: "Disabled"'
echo '    AllowedValues: ["Disabled", "Enabled"]'

echo 'Conditions:'
echo "  EnableNewKMSKey: !Equals [!Ref KMSKeyId, '']"
echo "  EnableEncryption: !Equals [!Ref EnableBucketEncryption, 'Enabled']"
echo 'Resources:'

for i in "${!BUCKETS[@]}"; do
  j=$((i + 1))
  echo "  KMSKeyAlias${j}:"
  echo '    Type: AWS::KMS::Alias'
  echo '    DeletionPolicy: Retain'
  echo '    UpdateReplacePolicy: Retain'
  echo '    Properties:'
  echo "      AliasName: !Sub alias/camm7-s3-\${Environment}-${BUCKETS[$i]}"
  echo "      TargetKeyId: !Ref KMSKey${j}"

  echo "  KMSKey${j}:"
  echo '    Type: AWS::KMS::Key'
  echo '    DeletionPolicy: Retain'
  echo '    UpdateReplacePolicy: Retain'
  echo '    Condition: EnableNewKMSKey'
  echo '    Properties:'
  echo "      Description: KMS Encryption Key for ${BUCKETS[$i]}"
  echo '      KeyPolicy:'
  echo "        Version: '2012-10-17'"
  echo '        Id: key-default-1'
  echo '        Statement:'
  echo '        - Sid: Enable IAM User Permissions'
  echo '          Effect: Allow'
  echo '          Principal:'
  echo '            AWS: !Sub arn:aws:iam::${AWS::AccountId}:root'
  echo '          Action: kms:*'
  echo "          Resource: '*'"
  echo '        - Sid: Allow use of the key'
  echo '          Effect: Allow'
  echo '          Principal:'
  echo '            AWS:'
  echo "            - !Sub 'arn:aws:iam::\${AWS::AccountId}:role/\${Role}'"
  echo '          Action:'
  echo '          - kms:DescribeKey'
  echo '          - kms:Encrypt'
  echo '          - kms:Decrypt'
  echo '          - kms:ReEncrypt*'
  echo '          - kms:GenerateDataKey'
  echo '          - kms:GenerateDataKeyWithoutPlaintext'
  echo "          Resource: '*'"
  echo '        - Sid: Allow attachment of persistent resources'
  echo '          Effect: Allow'
  echo '          Principal:'
  echo '            AWS:'
  echo "            - !Sub 'arn:aws:iam::\${AWS::AccountId}:role/\${Role}'"
  echo '          Action:'
  echo '          - kms:CreateGrant'
  echo '          - kms:ListGrants'
  echo '          - kms:RevokeGrant'
  echo "          Resource: '*'"
  echo '          Condition:'
  echo '            Bool:'
  echo '              "kms:GrantIsForAWSResource": true'

  echo "  Bucket${j}:"
  echo '    Type: AWS::S3::Bucket'
  echo '    DeletionPolicy: Retain'
  echo '    UpdateReplacePolicy: Retain'
  echo "    DependsOn: KMSKey${j}"
  echo '    Properties:'
  echo '      BucketName: !Sub'
  echo '        - camm7-${Environment}-${Name}-${AWS::Region}-${AWS::AccountId}'
  echo "        - Name: ${BUCKETS[$i]}"
  echo '      BucketEncryption:'
  echo '        !If'
  echo '        - EnableEncryption'
  echo '        -'
  echo '          ServerSideEncryptionConfiguration:'
  echo '            - ServerSideEncryptionByDefault:'
  echo '                SSEAlgorithm: aws:kms'
  echo "                KMSMasterKeyID: !If [EnableNewKMSKey, !Ref 'KMSKey${j}', !Ref 'KMSKeyId']"
  echo '        - !Ref "AWS::NoValue"'
  echo '      Tags:'
  echo '        - Key: "Environment"'
  echo '          Value: !Ref Environment'
  echo '        - Key: "Mnemonic"'
  echo "          Value: \"${MNEMONICS[$i]}\""
  echo '        - Key: "Domain"'
  echo "          Value: \"${DOMAINS[$i]}\""
  echo '        - Key: "TenantID"'
  echo "          Value: \"${TENANTIDS[$i]}\""

  echo "  Bucket${j}Policy:"
  echo '    Type: AWS::S3::BucketPolicy'
  echo '    DeletionPolicy: Retain'
  echo '    UpdateReplacePolicy: Retain'
  echo '    Properties:'
  echo "      Bucket: !Ref Bucket${j}"
  echo '      PolicyDocument:'
  echo '        Statement:'
  echo '          - Effect: Allow'
  echo '            Principal:'
  echo "              AWS: !Sub 'arn:aws:iam::\${AWS::AccountId}:role/\${Role}'"
  echo '            Action:'
  echo '              - s3:GetObject'
  echo '              - s3:PutObject'
  echo '              - s3:DeleteObject'
  echo "            Resource: !Sub \${Bucket${j}.Arn}/*"
done
