###################################################################

# Infrastructure for AWS Lambda function

###################################################################

# Create KMS key to encrypt S3 bucket objects at rest.
resource "aws_kms_key" "s3_key" {
  description             = "KMS key used to encrypt bucket objects"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

# Create KMS key to encrypt DynamoDB table data at rest.
resource "aws_kms_key" "dynamodb_key" {
  description             = "KMS key used to encrypt DynamoDB table"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

# Create KMS key policy to allow access to the S3 KMS key.
resource "aws_kms_key_policy" "s3_kms_key_policy" {
  key_id = aws_kms_key.s3_key.id
  policy = jsonencode({
    Id = "Allow Access to S3 KMS Key"
    Statement = [
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Resource = "*"
      },
    ]
    Version = "2012-10-17"
  })
}

# Create KMS key policy to allow access to the DynamoDB KMS key.
resource "aws_kms_key_policy" "dynamodb_kms_key_policy" {
  key_id = aws_kms_key.dynamodb_key.id
  policy = jsonencode({
    Id = "Allow Access to DynamoDB KMS Key"
    Statement = [
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Resource = "*"
      },
    ]
    Version = "2012-10-17"
  })
}

# Create S3 bucket to store uploaded images.
#
# Configuration:
#   - block all public access
#   - versioning enabled
#   - force destroy enabled (allows ability to delete bucket with objects in it)
#   - server-side encryption enabled (encrypts bucket objects at rest)
module "upload_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "v3.10.1"

  bucket_prefix = "uploaded-images-"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = true
  }

  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = aws_kms_key.s3_key.key_id
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

# Create S3 bucket to store resized images.
#
# Configuration:
#   - block all public access
#   - versioning enabled
#   - force destroy enabled (allows ability to delete bucket with objects in it)
#   - server-side encryption enabled (encrypts bucket objects at rest)
module "resize_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "v3.10.1"

  bucket_prefix = "resized-images-"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = true
  }

  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = aws_kms_key.s3_key.key_id
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

# Generate a random ID to append to the DynamoDB table name.
resource "random_id" "table_name" {
  byte_length = 4
}

# Create a DynamoDB table to store image metadata in.
# Server-side encryption is enabled to encrypt data at rest.
resource "aws_dynamodb_table" "image_metadata" {
  name         = "image-metadata-${random_id.table_name.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sourceBucketName"

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "sourceBucketName"
    type = "S"
  }

  attribute {
    name = "sourceImageName"
    type = "S"
  }

  attribute {
    name = "targetBucketName"
    type = "S"
  }

  attribute {
    name = "resizedImageName"
    type = "S"
  }

  global_secondary_index {
    name            = "sourceBucketNameIndex"
    hash_key        = "sourceBucketName"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "targetBucketNameIndex"
    hash_key        = "targetBucketName"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "sourceImageNameIndex"
    hash_key        = "sourceImageName"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "resizedImageNameIndex"
    hash_key        = "resizedImageName"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb_key.arn
  }
}

# Create Lambda function.
# Attach the Lambda role and specify the container image to use.
resource "aws_lambda_function" "image_resizer" {
  function_name = "imageResizer"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "311065888708.dkr.ecr.us-east-1.amazonaws.com/image-resize-lambda:v0.0.1"
  timeout       = 300

  environment {
    variables = {
      IMAGE_BUCKET   = module.upload_s3_bucket.s3_bucket_id
      RESIZED_BUCKET = module.resize_s3_bucket.s3_bucket_id
      TABLE_NAME     = aws_dynamodb_table.image_metadata.name
    }
  }
}

# Create IAM role to attach to the Lambda function.
resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWSLambdaBasicExecutionRole policy to Lambda role.
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# Attach AmazonS3FullAccess policy to Lambda role.
resource "aws_iam_role_policy_attachment" "s3_access_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.lambda_role.name
}

# Attach AWSKeyManagementServicePowerUser policy to Lambda role.
resource "aws_iam_role_policy_attachment" "kms_access" {
  policy_arn = "arn:aws:iam::aws:policy/AWSKeyManagementServicePowerUser"
  role       = aws_iam_role.lambda_role.name
}

# Attach AmazonDynamoDBFullAccess policy to Lambda role.
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  role       = aws_iam_role.lambda_role.name
}

# Create Lambda permission to allow S3 to invoke the function.
resource "aws_lambda_permission" "s3_permission" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_resizer.function_name
  principal     = "s3.amazonaws.com"

  source_arn = module.upload_s3_bucket.s3_bucket_arn

  depends_on = [
    module.upload_s3_bucket,
    module.resize_s3_bucket,
    aws_lambda_function.image_resizer,
  ]
}

# Create S3 bucket notification to configure the upload S3 bucket
# to send an event payload to the Lambda function when an Object is created/updated in the bucket.
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = module.upload_s3_bucket.s3_bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_resizer.arn
    events = [
      "s3:ObjectCreated:Put"
    ]
  }
}

###################################################################

# Infrastructure for API Gateway REST API

###################################################################

# Create the REST API.
resource "aws_api_gateway_rest_api" "image_resizer" {
  name        = "imageResizer"
  description = "Image Resize API"

  binary_media_types = [
    "image/jpeg"
  ]
}

# Create the 'images' endpoint.
resource "aws_api_gateway_resource" "images" {
  rest_api_id = aws_api_gateway_rest_api.image_resizer.id
  parent_id   = aws_api_gateway_rest_api.image_resizer.root_resource_id
  path_part   = "images"
}

# Create a PUT method for the 'images' endpoint for uploading images.
resource "aws_api_gateway_method" "images_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.image_resizer.id
  resource_id   = aws_api_gateway_resource.images.id
  http_method   = "PUT"
  authorization = "NONE"
}

# Create an integration with S3.
resource "aws_api_gateway_integration" "s3_integration" {
  rest_api_id             = aws_api_gateway_rest_api.image_resizer.id
  resource_id             = aws_api_gateway_resource.images.id
  http_method             = aws_api_gateway_method.images_post_method.http_method
  type                    = "AWS"
  integration_http_method = "PUT"
  uri                     = "arn:aws:apigateway:us-east-1:s3:path/${module.upload_s3_bucket.s3_bucket_id}/test.jpg"
  credentials             = aws_iam_role.api_gateway_role.arn
}

# Create IAM role for API Gateway to assume to upload to S3.
resource "aws_iam_role" "api_gateway_role" {
  name = "APIGatewayS3UploadRole"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "apigateway.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

# Attach the AmazonS3FullAccess policy to the API Gateway policy.
resource "aws_iam_role_policy_attachment" "api_gateway_s3_upload_policy" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Create a 'dev' stage for the API deployment.
resource "aws_api_gateway_stage" "dev" {
  deployment_id = aws_api_gateway_deployment.dev_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.image_resizer.id
  stage_name    = "dev"
}

# Deploy the REST API.
resource "aws_api_gateway_deployment" "dev_deployment" {
  rest_api_id = aws_api_gateway_rest_api.image_resizer.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.images,
      aws_api_gateway_method.images_post_method,
      aws_api_gateway_integration.s3_integration,
    ]))
  }
}
