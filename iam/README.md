# IAM for Delegaris

- `member-account-role.yaml`: CloudFormation for the role Delegaris assumes in each account it manages. One `Manage...` switch per service; `ReadSchedules` for reading AWS Instance Scheduler and Quick Setup schedules.
- `hub-role.yaml`: CloudFormation for the role Delegaris itself runs as on EC2, with its instance profile.
- `hub-policy.json`: the permissions the service's own identity needs when it is not on EC2.
- `policies/`: the same permissions as plain IAM policy documents, for the console, Terraform or the CDK.

How to use them: https://docs.delegaris.co.uk/aws/member-account-role and https://docs.delegaris.co.uk/aws/iam-by-hand
