package main

import (
	"log"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	resize "github.com/lucasrod16/image-resize/lambda"
)

func main() {
	lambda.Start(imageResizer)
}

func imageResizer(s3Event events.S3Event) error {
	var (
		sourceBucket      = os.Getenv("IMAGE_BUCKET")
		targetBucket      = os.Getenv("RESIZED_BUCKET")
		dynamodbTableName = os.Getenv("TABLE_NAME")
		image             string
	)

	// Get the name of the image that was uploaded to S3 to trigger this Lambda function
	for _, record := range s3Event.Records {
		image = record.S3.Object.Key
	}

	// Fetch the uploaded image from the S3 bucket
	imageData, err := resize.FetchImageFromBucket(sourceBucket, image)
	if err != nil {
		return err
	}
	log.Printf("'%s' was successfully fetched from the '%s' bucket", image, sourceBucket)

	// Resize the image
	resizedImageBytes, err := resize.ResizeImage(imageData)
	if err != nil {
		return err
	}
	log.Printf("Successfully resized image '%s'", image)

	// Upload the resized image to the target bucket
	resizedImage, err := resize.UploadResizedImageToBucket(targetBucket, image, resizedImageBytes)
	if err != nil {
		return err
	}
	log.Printf("'%s' was successfully uploaded to the '%s' bucket", resizedImage, targetBucket)

	// Write image and S3 metadata to DynamoDB table
	err = resize.WriteMetadataToDynamoDBTable(dynamodbTableName, sourceBucket, image, targetBucket, resizedImage)
	if err != nil {
		return err
	}
	log.Printf("Successfully wrote metadata to the '%s' DynamoDB table", dynamodbTableName)

	return nil
}
