#!/bin/bash

function delete_log_streams() {
    log_group_name="/aws/lambda/$1"

    # Get all log streams in the log group
    log_streams=$(aws logs describe-log-streams \
        --log-group-name "$log_group_name" \
        --query 'logStreams[*].logStreamName' \
        --output text)

    # Loop through each log stream and delete it
    for log_stream in $log_streams
    do
        echo "Deleting log stream: $log_stream"

        aws logs delete-log-stream \
            --log-group-name "$log_group_name" \
            --log-stream-name "$log_stream"
    done
}

function e2e_test() {
    cd infra || exit

    test_image="../testdata/test.jpg"

    terraform init

    terraform apply --auto-approve

    upload_s3_bucket="$(terraform output -raw upload_s3_bucket_name)"
    # resize_s3_bucket="$(terraform output -raw resize_s3_bucket_name)"
    lambda_function="$(terraform output -raw lambda_function_name)"
    # dynamodb_table="$(terraform output -raw dynamodb_table_name)"

    # Delete old log streams
    delete_log_streams "$lambda_function"

    # Upload image to S3 bucket to trigger the lambda function
    aws s3 cp "$test_image" s3://"$upload_s3_bucket"

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
    if [[ "$log_message" =~ "error" ]]
    then
        terraform destroy --auto-approve
        echo -e "Lambda function returned an error\n"
        echo "$log_message"
        exit 1
    fi

    terraform destroy --auto-approve

    echo "$log_message"
}

e2e_test
