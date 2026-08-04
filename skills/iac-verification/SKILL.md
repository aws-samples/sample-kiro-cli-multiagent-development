---
name: iac-verification
description: Strong validation commands for infrastructure-as-code (CDK, CloudFormation, Terraform, Docker, Kubernetes) plus mandatory post-deploy smoke tests. Use when verifying IaC changes before marking a task complete, or when authoring or modifying a deploy script — render and validate the actual output, never just lint or cat the file.
---

# IaC Verification

A file that parses is not a file that works. Always verify infrastructure by rendering/validating the real output with the tool's own command. Use the strong command, never the weak one.

## Verify Commands by Tool

| Tool | Weak (do NOT use) | Strong (use this) |
|------|-------------------|-------------------|
| AWS CDK | `python3 -c "from stack import MyStack"` | `cdk synth <StackName> 2>&1` |
| CloudFormation | `cat template.yaml` | `aws cloudformation validate-template --template-body file://template.yaml --no-cli-pager` |
| Terraform | `terraform fmt` | `terraform validate` |
| Docker | `cat Dockerfile` | `docker build --check .` |
| Kubernetes | `cat manifest.yaml` | `kubectl apply --dry-run=server -f manifest.yaml` |
| Helm | `cat values.yaml` | `helm template . \| kubectl apply --dry-run=client -f -` |

Import checks and `cat` only prove a file parses — they do NOT prove the constructs, resources, or properties are correct.

## CDK

```bash
# Synthesize a single stack — fails loudly on bad construct args or resolution errors
cdk synth MyStack 2>&1

# Synthesize all stacks
cdk synth --all 2>&1

# Show what would change against deployed state (read-only, safe)
cdk diff MyStack 2>&1
```

Run from the directory containing `cdk.json`. `cdk synth` failing is the signal the code is wrong — read the error, do not assume the construct API.

## CloudFormation

```bash
# Schema + syntax validation via the service
aws cloudformation validate-template \
  --template-body file://template.yaml \
  --no-cli-pager

# Deeper local lint (catches resource-property errors validate-template misses)
cfn-lint template.yaml
```

## Terraform

```bash
terraform init -backend=false   # init providers without touching remote state
terraform validate              # config + provider schema validation
terraform plan -lock=false      # read-only preview of changes
```

Use `terraform validate`, not `terraform fmt` — `fmt` only checks formatting.

## Docker

```bash
# Build-time validation of Dockerfile (BuildKit)
docker build --check .

# Full build to confirm it actually builds
docker build -t scratch-check:local .
```

## Rules

- Do not infer a resource property, ARN format, or construct argument from its name — verify the contract first (project `docs/tech.md`, AWS docs, or `@context7`), then write.
- Run the strong-verify command before marking any IaC task `[x]`.
- If the verify command fails twice for the same reason, mark the task `[!]` with the exact error and stop — do not loop on edits.
- All commands must be non-interactive (`--no-cli-pager`, `-auto-approve` only where explicitly intended, `--dry-run` for cluster ops).

---

## Post-Deploy Validation

Every deploy script MUST include a post-deploy smoke test. Never rely on users to discover runtime errors.

### Smoke Test by Deployment Target

Every deploy script MUST include a post-deploy smoke test appropriate to the deployment target.

| Deployment Target | Smoke Test |
|-------------------|------------|
| Container/Runtime service | Wait 60s, check CloudWatch logs for `ERROR`/`Traceback` |
| Frontend (S3 + CloudFront) | Verify CloudFront URL returns HTTP 200 after invalidation |
| Lambda function | Invoke with test payload, or verify function state is `Active` |
| API Gateway | Hit health check endpoint, verify 200 response |
| ECS/Fargate service | Verify task count matches desired, check ALB health |

Deploy script MUST exit non-zero if any smoke test fails. A "successful deploy" that crashes at runtime is not successful.

### Implementation Pattern

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

### Pre-Deploy Prerequisite Checks

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
