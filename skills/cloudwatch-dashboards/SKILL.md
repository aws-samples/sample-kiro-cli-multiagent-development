---
name: cloudwatch-dashboards
description: AWS CloudWatch dashboard observability patterns including dashboard hierarchy, widget selection, CDK implementation, metric math, alarms, and cross-account monitoring. Use when creating dashboards, setting up observability, or instrumenting workloads with CloudWatch.
---

# CloudWatch Dashboards

## Dashboard Hierarchy

Create dashboards at multiple levels — don't put everything on one dashboard.

| Level | Purpose | Audience |
|-------|---------|----------|
| Account/cross-service | High-level health across all workloads | Ops team, leadership |
| Application/workload | Key metrics for a specific service | Dev team, on-call |
| Incident/runbook | Focused view for troubleshooting specific failure modes | On-call engineer |

Start every dashboard with a `TextWidget` header explaining what it monitors and who owns it.

## Widget Selection

| Widget | Use When |
|--------|----------|
| `GraphWidget` | Trending metrics over time (CPU, latency, request count) |
| `SingleValueWidget` | Current value of a KPI (active users, error rate, queue depth) |
| `GaugeWidget` | Value within a known range (disk usage %, memory %) |
| `AlarmStatusWidget` | At-a-glance health of multiple alarms in a grid |
| `LogQueryWidget` | Recent log entries or log-derived metrics (error counts, top paths) |
| `TextWidget` | Section headers, runbook links, ownership info |
| `CustomWidget` | Lambda-backed dynamic content (cost data, external API status) |

## CDK Dashboard Pattern (Python)

```python
from aws_cdk import Duration
from aws_cdk import aws_cloudwatch as cw

# Create dashboard
dashboard = cw.Dashboard(self, "AppDashboard",
    dashboard_name=f"{env}-my-service",
    default_interval=Duration.hours(3),
)

# Section header
dashboard.add_widgets(cw.TextWidget(
    markdown="# My Service Dashboard\nOwner: team-foo | Runbook: [link](https://...)",
    height=1, width=24,
))

# Alarm status grid — put this at the top
dashboard.add_widgets(cw.AlarmStatusWidget(
    title="Alarm Status",
    alarms=[error_alarm, latency_alarm, throttle_alarm],
    width=24, height=2,
))

# Metrics row — use Row for horizontal layout
dashboard.add_widgets(cw.Row(
    cw.GraphWidget(title="Request Count", left=[api_requests_metric], width=8),
    cw.GraphWidget(title="Error Rate", left=[error_rate_metric], width=8),
    cw.GraphWidget(title="Latency p99", left=[latency_p99_metric], width=8),
))

# Single value KPIs
dashboard.add_widgets(cw.Row(
    cw.SingleValueWidget(title="Active Users", metrics=[active_users], width=6),
    cw.SingleValueWidget(title="Queue Depth", metrics=[queue_depth], width=6),
    cw.SingleValueWidget(title="Error Count", metrics=[error_count], width=6, color="#d13212"),
))

# Log query widget
dashboard.add_widgets(cw.LogQueryWidget(
    title="Recent Errors",
    log_group_names=[log_group.log_group_name],
    query_lines=["fields @timestamp, @message", "filter @message like /ERROR/", "sort @timestamp desc", "limit 20"],
    width=24, height=6,
))
```

## Metric Math

Use metric math for derived metrics that aren't published directly.

```python
# Error rate as percentage
requests = cw.Metric(namespace="MyApp", metric_name="Requests", statistic="Sum")
errors = cw.Metric(namespace="MyApp", metric_name="Errors", statistic="Sum")

error_rate = cw.MathExpression(
    expression="(errors / requests) * 100",
    using_metrics={"errors": errors, "requests": requests},
    label="Error Rate %",
)

# EBS IOPS from read/write ops
iops = cw.MathExpression(
    expression="(reads + writes) / PERIOD(reads)",
    using_metrics={
        "reads": cw.Metric(namespace="AWS/EBS", metric_name="VolumeReadOps", statistic="Sum"),
        "writes": cw.Metric(namespace="AWS/EBS", metric_name="VolumeWriteOps", statistic="Sum"),
    },
    label="IOPS",
)
```

## Alarms on Dashboards

Always pair dashboards with alarms — dashboards are for humans, alarms are for automation.

```python
# Alarm on error rate
error_alarm = cw.Alarm(self, "HighErrorRate",
    metric=error_rate,
    threshold=5,
    evaluation_periods=3,
    comparison_operator=cw.ComparisonOperator.GREATER_THAN_THRESHOLD,
    alarm_description="Error rate exceeded 5% for 3 consecutive periods",
    treat_missing_data=cw.TreatMissingData.NOT_BREACHING,
)

# Composite alarm to reduce noise
composite = cw.CompositeAlarm(self, "ServiceHealth",
    alarm_rule=cw.AlarmRule.any_of(error_alarm, latency_alarm),
    alarm_description="Service degraded — high errors or latency",
)
```

## Service-Specific Metrics

Use built-in `.metric_*()` methods instead of constructing metrics manually:

```python
# Lambda
fn.metric_invocations()
fn.metric_errors()
fn.metric_duration()
fn.metric_throttles()

# API Gateway
api.metric_count()
api.metric_latency()
api.metric_server_error()
api.metric_client_error()

# DynamoDB
table.metric_consumed_read_capacity_units()
table.metric_consumed_write_capacity_units()
table.metric_throttled_requests_for_operation("GetItem")

# SQS
queue.metric_approximate_number_of_messages_visible()
queue.metric_number_of_messages_sent()
queue.metric_approximate_age_of_oldest_message()
```

## Cross-Account / Cross-Region

CloudWatch dashboards support cross-region widgets natively. For cross-account, use CloudWatch cross-account observability.

```python
# Cross-region metric
cw.Metric(
    namespace="AWS/EC2",
    metric_name="CPUUtilization",
    dimensions_map={"InstanceId": "i-abc123"},
    region="eu-west-1",  # different from stack region
)

# Cross-account metric (requires cross-account observability setup)
cw.GraphWidget(
    title="Cross-Account CPU",
    left=[cpu_metric],
    account_id="123456789012",  # source account
)
```

## Anti-Patterns

- **Too many metrics on one dashboard** — if you need to scroll, split it
- **Dashboards without alarms** — dashboards are for context, alarms are for detection
- **Stale dashboards** — update when features ship or retire; add as a task in specs
- **No text context** — always include headers, ownership, and runbook links
- **Raw counts without rates** — "500 errors" means nothing without "out of 100K requests"
- **Missing period alignment** — use consistent periods across widgets for correlation
