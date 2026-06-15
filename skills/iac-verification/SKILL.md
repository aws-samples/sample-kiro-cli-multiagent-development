---
name: iac-verification
description: Strong validation commands for infrastructure-as-code (CDK, CloudFormation, Terraform, Docker, Kubernetes). Use when verifying IaC changes before marking a task complete — render and validate the actual output, never just lint or cat the file.
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
