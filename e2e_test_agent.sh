#!/bin/bash

set -e

echo "Starting test agent for role: $VCC_ROLE_ID"

echo "Waiting for VCC bootstrap message..."

while IFS= read -r line; do

  if [[ "$line" == *"VCC bootstrap initialization"* ]]; then

    break

  fi

done

vcc ready



if [ "$VCC_ROLE_ID" == "lead" ]; then

  echo "Lead coordinator standing by..."

  while true; do

    for EXPECTED_ROLE in backend database frontend web-quality; do

        PR_NUMBER=$(gh pr list --state open --json number,headRefName,statusCheckRollup --jq ".[] | select(.headRefName == \"$EXPECTED_ROLE\") | select(.statusCheckRollup | length > 0) | select(.statusCheckRollup | all(.conclusion == \"SUCCESS\" and .status == \"COMPLETED\")) | .number" 2>/dev/null || echo "")

        

        if [ -n "$PR_NUMBER" ] && [ "$PR_NUMBER" != "null" ]; then

          echo "Lead: Found mergeable PR #$PR_NUMBER for branch $EXPECTED_ROLE. Reviewing..."

          gh pr review "$PR_NUMBER" --approve --body "Approved by Lead" || true

          echo "Lead: Attempting to merge PR #$PR_NUMBER via VCC API..."

          JSON_PAYLOAD=$(node -e "console.log(JSON.stringify({number: parseInt(process.argv[1])}))" "$PR_NUMBER")

          RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://host.docker.internal:4000/api/agent/pr/merge" \

            -H "Authorization: Bearer $VCC_EXECUTION_TOKEN" \

            -H "Content-Type: application/json" \

            -d "$JSON_PAYLOAD")

          HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

          BODY=$(echo "$RESPONSE" | head -n1)

          echo "Response: $BODY (HTTP $HTTP_CODE)"

          if [ "$HTTP_CODE" == "200" ]; then

            echo "Lead: PR #$PR_NUMBER merged successfully."

          fi

        else

          echo "Lead: No PRs with passing CI found yet for $EXPECTED_ROLE. Waiting..."

        fi

      done

    sleep 5

  done

else

  echo "Specialist $VCC_ROLE_ID starting work..."

  echo "test output from $VCC_ROLE_ID" > "output_$VCC_ROLE_ID.txt"

  BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)



  git add .

  git commit --allow-empty -m "feat: $VCC_ROLE_ID implementation"

  git push -u origin "$BRANCH_NAME"



  gh workflow run create-pr.yml -f branch="$BRANCH_NAME" -f "title=feat: $VCC_ROLE_ID"



  while true; do

    PR_NUMBER=$(gh pr list --state open --json number,headRefName \

      --jq ".[] | select(.headRefName == \"$BRANCH_NAME\") | .number" 2>/dev/null || echo "")

    if [ -n "$PR_NUMBER" ] && [ "$PR_NUMBER" != "null" ]; then

      echo "PR Created: #$PR_NUMBER for branch $BRANCH_NAME"

      git commit --allow-empty -m "trigger ci"

      git push origin "$BRANCH_NAME"

      break

    fi

    sleep 2

  done



  echo "PR Number: #$PR_NUMBER"



  HANDOFF_DIR="$VCC_PROJECT_ROOT/.vcc"

  if [ -n "$VCC_WORKTREE_ROOT" ] && [ "$VCC_WORKTREE_ROOT" != "$VCC_PROJECT_ROOT" ]; then

    HANDOFF_DIR="$VCC_WORKTREE_ROOT/.vcc"

  fi

  mkdir -p "$HANDOFF_DIR"

  cat > "$HANDOFF_DIR/${VCC_ROLE_ID}-handoff.json" <<EOF

{

  "role": "$VCC_ROLE_ID",

  "status": "complete",

  "branch": "$BRANCH_NAME",

  "commit": "$(git rev-parse HEAD)",

  "prUrl": "https://github.com/Jonathan-Acheampong042/vcc-phase11-final-test-4/pull/$PR_NUMBER",

  "summary": "E2E test: $VCC_ROLE_ID implementation complete",

  "completedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

}

EOF

  echo "Handoff artifact created at $HANDOFF_DIR/${VCC_ROLE_ID}-handoff.json"



  vcc complete

  sleep 10

fi