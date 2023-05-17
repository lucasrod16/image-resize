package lambda

import (
	"bytes"
	"fmt"
	"image/jpeg"
	"io"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/disintegration/imaging"
)

func FetchImageFromBucket(sourceBucket string, image string) (imageData []byte, err error) {
	s3Client := SetupS3Client()

	// Download the image from the source bucket
	response, err := s3Client.GetObject(&s3.GetObjectInput{
		Bucket: aws.String(sourceBucket),
		Key:    aws.String(image),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to fetch image data from the '%s' bucket: %s,", sourceBucket, err.Error())
	}
	defer response.Body.Close()

	imageBytes, err := io.ReadAll(response.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read image data from response body: %s", err.Error())
	}

	return imageBytes, nil
}

func ResizeImage(imageData []byte) (resizedImageBytes []byte, err error) {
	inputImage, err := jpeg.Decode(bytes.NewReader(imageData))
	if err != nil {
		return nil, fmt.Errorf("failed to decode input image: %s", err.Error())
	}

	// Resize the input image to 800x600 pixels using Lanczos filter
	resizedImage := imaging.Resize(inputImage, 800, 600, imaging.Lanczos)

	// Encode the output image to JPEG format
	var resizedImageData bytes.Buffer
	err = jpeg.Encode(&resizedImageData, resizedImage, &jpeg.Options{Quality: 90})
	if err != nil {
		return nil, fmt.Errorf("failed to encode resized image: %s", err.Error())
	}

	// Get the resized image data as a byte slice
	resizedImageBytes = resizedImageData.Bytes()

	return resizedImageBytes, nil
}

func UploadResizedImageToBucket(targetBucket string, image string, resizedImageBytes []byte) (resizedImage string, err error) {
	s3Client := SetupS3Client()

	resizedImage = "resized-" + image

	// Upload resized image target bucket
	_, err = s3Client.PutObject(&s3.PutObjectInput{
		Bucket: aws.String(targetBucket),
		Key:    aws.String(resizedImage),
		Body:   bytes.NewReader(resizedImageBytes),
	})
	if err != nil {
		return "", fmt.Errorf("failed to upload resized image '%s' to the '%s' bucket: %s", resizedImage, targetBucket, err.Error())
	}

	return resizedImage, nil
}

func WriteMetadataToDynamoDBTable(tableName string, sourceBucket string, sourceImage string, targetBucket string, resizedImage string) (err error) {
	dynamoDBClient := SetupDynamoDBClient()

	tableAttributes := map[string]*dynamodb.AttributeValue{
		"sourceBucketName": {
			S: aws.String(sourceBucket),
		},
		"sourceImageName": {
			S: aws.String(sourceImage),
		},
		"targetBucketName": {
			S: aws.String(targetBucket),
		},
		"resizedImageName": {
			S: aws.String(resizedImage),
		},
	}

	_, err = dynamoDBClient.PutItem(&dynamodb.PutItemInput{
		TableName: aws.String(tableName),
		Item:      tableAttributes,
	})
	if err != nil {
		return fmt.Errorf("failed to write data to DynamoDB table: %v", err)
	}

	return nil
}

func SetupS3Client() *s3.S3 {
	session := session.Must(session.NewSession(&aws.Config{
		Region: aws.String("us-east-1"),
	}))

	// Create a S3 client
	s3Client := s3.New(session)

	return s3Client
}

func SetupDynamoDBClient() *dynamodb.DynamoDB {
	session := session.Must(session.NewSession(&aws.Config{
		Region: aws.String("us-east-1"),
	}))

	// Create a DynamoDB client
	dynamodbClient := dynamodb.New(session)

	return dynamodbClient
}
