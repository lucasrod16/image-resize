#!/bin/bash

GREEN="\033[0;32m"
RED="\033[0;31m"

function delete_log_streams() {
    log_group_name="/aws/lambda/$1"

    # Get all log streams in the log group
    log_streams="$(aws logs describe-log-streams \
        --log-group-name "$log_group_name" \
        --query 'logStreams[*].logStreamName' \
        --output text)"

    # Loop through each log stream and delete it
    for log_stream in $log_streams
    do
        echo -e "Deleting log stream: $log_stream\n"

        aws logs delete-log-stream \
            --log-group-name "$log_group_name" \
            --log-stream-name "$log_stream"
    done
}

function destroy() {
    terraform destroy --auto-approve
}

function e2e_test() {
    cd infra || exit

    # Ensure 'terraform destroy' is always executed
    trap destroy EXIT SIGINT SIGTERM

    test_image="../testdata/test.jpg"

    terraform init --upgrade

    terraform apply --auto-approve

    # Check if we got any errors
    if [ $? -ne 0 ]
    then
        echo -e "${RED}Error: 'terraform apply' exited with an error\n${RED}"
        exit 1
    fi

    # Get terraform outputs
    upload_s3_bucket="$(terraform output -raw upload_s3_bucket_name)"
    resize_s3_bucket="$(terraform output -raw resize_s3_bucket_name)"
    lambda_function="$(terraform output -raw lambda_function_name)"
    dynamodb_table="$(terraform output -raw dynamodb_table_name)"
    invoke_url="$(terraform output -raw invoke_url)"

    # Delete old log streams
    delete_log_streams "$lambda_function"

    # Upload image to S3 bucket to trigger the lambda function.
    # Using the REST API '/images' endpoint to upload the image.
    response="$(curl -s -X PUT -H "Content-Type: image/jpeg" --data-binary "@$test_image" "$invoke_url")"

    echo -e "API response: $response\n"

    # Wait for log stream to be created
    log_stream="[]"
    while [[ "$log_stream" == "[]" ]]
    do
        echo "Waiting for log stream to be created..."

        log_stream="$(aws logs describe-log-streams \
            --log-group-name /aws/lambda/"$lambda_function" \
            --order-by LastEventTime \
            --descending \
            --max-items 1 \
            | jq -r '.logStreams')"

        sleep 1
    done


    log_stream_name="$(echo "$log_stream" | jq -r '.[].logStreamName')"

    # Wait for lambda function to finish executing
    log_message=""
    while [[ ! "$log_message" =~ "REPORT" ]]
    do
        echo "Waiting for lambda function to finish executing..."

        log_message="$(aws logs get-log-events \
            --log-group-name /aws/lambda/"$lambda_function" \
            --log-stream-name "$log_stream_name" \
            --limit 10 \
            | jq -r '.events[].message')"

        sleep 1
    done

    # Check if log message contains any errors
    if [[ "$log_message" =~ "Error" || "$log_message" =~ "errorMessage" ]]
    then
        echo -e "${RED}Lambda function returned an error\n"
        echo "$log_message${RED}"
        exit 1
    fi

    image_metadata_payload="$(aws dynamodb scan --table-name "$dynamodb_table")"

    # Check if we got any errors
    if [ $? -ne 0 ]
    then
        echo -e "${RED}Error: Failed to fetch data from the '$dynamodb_table' DynamoDB table\n"
        echo -e "Ensure the requested DynamoDB table name is valid\n${RED}"
        exit 1
    fi

    # Assert upload S3 bucket name
    actual_upload_bucket_name="$(echo "$image_metadata_payload" | jq -r '.Items[].sourceBucketName.S')"
    if [ "$actual_upload_bucket_name" != "$upload_s3_bucket" ]
    then
        echo -e "${RED}Error: The upload S3 bucket name does not match metadata in DynamoDB\n"
        echo -e "expected: '$upload_s3_bucket', got: '$actual_upload_bucket_name'\n${RED}"
        exit 1
    fi

    # Assert upload image name
    expected_upload_image_name="test.jpg"
    actual_upload_image_name="$(echo "$image_metadata_payload" | jq -r '.Items[].sourceImageName.S')"
    if [ "$actual_upload_image_name" != "$expected_upload_image_name" ]
    then
        echo -e "${RED}Error: The upload image name does not match metadata in DynamoDB\n"
        echo -e "expected: '$expected_upload_image_name', got: '$actual_upload_image_name'\n${RED}"
        exit 1
    fi

    # Assert resize S3 bucket name
    actual_resize_bucket_name="$(echo "$image_metadata_payload" | jq -r '.Items[].targetBucketName.S')"
    if [ "$actual_resize_bucket_name" != "$resize_s3_bucket" ]
    then
        echo -e "${RED}Error: The resize S3 bucket name does not match metadata in DynamoDB\n"
        echo -e "expected: '$resize_s3_bucket', got: '$actual_resize_bucket_name'\n${RED}"
        exit 1
    fi

    # Assert resized image name
    expected_resized_image_name="resized-test.jpg"
    actual_resized_image_name="$(echo "$image_metadata_payload" | jq -r '.Items[].resizedImageName.S')"
    if [ "$actual_resized_image_name" != "$expected_resized_image_name" ]
    then
        echo -e "${RED}Error: The resized image name does not match metadata in DynamoDB\n"
        echo -e "expected: '$expected_resized_image_name', got: '$actual_resized_image_name'\n${RED}"
        exit 1
    fi

    echo -e "${GREEN}Lambda function executed succesfully\n\n$log_message\n${GREEN}"
}

e2e_test
