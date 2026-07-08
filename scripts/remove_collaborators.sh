#!/usr/bin/env bash
set -euo pipefail

# remove_collaborators.sh
# Safely remove one or more GitHub collaborators from a repository.
# The script prompts for the repo owner, repo name, and a personal access token
# (or reads from GITHUB_TOKEN). It lists current collaborators and asks
# for confirmation before removing the specified users.

usage() {
  cat <<'EOF'
Usage: $0

This script will remove one or more collaborators from a GitHub repository.
You will be prompted for:
 - OWNER (GitHub account or org owning the repo)
 - REPO (repository name, default: HealthCare-Plus)
 - GITHUB_TOKEN (or set env GITHUB_TOKEN)
 - comma-separated list of usernames to remove

The token needs the `repo` scope for private repos or `public_repo` for public repos,
and you must be an admin of the repository.
EOF
  exit 1
}

command -v curl >/dev/null 2>&1 || { echo "curl is required; please install it."; exit 1; }
command -v jq >/dev/null 2>&1 || echo "Warning: jq not found — output will be less readable."

read -r -p "Owner (GitHub user or org) [required]: " OWNER
if [[ -z "$OWNER" ]]; then
  echo "Owner is required." >&2
  usage
fi

read -r -p "Repo name [default: HealthCare-Plus]: " REPO
REPO=${REPO:-HealthCare-Plus}

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo -n "Enter GitHub personal access token (input hidden): "
  read -rs GITHUB_TOKEN
  echo
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "A GitHub token is required (set GITHUB_TOKEN or enter it when prompted)." >&2
  exit 1
fi

API_BASE="https://api.github.com"

echo "Fetching current collaborators for $OWNER/$REPO..."
COLS_JSON=$(curl -sS -H "Authorization: token $GITHUB_TOKEN" "$API_BASE/repos/$OWNER/$REPO/collaborators")

if echo "$COLS_JSON" | jq -e . >/dev/null 2>&1; then
  echo "Current collaborators:"
  echo "$COLS_JSON" | jq -r '.[].login' || true
else
  echo "Unable to fetch collaborators. Response:"
  echo "$COLS_JSON"
  exit 1
fi

read -r -p "Enter comma-separated GitHub username(s) to remove (e.g. user1,user2): " INPUT_USERS
if [[ -z "$INPUT_USERS" ]]; then
  echo "No users supplied; aborting." >&2
  exit 1
fi

IFS=',' read -r -a USERS <<< "$INPUT_USERS"

echo
echo "You are about to remove the following users from $OWNER/$REPO:" 
for u in "${USERS[@]}"; do echo " - ${u// /}"; done
echo
read -r -p "Type YES to proceed: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "Aborted by user."; exit 0
fi

for raw_user in "${USERS[@]}"; do
  USER=$(echo "$raw_user" | xargs)
  if [[ -z "$USER" ]]; then
    continue
  fi

  echo -n "Removing $USER... "
  HTTP_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: token $GITHUB_TOKEN" \
    "$API_BASE/repos/$OWNER/$REPO/collaborators/$USER")

  if [[ "$HTTP_STATUS" -eq 204 ]]; then
    echo "done"
  elif [[ "$HTTP_STATUS" -eq 404 ]]; then
    echo "not found or already removed (404)"
  else
    echo "failed (HTTP $HTTP_STATUS)"
  fi
done

echo "Operation complete. Re-fetching collaborator list..."
curl -sS -H "Authorization: token $GITHUB_TOKEN" "$API_BASE/repos/$OWNER/$REPO/collaborators" | jq -r '.[].login' || true

exit 0
