import os
import json
import boto3
import datetime

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

INSTANCE_ID = os.environ["INSTANCE_ID"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

def handler(event, context):
    now = datetime.datetime.utcnow().isoformat() + "Z"

    ec2.reboot_instances(InstanceIds=[INSTANCE_ID])

    payload = {
        "time": now,
        "action": "reboot_instances",
        "instance_id": INSTANCE_ID,
        "reason": "sumo_alert",
        "request_id": getattr(context, "aws_request_id", ""),
    }

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="EC2 reboot triggered by alert",
        Message=json.dumps(payload, indent=2),
    )

    return {
        "statusCode": 200,
        "body": json.dumps({"ok": True, "details": payload})
    }
