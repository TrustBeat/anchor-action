#!/usr/bin/env bash
# TrustBeat Anchor — core script of the GitHub Action.
#
# Hashes each input file locally (SHA-256), submits the hashes to the
# TrustBeat anchoring API, optionally waits for the Merkle inclusion proofs,
# and writes a job-summary table with verify links + badge snippets.
#
# File contents never leave the runner — only 64-hex digests are transmitted.
#
# Requires: bash, curl, jq, sha256sum (all present on GitHub-hosted runners).
set -euo pipefail

API_URL="${TRUSTBEAT_API_URL:-https://api.trustbeat.eu}"
PORTAL_URL="${TRUSTBEAT_PORTAL_URL:-https://trustbeat.eu}"
WAIT="${TRUSTBEAT_WAIT:-false}"
POLL_INTERVAL=30
POLL_TIMEOUT=900   # 15 min — covers one full 10-minute batch cycle with margin

for dep in curl jq sha256sum; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "::error::'$dep' is required (preinstalled on GitHub-hosted runners; install it on self-hosted ones)"
    exit 1
  fi
done

if [[ -z "${TRUSTBEAT_API_KEY:-}" ]]; then
  echo "::error::api-key is required (create one free at ${PORTAL_URL}/register)"
  exit 1
fi

DESCRIPTION="${TRUSTBEAT_DESCRIPTION:-}"
if [[ -z "$DESCRIPTION" ]]; then
  DESCRIPTION="${GITHUB_REPOSITORY:-local}@${GITHUB_REF_NAME:-dev}"
fi
CLIENT_REF="${TRUSTBEAT_CLIENT_REF:-${GITHUB_SHA:-}}"

# ── Expand file globs (one pattern per line) ─────────────────────────────────
declare -a FILES=()
while IFS= read -r pattern; do
  pattern="$(echo "$pattern" | xargs || true)"   # trim
  [[ -z "$pattern" ]] && continue
  # shellcheck disable=SC2206  # intentional glob expansion
  matched=($pattern)
  for f in "${matched[@]}"; do
    if [[ -f "$f" ]]; then FILES+=("$f"); fi
  done
done <<< "${TRUSTBEAT_FILES:-}"

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "::error::no files matched the 'files' input: ${TRUSTBEAT_FILES:-<empty>}"
  exit 1
fi

echo "Anchoring ${#FILES[@]} file(s) via ${API_URL} — hashes only, files never leave the runner."

# ── Submit each hash ─────────────────────────────────────────────────────────
RESULTS="[]"
for f in "${FILES[@]}"; do
  hash="$(sha256sum "$f" | cut -d' ' -f1)"
  body="$(jq -n --arg h "$hash" --arg d "$DESCRIPTION — $(basename "$f")" --arg r "$CLIENT_REF" \
    '{hash: $h, description: $d} + (if $r != "" then {client_ref: $r} else {} end)')"

  response="$(curl -sS -w '\n%{http_code}' -X POST "${API_URL}/v1/anchor" \
    -H "Authorization: Bearer ${TRUSTBEAT_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$body")"
  status="$(echo "$response" | tail -n1)"
  json="$(echo "$response" | sed '$d')"

  if [[ "$status" != "202" ]]; then
    echo "::error::anchor of $f failed (HTTP $status): $(echo "$json" | head -c 300)"
    exit 1
  fi

  id="$(echo "$json" | jq -r '.id')"
  echo "  anchored $f  sha256=${hash:0:12}…  id=$id"

  RESULTS="$(echo "$RESULTS" | jq \
    --arg file "$f" --arg hash "$hash" --arg id "$id" \
    --arg verify "${PORTAL_URL}/verify?id=${id}" \
    --arg badge "${API_URL}/v1/public/badge/${id}" \
    '. + [{file: $file, hash: $hash, id: $id, verify_url: $verify, badge_url: $badge}]')"
done

# ── Optionally wait for inclusion proofs ─────────────────────────────────────
if [[ "$WAIT" == "true" ]]; then
  echo "Waiting for inclusion proofs (batches run every 10 minutes)…"
  deadline=$(( $(date +%s) + POLL_TIMEOUT ))
  for id in $(echo "$RESULTS" | jq -r '.[].id'); do
    while true; do
      code="$(curl -sS -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer ${TRUSTBEAT_API_KEY}" \
        "${API_URL}/v1/anchor/${id}/proof")"
      if [[ "$code" == "200" ]]; then
        echo "  proof ready: $id"
        break
      fi
      if (( $(date +%s) >= deadline )); then
        echo "::error::timed out after ${POLL_TIMEOUT}s waiting for proof $id"
        exit 1
      fi
      sleep "$POLL_INTERVAL"
    done
  done
fi

# ── Outputs ──────────────────────────────────────────────────────────────────
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "results=$(echo "$RESULTS" | jq -c .)"
    echo "ids=$(echo "$RESULTS" | jq -c '[.[].id]')"
  } >> "$GITHUB_OUTPUT"
fi

# ── Job summary ──────────────────────────────────────────────────────────────
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## ⚓ TrustBeat — qualified EU timestamp"
    echo
    if [[ "$WAIT" == "true" ]]; then
      echo "Each artifact below is anchored with an **eIDAS-qualified timestamp** — legally presumed valid across the EU (eIDAS Art. 41)."
    else
      echo "Each artifact below is queued for the next anchoring batch (≤ 10 min). Proof and badge links go live automatically — no further action needed."
    fi
    echo
    echo "| File | SHA-256 | Proof |"
    echo "|---|---|---|"
    echo "$RESULTS" | jq -r '.[] | "| `\(.file)` | `\(.hash[0:16])…` | [verify ↗](\(.verify_url)) |"'
    echo
    echo "**Badge for your README / release notes:**"
    echo
    first_id="$(echo "$RESULTS" | jq -r '.[0].id')"
    echo '```markdown'
    echo "[![Anchored — qualified EU timestamp](${API_URL}/v1/public/badge/${first_id})](${PORTAL_URL}/verify?id=${first_id})"
    echo '```'
    echo
    echo "_Verification is independent: anyone can check the Merkle proof and RFC 3161 token without trusting TrustBeat — [manual guide](${PORTAL_URL}/en/manual-verify)._"
  } >> "$GITHUB_STEP_SUMMARY"
fi

echo "Done: $(echo "$RESULTS" | jq -r 'length') file(s) anchored."
