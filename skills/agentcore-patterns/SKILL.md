# Amazon Bedrock AgentCore Patterns

Verified patterns for AgentCore Runtime, Gateway, Memory, and Bedrock IAM. Use when building or debugging AgentCore-based agents.

## Runtime Handler

The `@app.entrypoint` handler receives `payload` and `context`. The SDK inspects parameter **names** — `context` is required, not just position.

```python
from bedrock_agentcore.runtime import BedrockAgentCoreApp
app = BedrockAgentCoreApp()

@app.entrypoint
def handler(payload, context):  # param MUST be named 'context'
    session_id = getattr(context, 'session_id', 'default')
    user_message = payload.get('prompt', '')
    # ... agent logic ...
    return str(result)

app.run()
```

**Pitfall**: Using `session` instead of `context` causes `TypeError: handler() missing 1 required positional argument`.

## Gateway MCP Client (IAM Auth / SigV4)

Gateway with `IamAuthorizer` requires SigV4-signed requests. Use `mcp-proxy-for-aws`:

```python
from mcp_proxy_for_aws.client import aws_iam_streamablehttp_client
from strands.tools.mcp import MCPClient

mcp_client = MCPClient(lambda: aws_iam_streamablehttp_client(
    endpoint=gateway_url,
    aws_region='us-east-1',
    aws_service='bedrock-agentcore',
))
```

**Pitfalls**:
- `MCPClient(transport=...)` is the old API — it now takes a callable
- Plain `streamablehttp_client` without SigV4 returns 401 against IAM-authenticated Gateways
- `aws_service` must be `bedrock-agentcore`

## Memory (Strands Integration)

Use `AgentCoreMemorySessionManager` as the Strands `session_manager`:

```python
from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig
from bedrock_agentcore.memory.integrations.strands.session_manager import AgentCoreMemorySessionManager

config = AgentCoreMemoryConfig(
    memory_id=memory_id,
    session_id=session_id,
    actor_id=actor_id,
)
with AgentCoreMemorySessionManager(config, region_name='us-east-1') as sm:
    agent = Agent(session_manager=sm, model=model, tools=tools)
    result = agent(user_message)
```

**Pitfall**: `MemoryClient(memory_id=...)` is wrong — `MemoryClient` takes `region_name`, and `memory_id` goes to individual operations.

## Bedrock IAM for Cross-Region Inference Profiles

Two statements required:

```python
from aws_cdk import Stack

account = Stack.of(self).account
model_id = 'us.anthropic.claude-haiku-4-5-20251001-v1:0'
fm_id = model_id.split('.', 1)[1]  # strip geographic prefix

# 1. Inference profile (includes account ID)
iam.PolicyStatement(
    actions=['bedrock:InvokeModel', 'bedrock:InvokeModelWithResponseStream'],
    resources=[f'arn:aws:bedrock:*:{account}:inference-profile/{model_id}']
)

# 2. Foundation model (no account ID)
iam.PolicyStatement(
    actions=['bedrock:InvokeModel', 'bedrock:InvokeModelWithResponseStream'],
    resources=[f'arn:aws:bedrock:*::foundation-model/{fm_id}']
)
```

**Pitfalls**:
- Inference profile ARN requires account ID — `arn:aws:bedrock:*::inference-profile/...` (empty account) never matches
- Foundation model ARN has NO account ID — `arn:aws:bedrock:*::foundation-model/...`
- Strands uses `ConverseStream` which needs `bedrock:InvokeModelWithResponseStream`, not just `bedrock:InvokeModel`
