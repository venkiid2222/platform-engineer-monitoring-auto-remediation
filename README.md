Platform Engineer Coding Test – Monitoring & Auto-Remediation
Overview

This project demonstrates a simple monitoring and self-healing setup for a web application.
When application performance degrades, the system automatically detects the issue, takes corrective action, and notifies the team.

The goal is to show how logs → alerts → automation → notification can work together using cloud-native services.

Problem Scenario

The application occasionally experiences slow responses on the /api/data endpoint.
If too many slow responses happen within a short time window, manual intervention is not fast enough.

This solution automatically:

Detects the issue

Restarts the affected compute instance

Sends a notification so the team is aware

How the Solution Works (End-to-End)

Sumo Logic continuously scans application logs

Looks for /api/data requests taking more than 3 seconds

Triggers when more than 5 such logs occur in 10 minutes

Webhook Trigger

The Sumo alert calls a public webhook endpoint

API Gateway (HTTP API)

Acts as the public entry point for the webhook

Forwards the request to AWS Lambda

AWS Lambda (Python)

Receives the alert

Reboots the target EC2 instance

Publishes a message to an SNS topic

Amazon SNS

Sends an email notification confirming the action taken

Amazon EC2

Instance is restarted automatically to recover performance

Why API Gateway Is Used Instead of Lambda Function URL

This AWS account blocks public Lambda Function URLs at the account level, which causes 403 Forbidden errors even when authorization is set to NONE.

To handle this correctly, API Gateway HTTP API is used as the public webhook endpoint.
This is a recommended production-ready pattern and works reliably across restricted AWS accounts.

Repository Structure
.
├── lambda_function/
│   └── lambda_function.py     # Lambda logic (restart EC2 + send SNS)
│
├── terraform/
│   ├── main.tf                # All infrastructure (EC2, Lambda, SNS, API Gateway)
│   ├── variables.tf
│   └── outputs.tf
│
├── sumo_logic_query.txt       # Sumo Logic query for slow API detection
└── README.md

Deployment Steps

From the terraform/ directory:

terraform init
terraform apply -auto-approve


Terraform creates:

EC2 instance

Lambda function

SNS topic

API Gateway HTTP API

IAM roles and permissions

Terraform Outputs

After deployment, Terraform prints:

api_gateway_url → Use this as the Sumo webhook URL

ec2_instance_id → Target instance being restarted

sns_topic_arn → Notification topic

Manual Test (Local)
$url = terraform output -raw api_gateway_url
curl.exe -i -X POST "$url" -H "Content-Type: application/json" -d "{\"source\":\"manual-test\"}"


Expected result:

HTTP 200 OK

EC2 instance reboot initiated

SNS email notification received

Verification

CloudWatch Logs → Lambda execution logs visible

EC2 Console → Instance reboot event visible

Email Inbox → SNS notification received

Key Takeaways

Shows log-based alerting

Demonstrates automated remediation

Uses Infrastructure as Code

Handles real-world AWS account restrictions correctly

Designed to be simple, readable, and reliable