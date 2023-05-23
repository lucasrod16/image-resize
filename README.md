# Image resize Lambda function

This repository contains Go code in `main.go` and the `lambda/` directory that creates an AWS Lambda function that performs image resizing and processing. Here's an overview of its functionality:

1. The Lambda function is triggered by an S3 event, indicating that an image has been uploaded to an S3 bucket.

2. The function fetches the uploaded image from the source S3 bucket.

3. The fetched image is then resized.

4. The resized image is uploaded to a target S3 bucket.

5. The function writes metadata about the image processing operation, including the source bucket, source image name, target bucket, and resized image name, to a DynamoDB table.

6. Logging statements are used to indicate the successful execution of each step in the image processing pipeline.

The Lambda function utilizes environment variables to specify the source bucket, target bucket, and DynamoDB table name.

The Lambda function is packaged and deployed as a container.

This code can be deployed as an AWS Lambda function to automatically resize and process images as they are uploaded to the source S3 bucket.

## Infrastructure for AWS Lambda function

This repository contains Terraform code in the `infra/` directory to provision the infrastructure required for an AWS Lambda function that performs image resizing.

It includes the following resources:

### AWS KMS Keys

Two AWS KMS keys are created to encrypt sensitive data at rest:

1. KMS key used to encrypt S3 bucket objects.
2. KMS key used to encrypt DynamoDB table data.

### S3 Buckets

Two S3 buckets are created to store uploaded and resized images:

1. S3 bucket to store uploaded images. It has the following configurations:
   - Blocks all public access.
   - Versioning enabled.
   - Force destroy enabled (allows deleting the bucket with objects in it).
   - Server-side encryption enabled using the KMS key.

2. S3 bucket to store resized images. It has identical configurations to the other bucket.

### DynamoDB Table

A DynamoDB table is created to store image metadata:

- Billing mode: PAY_PER_REQUEST
- Global secondary indexes for efficient querying.
- Server-side encryption enabled using the KMS key.

### Lambda Function

The AWS Lambda function is created to perform image resizing. It has the following configurations:

The Lambda function assumes an IAM role with permissions to upload and download from S3, access KMS keys, write data to DynamoDB, etc.

The Lambda function is also configured to be invoked by the upload S3 bucket. The S3 bucket sends an event payload to the Lambda function when an object is created or updated.

### API Gateway REST API

The repository also provisions an API Gateway REST API for image uploading and resizing.

The API has an endpoint `/images` with a `PUT` method. The method is integrated with S3 to store uploaded images in the S3 bucket.

API Gateway assumes an IAM role with permissions to upload to S3.

A `dev` stage is created to deploy the API, and the deployment is triggered by changes to relevant resources.

## Tests

## Unit tests

There are unit tests in the `lambda/image_resize_test.go` file.

They are test cases ran in parallel against the terraform module to test the individual Go functions that make up the core business logic of the AWS Lambda function.

## End-To-End tests

There are end-to-end tests in the `infra/test/e2e_test.sh` file.

It is a comprehensive smoke test of all of the infrastructure defined in this repository.

It performs the following steps:

1. Provisions all of the cloud infrastructure.

2. Uploads the JPEG image at `testdata/test.jpg` to S3 to trigger the Lambda function.

   - The image is uploaded via a PUT request to the newly created REST API `/images` endpoint.

3. Asserts that the Lambda function executes successfully.

4. Asserts that the metadata written to DynamoDB matches what is expected.

5. Tears down all of the cloud infrastructure.
