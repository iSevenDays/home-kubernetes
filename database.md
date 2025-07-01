# OpenHands Database Configuration Issues

## Overview

OpenHands uses a PostgreSQL database to store user-specific settings that can override environment variables and application defaults. This document outlines common database-related configuration issues and their solutions.

## User Settings Override Issue

### Problem Description

OpenHands was using external LLM proxy URL `https://llm-proxy.redacted` instead of the internal Kubernetes service URL `http://openhands-litellm.openhands.svc.cluster.local:4000`, causing 504 timeouts and connectivity issues.

### Root Cause

The issue occurs due to the **SaaS settings store configuration mechanism** that overrides environment variables with user-specific settings stored in the database.

#### Configuration Flow

```
1. Container Startup:
   Environment Variables Set: LLM_BASE_URL=http://openhands-litellm.openhands.svc.cluster.local:4000
   ↓ LLMConfig() direct instantiation returns base_url=None (env not auto-loaded)

2. Session Creation:
   load_from_env() works when manually called
   ↓ SaasSettingsStore loads user settings from database
   ↓ User settings override environment variables
   ↓ Session.initialize_agent() applies settings.llm_base_url to default_llm_config

3. LLM Usage:
   ↓ Uses settings.llm_base_url from database instead of environment variables
```

#### Key Files Involved

1. **Primary Configuration Override**: `/app/storage/saas_settings_store.py:277`

   ```python
   settings.llm_base_url = LITE_LLM_API_URL  # This should work correctly
   ```

2. **Session Initialization**: `/app/openhands/server/session/session.py:126`

   ```python
   default_llm_config.base_url = settings.llm_base_url  # Uses database value
   ```

3. **Database Storage**: `user_settings` table stores user-specific LLM configuration

### Configuration Precedence (High to Low)

1. **User-specific database settings** (from `user_settings` table) ← **ROOT CAUSE**
2. Environment variables (correctly set but overridden)
3. Default configuration (fallback)

## Context Window Validation Error

### Problem Description

After fixing the LLM proxy URL issue, OpenHands may encounter a Pydantic validation error:

```
1 validation error for TokenUsage
context_window
  Input should be a valid integer [type=int_type, input_value=None, input_type=NoneType]
```

This error occurs when the LLM completion succeeds, but the model metadata doesn't include the `context_window` information required for token usage tracking.

### Root Cause

The LiteLL service configuration is missing the `context_window` field in the model configuration. OpenHands requires this field to track token usage properly, but LiteLL is not providing this information for the model.

### Solution

Update the LiteLL configuration to include the `context_window` field for the model:

1. **Check current LiteLL configuration:**

   ```bash
   kubectl get configmap -n openhands openhands-litellm-config -o yaml
   ```

2. **Update the model configuration to include context_window:**

   ```yaml
   model_list:
   - litellm_params:
       api_base: api-base-redacted
       api_key: sk-rtiugirtngiunrtipughipn43igh4589pgjrting
       max_tokens: 20000  # Maximum output tokens
       model: openai/ubergarm/DeepSeek-R1-0528-IQ3_K_R4
       timeout: 3600
       context_window: 131072  # Add this line - 128k context window for DeepSeek-R1
     model_name: openai/ubergarm/DeepSeek-R1-0528-IQ3_K_R4
   ```

3. **Apply the updated configuration:**

   ```bash
   kubectl patch configmap -n openhands openhands-litellm-config --patch '{"data":{"config.yaml":"<updated_config>"}}'
   ```

4. **Restart LiteLL service to pick up the new configuration:**

   ```bash
   kubectl rollout restart deployment -n openhands openhands-litellm
   ```

5. **Restart OpenHands to clear any cached model metadata:**

   ```bash
   kubectl rollout restart deployment -n openhands openhands
   ```

### Model Context Window Values

Common context window sizes for different models:

- **DeepSeek-R1**: 131072 tokens (128k)
- **GPT-4**: 8192 tokens (8k) or 32768 tokens (32k)
- **Claude-3**: 200000 tokens (200k)
- **Llama-2**: 4096 tokens (4k)

### Verification

After applying the fix, verify that the error is resolved:

1. **Check LiteLL logs for successful model loading:**

   ```bash
   kubectl logs -n openhands -l app=openhands-litellm --tail=50
   ```

2. **Create a new conversation in OpenHands and test LLM functionality**

3. **Check OpenHands logs for successful token usage tracking:**

   ```bash
   kubectl logs -n openhands -l app=openhands --tail=100 | grep -E "(TokenUsage|context_window)"
   ```

The logs should no longer show Pydantic validation errors, and OpenHands should successfully track token usage.

## Database Access

### Accessing the PostgreSQL Database

```bash
# Get the PostgreSQL password
kubectl get secret -n openhands postgres-password -o jsonpath='{.data.password}' | base64 -d

# Access the database
kubectl exec -n openhands openhands-postgresql-0 -- env PGPASSWORD='<password>' psql -U postgres -d openhands
```

### Important Tables

#### `user_settings` Table

Contains user-specific configuration that overrides environment variables:

```sql
-- View current user settings
SELECT keycloak_user_id, llm_base_url, llm_model FROM user_settings;

-- Check for problematic external URLs
SELECT keycloak_user_id, llm_base_url FROM user_settings
WHERE llm_base_url NOT LIKE '%openhands-litellm.openhands.svc.cluster.local%';
```

#### `conversation_metadata` Table

Contains conversation metadata and session information.

## Solutions

### Fix User Settings Override

#### Method 1: Update Existing User Settings

```sql
-- Update specific user
UPDATE user_settings
SET llm_base_url = 'http://openhands-litellm.openhands.svc.cluster.local:4000'
WHERE keycloak_user_id = '<user_id>';

-- Update all users (use with caution)
UPDATE user_settings
SET llm_base_url = 'http://openhands-litellm.openhands.svc.cluster.local:4000';
```

#### Method 2: Clear User Settings (Force Regeneration)

```sql
-- Delete specific user settings (will be regenerated from environment variables)
DELETE FROM user_settings WHERE keycloak_user_id = '<user_id>';

-- Clear all user settings (use with extreme caution)
DELETE FROM user_settings;
```

### Verification Commands

#### Check Environment Variables

```bash
kubectl exec -n openhands <pod-name> -c openhands -- env | grep -E "(LLM_BASE_URL|LITELLM_BASE_URL|LITE_LLM_API_URL)"
```

#### Test Configuration Loading

```bash
kubectl exec -n openhands <pod-name> -c openhands -- python3 -c "
from server.constants import LITE_LLM_API_URL
from openhands.core.config.utils import load_from_env
from openhands.core.config.openhands_config import OpenHandsConfig
import os

print('Environment LLM_BASE_URL:', os.environ.get('LLM_BASE_URL'))
print('LITE_LLM_API_URL constant:', LITE_LLM_API_URL)

config = OpenHandsConfig()
load_from_env(config, os.environ)
print('After load_from_env base_url:', config.get_llm_config().base_url)
"
```

#### Monitor Logs for Configuration

```bash
# Check for base_url in logs
kubectl logs -n openhands <pod-name> -c openhands --tail=100 | grep -i "base_url" | jq

# Look for the pipeline condenser log that shows the actual URL being used
kubectl logs -n openhands <pod-name> -c openhands --tail=100 | grep "Enabling pipeline condenser"
```

## Database Maintenance

### Reset Database (Development Only)

```bash
# Scale down OpenHands
helm -n openhands uninstall openhands-runtime-api --no-hooks
kubectl scale statefulset -n openhands openhands-postgresql --replicas=0

# Delete persistent data
kubectl delete pvc -n openhands data-openhands-postgresql-0

# Scale back up
kubectl scale statefulset -n openhands openhands-postgresql --replicas=1

# Wait for PostgreSQL to be ready
kubectl get pod -n openhands -w

# Reconcile OpenHands
flux reconcile hr -n openhands openhands --with-source
```

### Backup User Settings

```bash
# Backup user settings
kubectl exec -n openhands openhands-postgresql-0 -- env PGPASSWORD='<password>' \
  pg_dump -U postgres -d openhands -t user_settings --data-only > user_settings_backup.sql

# Restore user settings
kubectl exec -i -n openhands openhands-postgresql-0 -- env PGPASSWORD='<password>' \
  psql -U postgres -d openhands < user_settings_backup.sql
```

## Prevention

### Environment Variable Validation

Ensure these environment variables are correctly set in the Helm chart:

```yaml
env:
- name: LLM_BASE_URL
  value: "http://openhands-litellm.openhands.svc.cluster.local:4000"
- name: LITELLM_BASE_URL
  value: "http://openhands-litellm.openhands.svc.cluster.local:4000"
- name: LITE_LLM_API_URL
  value: "http://openhands-litellm.openhands.svc.cluster.local:4000"
```

### Monitoring

Set up monitoring to detect when external URLs are being used:

```bash
# Alert on external LLM proxy usage
kubectl logs -n openhands -l app=openhands -c openhands --tail=100 | \
  grep -E "(llm-proxy\.sevendays\.cloud|external.*proxy)" && \
  echo "ALERT: External LLM proxy detected!"
```

## Troubleshooting

### Common Issues

1. **504 Timeouts**: Usually indicates external URL usage
2. **Authentication Errors**: May indicate incorrect LLM service configuration
3. **Session Creation Failures**: Often related to database connectivity or user settings

### Debug Steps

1. Check pod status: `kubectl get pods -n openhands`
2. Verify environment variables (see commands above)
3. Check user settings in database
4. Monitor logs during conversation creation
5. Test internal service connectivity

### Emergency Fix

If users are experiencing issues and you need an immediate fix:

```sql
-- Emergency: Update all user settings to use internal service
UPDATE user_settings
SET llm_base_url = 'http://openhands-litellm.openhands.svc.cluster.local:4000'
WHERE llm_base_url LIKE '%llm-proxy%' OR llm_base_url LIKE '%sevendays%';
```

Then restart OpenHands pods:

```bash
kubectl rollout restart deployment -n openhands openhands
```

## Related Files

- `issue.md` - Detailed root cause analysis
- `kubernetes/apps/openhands/openhands/app/helmrelease.yaml` - Environment variable configuration
- `templates/config/kubernetes/apps/openhands/openhands/app/helmrelease.yaml.j2` - Template source
