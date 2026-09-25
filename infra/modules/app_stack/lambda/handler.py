import json
import os

import boto3
from botocore.exceptions import ClientError


def handler(event, context):
    configured = False
    try:
        boto3.client("secretsmanager").get_secret_value(
            SecretId=os.environ["SECRET_ARN"]
        )
        configured = True
    except ClientError as error:
        if error.response["Error"]["Code"] != "ResourceNotFoundException":
            raise

    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({
            "message": "Hello from Lambda",
            "environment": os.environ["ENVIRONMENT"],
            "secret_configured": configured,
        }),
    }
