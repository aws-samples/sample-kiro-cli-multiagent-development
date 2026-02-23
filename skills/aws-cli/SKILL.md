---
name: aws-cli
description: AWS CLI best practices including pagination control, output formatting, and efficient querying. Use when running AWS CLI commands, querying AWS resources, or automating AWS operations.
---

# AWS CLI

## Pagination Control

Always use `--no-cli-pager` for complete results in a single response:

```bash
# Good: Complete results
aws ec2 describe-instances --no-cli-pager
aws s3api list-objects-v2 --bucket my-bucket --no-cli-pager
aws iam list-users --no-cli-pager

# Bad: May truncate or require interaction
aws ec2 describe-instances
```

Only use default pagination when:
- User explicitly requests paginated output
- Working with extremely large datasets
- User asks for "first N results"

## Query and Filtering

Combine `--no-cli-pager` with `--query` for efficient data retrieval:

```bash
# Running instances only
aws ec2 describe-instances --no-cli-pager \
  --query 'Reservations[].Instances[?State.Name==`running`].[InstanceId,InstanceType]'

# Large S3 objects
aws s3api list-objects-v2 --bucket my-bucket --no-cli-pager \
  --query 'Contents[?Size>`1000000`].[Key,Size]'

# Specific fields as table
aws ec2 describe-instances --no-cli-pager \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType]' \
  --output table
```

## Output Formats

```bash
--output json   # Default, full detail
--output table  # Human-readable
--output text   # Tab-separated, good for scripting
--output yaml   # YAML format
```

## Common Patterns

```bash
# Get account ID
aws sts get-caller-identity --query 'Account' --output text --no-cli-pager

# List all regions
aws ec2 describe-regions --query 'Regions[].RegionName' --output text --no-cli-pager

# Wait for resource
aws ec2 wait instance-running --instance-ids i-1234567890abcdef0

# Dry run (check permissions)
aws ec2 run-instances --dry-run --image-id ami-12345 --instance-type t3.micro
```
