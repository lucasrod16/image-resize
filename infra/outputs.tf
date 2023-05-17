output "upload_s3_bucket_name" {
  value = module.upload_s3_bucket.s3_bucket_id
}

output "resize_s3_bucket_name" {
  value = module.resize_s3_bucket.s3_bucket_id
}

output "lambda_function_name" {
  value = aws_lambda_function.image_resizer.function_name
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.image_metadata.name
}
