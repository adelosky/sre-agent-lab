#!/bin/bash
# =============================================================================
# setup-github.sh — Add GitHub integration to an existing SRE Agent
# Uses REST APIs (az rest + curl) — no srectl dependency.
# For the srectl version, see setup-github-srectl.sh
#
# Usage:
#   ./scripts/setup-github.sh
# =============================================================================

# Windows compatibility: python3 may be 'python' on Windows
if command -v python3 &>/dev/null; then
  PYTHON=python3
elif command -v python &>/dev/null; then
  PYTHON=python
else
  echo "ERROR: Python not found"; exit 1
fi
set -e

# Read azd environment
AGENT_ENDPOINT=$(azd env get-value SRE_AGENT_ENDPOINT 2>/dev/null || echo "")
AGENT_NAME=$(azd env get-value SRE_AGENT_NAME 2>/dev/null || echo "")
RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null || echo "")
SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null || echo "")

if [ -z "$AGENT_ENDPOINT" ] || [ -z "$AGENT_NAME" ]; then
  echo "❌ Could not read agent details. Run from azd project directory after 'azd up'."
  exit 1
fi

AGENT_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/agents/${AGENT_NAME}"
API_VERSION="2025-05-01-preview"

get_token() {
  az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>/dev/null
}

ensure_pyyaml() {
  if $PYTHON -c "import yaml" >/dev/null 2>&1; then
    return 0
  fi

  echo "   Python package 'pyyaml' is missing. Attempting automatic install..."
  if $PYTHON -m pip --version >/dev/null 2>&1; then
    $PYTHON -m pip install --user pyyaml >/dev/null 2>&1 || true
  fi

  if ! $PYTHON -c "import yaml" >/dev/null 2>&1; then
    echo "❌ Missing Python module: yaml"
    echo "   Install it with: $PYTHON -m pip install pyyaml"
    exit 1
  fi
}

# Git Bash on Windows can fail TLS revocation checks with curl (exit code 35).
CURL_FLAGS=(-sS)
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*) CURL_FLAGS+=(--ssl-no-revoke) ;;
esac

curl_sre() {
  curl "${CURL_FLAGS[@]}" --retry 3 --retry-delay 2 --retry-all-errors --connect-timeout 15 --max-time 90 "$@"
}

curl_http_code() {
  curl_sre -o /dev/null -w "%{http_code}" "$@" 2>/dev/null || true
}

apply_subagent_spec() {
  local subagent_name="$1"
  local spec_file="$2"

  if [ "$AGENT_EXTENSIONS_AVAILABLE" = "false" ]; then
    echo "   ⏭️  Skipped ${subagent_name} (Agent Extensions not available in this tenant)"
    return 2
  fi

  SPEC_JSON=$($PYTHON -c "
import yaml, json
with open('${spec_file}') as f:
    data = yaml.safe_load(f)
print(json.dumps(data['spec']))
")
  SPEC_B64=$(echo -n "$SPEC_JSON" | base64 | tr -d '\r\n')

  local err
  if ! err=$(az rest --method PUT \
    --url "https://management.azure.com${AGENT_RESOURCE_ID}/subagents/${subagent_name}?api-version=${API_VERSION}" \
    --body "{\"properties\":{\"value\":\"${SPEC_B64}\"}}" \
    --output none 2>&1); then
    if echo "$err" | grep -qi "Agent Extensions is invalid"; then
      AGENT_EXTENSIONS_AVAILABLE=false
      echo "   ⚠️  ${subagent_name} skipped: Agent Extensions are not available for this tenant"
      return 2
    fi
    echo "   ⚠️  ${subagent_name} apply failed"
    echo "      ${err}"
    return 1
  fi

  return 0
}

echo ""
echo "============================================="
echo "  🔗 Adding GitHub Integration"
echo "============================================="
echo ""

SUBAGENT_FAILURES=0
AGENT_EXTENSIONS_AVAILABLE=true

# Step 1: Configure GitHub OAuth connector (data plane + ARM)
echo "1️⃣  Configuring GitHub OAuth connector..."
TOKEN=$(get_token)
RESULT=$(curl_http_code \
  -X PUT "${AGENT_ENDPOINT}/api/v2/extendedAgent/connectors/github" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"github","type":"AgentConnector","properties":{"dataConnectorType":"GitHubOAuth","dataSource":"github-oauth"}}')
if [ "$RESULT" = "200" ] || [ "$RESULT" = "201" ]; then
  echo "   ✅ GitHub OAuth connector created"
else
  echo "   ⚠️  GitHub connector returned HTTP ${RESULT}"
fi

az rest --method PUT \
  --url "https://management.azure.com${AGENT_RESOURCE_ID}/DataConnectors/github?api-version=${API_VERSION}" \
  --body '{"properties":{"dataConnectorType":"GitHubOAuth","dataSource":"github-oauth"}}' \
  --output none 2>/dev/null || true

TOKEN=$(get_token)
OAUTH_URL=$(curl_sre "${AGENT_ENDPOINT}/api/v1/github/config" \
  -H "Authorization: Bearer ${TOKEN}" 2>/dev/null | $PYTHON -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('oAuthUrl', '') or d.get('OAuthUrl', '') or '')
except: print('')
" 2>/dev/null)
if [ -n "$OAUTH_URL" ]; then
  echo "   🔐 Authorize GitHub here: ${OAUTH_URL}"
else
  echo "   ⚠️  Could not retrieve OAuth URL. Open Builder > Connectors > GitHub OAuth in https://sre.azure.com"
fi

ensure_pyyaml

# Step 2: Upload triage runbook
echo "2️⃣  Uploading triage runbook..."
TOKEN=$(get_token)
if curl_sre -X POST "${AGENT_ENDPOINT}/api/v1/AgentMemory/upload" \
  -H "Authorization: Bearer ${TOKEN}" \
  -F "triggerIndexing=true" \
  -F "files=@./knowledge-base/github-issue-triage.md;type=text/plain" \
  > /dev/null 2>&1; then
  echo "   ✅ Uploaded github-issue-triage.md"
else
  echo "   ⚠️  Runbook upload failed; continuing. Re-run this script after OAuth sign-in if needed."
fi

# Step 3: Upgrade incident handler with GitHub tools
echo "3️⃣  Upgrading incident handler..."
if apply_subagent_spec "incident-handler" "sre-config/agents/incident-handler-full.yaml"; then
  echo "   ✅ incident-handler upgraded with GitHub tools"
else
  if [ "$?" -eq 1 ]; then
    SUBAGENT_FAILURES=$((SUBAGENT_FAILURES + 1))
  fi
fi

# Step 4: Create code-analyzer subagent
echo "4️⃣  Creating code-analyzer subagent..."
if apply_subagent_spec "code-analyzer" "sre-config/agents/code-analyzer.yaml"; then
  echo "   ✅ code-analyzer created"
else
  if [ "$?" -eq 1 ]; then
    SUBAGENT_FAILURES=$((SUBAGENT_FAILURES + 1))
  fi
fi

# Step 5: Create issue-triager subagent
echo "5️⃣  Creating issue-triager subagent..."
if apply_subagent_spec "issue-triager" "sre-config/agents/issue-triager.yaml"; then
  echo "   ✅ issue-triager created"
else
  if [ "$?" -eq 1 ]; then
    SUBAGENT_FAILURES=$((SUBAGENT_FAILURES + 1))
  fi
fi

echo ""
echo "============================================="
if [ "$SUBAGENT_FAILURES" -eq 0 ]; then
  echo "  ✅ GitHub Integration Complete!"
else
  echo "  ⚠️  GitHub OAuth Connected (Partial Setup)"
fi
echo "============================================="
echo ""
if [ "$SUBAGENT_FAILURES" -eq 0 ]; then
  echo "  New capabilities:"
  echo "  ├── incident-handler: now searches GitHub code + creates issues"
  echo "  ├── code-analyzer: deep source code root cause analysis"
  echo "  └── issue-triager: automated issue triage from runbook"
else
  echo "  GitHub OAuth connector was created successfully."
  if [ "$AGENT_EXTENSIONS_AVAILABLE" = "false" ]; then
    echo "  Subagent updates were skipped because this tenant does not support Agent Extensions."
  else
    echo "  Some subagent updates failed. Review warnings above for details."
  fi
fi
echo ""
