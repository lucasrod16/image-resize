###################################################################

# Infrastructure for AWS Lambda function

###################################################################

resource "aws_kms_key" "s3_key" {
  description             = "KMS key used to encrypt bucket objects"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_key" "dynamodb_key" {
  description             = "KMS key used to encrypt DynamoDB table"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

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

resource "random_id" "table_name" {
  byte_length = 4
}

resource "aws_dynamodb_table" "image_metadata" {
  name = "image-metadata-${random_id.table_name.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "sourceBucketName"

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
    name               = "sourceBucketNameIndex"
    hash_key           = "sourceBucketName"
    projection_type    = "ALL"
  }

  global_secondary_index {
    name               = "targetBucketNameIndex"
    hash_key           = "targetBucketName"
    projection_type    = "ALL"
  }

  global_secondary_index {
    name               = "sourceImageNameIndex"
    hash_key           = "sourceImageName"
    projection_type    = "ALL"
  }

  global_secondary_index {
    name               = "resizedImageNameIndex"
    hash_key           = "resizedImageName"
    projection_type    = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb_key.arn
  }
}

resource "aws_lambda_function" "image_resizer" {
  function_name = "imageResizer"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "311065888708.dkr.ecr.us-east-1.amazonaws.com/image-resize-lambda:v0.0.1"
  timeout = 300

  environment {
    variables = {
      IMAGE_BUCKET   = module.upload_s3_bucket.s3_bucket_id
      RESIZED_BUCKET = module.resize_s3_bucket.s3_bucket_id
      TABLE_NAME     = aws_dynamodb_table.image_metadata.name
    }
  }
}

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

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "s3_access_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "kms_access" {
  policy_arn = "arn:aws:iam::aws:policy/AWSKeyManagementServicePowerUser"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  role       = aws_iam_role.lambda_role.name
}

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

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = module.upload_s3_bucket.s3_bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_resizer.arn
    events = [
      "s3:ObjectCreated:Put"
    ]
  }
}
