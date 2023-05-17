package lambda

import (
	"os"
	"testing"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

func TestFetchImageFromBucket(t *testing.T) {
	t.Parallel()

	// Make a copy of the terraform module to a temporary directory.
	// This allows running multiple tests in parallel against the same terraform module.
	testFolder := test_structure.CopyTerraformFolderToTemp(t, "..", "infra")
	defer os.RemoveAll(testFolder)

	terraformOptions := &terraform.Options{
		TerraformDir: testFolder,

		// We only need the upload S3 bucket and the S3 KMS key
		Targets: []string{"aws_kms_key.s3_key", "module.upload_s3_bucket"},
	}

	terraform.InitAndApply(t, terraformOptions)
	defer terraform.Destroy(t, terraformOptions)

	s3BucketID := terraform.Output(t, terraformOptions, "upload_s3_bucket_name")
	image := "test.jpg"
	s3Client := SetupS3Client()

	_, err := s3Client.PutObject(&s3.PutObjectInput{
		Bucket: aws.String(s3BucketID),
		Key:    aws.String(image),
	})
	if err != nil {
		t.Error(err)
	}

	if _, err := FetchImageFromBucket(s3BucketID, image); err != nil {
		t.Error(err)
	}
}

func TestResizeImage(t *testing.T) {
	t.Parallel()

	imageFile := "../testdata/test.jpg"

	imageData, err := os.ReadFile(imageFile)
	if err != nil {
		t.Error(err)
	}

	if _, err = ResizeImage(imageData); err != nil {
		t.Error(err)
	}
}

func TestUploadResizedImageToBucket(t *testing.T) {
	t.Parallel()

	// Make a copy of the terraform module to a temporary directory.
	// This allows running multiple tests in parallel against the same terraform module.
	testFolder := test_structure.CopyTerraformFolderToTemp(t, "..", "infra")
	defer os.RemoveAll(testFolder)

	terraformOptions := &terraform.Options{
		TerraformDir: testFolder,

		// We only need the resize image S3 bucket and the S3 KMS key
		Targets: []string{"aws_kms_key.s3_key", "module.resize_s3_bucket"},

		// VarFiles: []string{"example.tfvars"},
	}

	terraform.InitAndApply(t, terraformOptions)
	defer terraform.Destroy(t, terraformOptions)

	s3BucketID := terraform.Output(t, terraformOptions, "resize_s3_bucket_name")
	image := "test.jpg"

	if _, err := UploadResizedImageToBucket(s3BucketID, image, []byte{}); err != nil {
		t.Error(err)
	}
}

func TestWriteMetadataToDynamoDBTable(t *testing.T) {
	t.Parallel()

	// Make a copy of the terraform module to a temporary directory.
	// This allows running multiple tests in parallel against the same terraform module.
	testFolder := test_structure.CopyTerraformFolderToTemp(t, "..", "infra")
	defer os.RemoveAll(testFolder)

	terraformOptions := &terraform.Options{
		TerraformDir: testFolder,

		// We only need the DynamoDB table and the DynamoDB KMS key
		Targets: []string{"aws_kms_key.dynamodb_key", "aws_dynamodb_table.image_metadata"},

		// VarFiles: []string{"example.tfvars"},
	}

	terraform.InitAndApply(t, terraformOptions)
	defer terraform.Destroy(t, terraformOptions)

	dynamoDBTableName := terraform.Output(t, terraformOptions, "dynamodb_table_name")

	var (
		sourceBucket = "sourceBucket"
		sourceImage  = "sourceImage.jpg"
		targetBucket = "targetBucket"
		resizedImage = "resizedImage.jpg"
	)

	err := WriteMetadataToDynamoDBTable(dynamoDBTableName, sourceBucket, sourceImage, targetBucket, resizedImage)
	if err != nil {
		t.Fatal(err)
	}
}
