---
inclusion: always
---

# Post-Deploy Validation

## Principle

Every deploy script MUST include a post-deploy smoke test. Never rely on users to discover runtime errors.

## Rules

Every deploy script MUST include a post-deploy smoke test appropriate to the deployment target.

| Deployment Target | Smoke Test |
|-------------------|------------|
| Container/Runtime service | Wait 60s, check CloudWatch logs for `ERROR`/`Traceback` |
| Frontend (S3 + CloudFront) | Verify CloudFront URL returns HTTP 200 after invalidation |
| Lambda function | Invoke with test payload, or verify function state is `Active` |
| API Gateway | Hit health check endpoint, verify 200 response |
| ECS/Fargate service | Verify task count matches desired, check ALB health |

Deploy script MUST exit non-zero if any smoke test fails. A "successful deploy" that crashes at runtime is not successful.

## Implementation Pattern

```bash
# Post-deploy health check — generic CloudWatch log check
log "Running post-deploy health check..."
sleep 60
ERRORS=$(aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --start-time "$(python3 -c "import time; print(int((time.time()-120)*1000))")" \
  --filter-pattern "?ERROR ?Traceback" \
  --limit 5 --region "$REGION" \
  --query 'events[].message' --output text 2>/dev/null)
if [ -n "$ERRORS" ]; then
  err "Runtime errors detected after deploy:"
  echo "$ERRORS"
  exit 1
fi
ok "Health check passed — no runtime errors"
```

## Pre-Deploy Prerequisite Checks

Before running any deploy script, verify that required services and tools are available. Do NOT blindly retry a failed deploy — diagnose the failure first.

| Prerequisite | Check Command |
|-------------|---------------|
| Docker daemon | `docker info >/dev/null 2>&1` |
| AWS credentials | `aws sts get-caller-identity >/dev/null 2>&1` |
| CDK bootstrap | `aws cloudformation describe-stacks --stack-name CDKToolkit >/dev/null 2>&1` |
| Node.js | `node --version >/dev/null 2>&1` |
| Python venv | `test -d .venv && source .venv/bin/activate` |

If a prerequisite check fails:
1. Tell the user what is missing and how to fix it
2. Do NOT retry the deploy until the user confirms the prerequisite is met
3. After the user confirms, re-run the prerequisite check before retrying
