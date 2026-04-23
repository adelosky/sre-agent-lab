#!/bin/bash
# Direct subagent creation bypassing post-provision issues

set -e

cd "$(cd "$(dirname "$0")/.." && pwd)"

TOKEN=$(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv)
AGENT_ENDPOINT=$(azd env get-value SRE_AGENT_ENDPOINT)

echo "Creating subagents..."
echo "Token: ${TOKEN:0:20}..."
echo "Agent: $AGENT_ENDPOINT"
echo ""

# Helper function
create_subagent() {
  local yaml_file="$1"
  local agent_name="$2"
  local json_file="/tmp/${agent_name}-temp.json"
  
  echo "📦 $agent_name..."
  python scripts/yaml-to-api-json.py "$yaml_file" "$json_file" > /dev/null 2>&1 || {
    echo "   ❌ Conversion failed"
    return 1
  }
  
  local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT "${AGENT_ENDPOINT}/api/v2/extendedAgent/agents/${agent_name}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "@${json_file}")
  
  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ] || [ "$http_code" = "202" ]; then
    echo "   ✅ Created ($http_code)"
  else
    echo "   ⚠️  HTTP $http_code"
  fi
  
  rm -f "$json_file"
}

# Create all subagents
create_subagent "sre-config/agents/incident-handler-full.yaml" "incident-handler"
create_subagent "sre-config/agents/code-analyzer.yaml" "code-analyzer"
create_subagent "sre-config/agents/issue-triager.yaml" "issue-triager"

echo ""
echo "Done!"
