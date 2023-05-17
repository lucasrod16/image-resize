package infra

import (
	"bytes"
	"encoding/json"
	"os"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/lambda"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/gruntwork-io/terratest/modules/terraform"
	myLambda "github.com/lucasrod16/image-resize/lambda"
)

func TestLambdaFunctionEndToEnd(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir: "..",
	}

	terraform.InitAndApply(t, terraformOptions)
	defer terraform.Destroy(t, terraformOptions)

	lambdaFunctionName := terraform.Output(t, terraformOptions, "lambda_function_name")
	uploadS3Bucket := terraform.Output(t, terraformOptions, "upload_s3_bucket_name")

	image := "test.jpg"
	testImage := "../../testdata/test.jpg"

	imageData, err := os.ReadFile(testImage)
	if err != nil {
		t.Fatal(err)
	}

	s3Client := myLambda.SetupS3Client()

	// Upload test image to S3 bucket so that we have a real image to resize
	s3Client.PutObject(&s3.PutObjectInput{
		Bucket: aws.String(uploadS3Bucket),
		Key:    aws.String(image),
		Body:   bytes.NewReader(imageData),
	})

	// Construct the S3 PUT event payload
	s3Event := &events.S3Event{
		Records: []events.S3EventRecord{
			{
				EventSource: "aws:s3",
				EventName:   "ObjectCreated:Put",
				S3: events.S3Entity{
					Bucket: events.S3Bucket{
						Name: uploadS3Bucket,
					},
					Object: events.S3Object{
						Key: image,
					},
				},
			},
		},
	}

	// Convert the struct to JSON
	jsonPayload, err := json.Marshal(s3Event)
	if err != nil {
		t.Fatalf("Error marshaling JSON: %v", err)
	}

	session := session.Must(session.NewSession(&aws.Config{
		Region: aws.String("us-east-1"),
	}))

	// Create a new Lambda service client
	lambdaClient := lambda.New(session)

	// Invoke the Lambda function
	invocationResult, err := lambdaClient.Invoke(&lambda.InvokeInput{
		FunctionName: aws.String(lambdaFunctionName),
		Payload:      jsonPayload,
	})
	if err != nil {
		t.Fatal(err)
	}

	// Ensure that the lambda function didn't return any errors
	if invocationResult.FunctionError != nil {
		t.Fatalf("Lambda function returned an error: %v", *invocationResult.FunctionError)
	}
}
