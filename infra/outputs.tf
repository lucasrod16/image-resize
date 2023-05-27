# Output the upload S3 bucket name.
output "upload_s3_bucket_name" {
  value = module.upload_s3_bucket.s3_bucket_id
}

# Output the resize S3 bucket name.
output "resize_s3_bucket_name" {
  value = module.resize_s3_bucket.s3_bucket_id
}

# Output the Lambda function name.
output "lambda_function_name" {
  value = aws_lambda_function.image_resizer.function_name
}

# Output the DynamoDB table name.
output "dynamodb_table_name" {
  value = aws_dynamodb_table.image_metadata.name
}

# Output the URL used to upload the image via the '/images' API endpoint.
output "invoke_url" {
  value = "${aws_api_gateway_deployment.dev_deployment.invoke_url}${aws_api_gateway_stage.dev.stage_name}/images"
}
