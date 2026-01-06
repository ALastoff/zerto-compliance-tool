
#!/usr/bin/env bash
set -euo pipefail
# Send logs to stderr and also tee to a file (stdout reserved for JSON token on success)
exec 2> >(tee -a /tmp/zerto_auth.log >&2)

# ---- Configuration ----
CLIENT_ID="4lif38ev9nsafmcm8lfe3iod5e"
COGNITO_EP="https://cognito-idp.us-east-1.amazonaws.com/"  # confirm pool region matches us-east-1
CLIENT_SECRET="${CLIENT_SECRET:-}"  # set via environment if your client has a secret

COGNITO_USER=""
COGNITO_PASS=""
MFA_CODE=""

# ---- SECRET_HASH helper (only used if CLIENT_SECRET is set) ----
secret_hash() {
  local username="$1"
  printf "%s" "${username}${CLIENT_ID}" \
    | openssl dgst -sha256 -hmac "${CLIENT_SECRET}" -binary \
    | base64 -w0
}

# ---- Args ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) COGNITO_USER="$2"; shift 2 ;;
    --pass) COGNITO_PASS="$2"; shift 2 ;;
    --mfa)  MFA_CODE="$2"; shift 2 ;;
    *) echo "[ERR] Unknown arg $1"; exit 2 ;;
  esac
done

[[ -n "$COGNITO_USER" && -n "$COGNITO_PASS" ]] || { echo "[ERR] Missing --user / --pass"; exit 2; }

# ---- InitiateAuth ----
echo "[REMOTE] Initiating Cognito USER_PASSWORD_AUTH for $COGNITO_USER ..." >&2

PARAMS=$(jq -n --arg u "$COGNITO_USER" --arg p "$COGNITO_PASS" \
  '{USERNAME:$u, PASSWORD:$p}')

if [[ -n "$CLIENT_SECRET" ]]; then
  SH=$(secret_hash "$COGNITO_USER")
  PARAMS=$(echo "$PARAMS" | jq --arg sh "$SH" '. + {SECRET_HASH:$sh}')
fi

INIT_PAYLOAD=$(jq -n --arg c "$CLIENT_ID" --argjson a "$PARAMS" \
  '{ClientId:$c, AuthFlow:"USER_PASSWORD_AUTH", AuthParameters:$a}')

INIT_RAW=$(curl -sS -X POST "$COGNITO_EP" \
  -H "Content-Type: application/x-amz-json-1.1" \
  -H "X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth" \
  --data-binary "$INIT_PAYLOAD" \
  -w "\n%{http_code}")

INIT_STATUS=$(echo "$INIT_RAW" | tail -n1)
INIT_BODY=$(echo "$INIT_RAW" | sed '$d')

if [[ "$INIT_STATUS" != "200" ]]; then
  echo "[ERR] InitiateAuth failed ($INIT_STATUS):" >&2
  echo "$INIT_BODY" | jq . >&2 || echo "$INIT_BODY" >&2
  exit 1
fi

CHALLENGE=$(echo "$INIT_BODY" | jq -r '.ChallengeName // empty')
SESSION=$(echo "$INIT_BODY" | jq -r '.Session // empty')

# ---- No challenge: success path ----
if [[ -z "$CHALLENGE" || "$CHALLENGE" == "null" ]]; then
  ID=$(echo "$INIT_BODY" | jq -r '.AuthenticationResult.IdToken // empty')
  if [[ -z "$ID" || "$ID" == "null" ]]; then
    echo "[ERR] Unexpected response without challenge:" >&2
    echo "$INIT_BODY" | jq . >&2 || echo "$INIT_BODY" >&2
    exit 1
  fi
  printf '{"token":"%s"}\n' "$ID"
  exit 0
fi

# ---- MFA challenge ----
echo "[REMOTE] MFA challenge received: $CHALLENGE" >&2

FIELD="SMS_MFA_CODE"
[[ "$CHALLENGE" == "SOFTWARE_TOKEN_MFA" ]] && FIELD="SOFTWARE_TOKEN_MFA_CODE"

[[ -n "$MFA_CODE" ]] || { echo "[ERR] MFA code required for $CHALLENGE. Rerun with --mfa <code>."; exit 2; }

RESP_PAYLOAD=$(jq -n \
  --arg c "$CLIENT_ID" --arg s "$SESSION" \
  --arg u "$COGNITO_USER" --arg f "$FIELD" --arg m "$MFA_CODE" \
  '{ClientId:$c, ChallengeName:"'$CHALLENGE'", Session:$s, ChallengeResponses:{USERNAME:$u}}' \
  | jq --arg f "$FIELD" --arg m "$MFA_CODE" '.ChallengeResponses[$f]=$m')

if [[ -n "$CLIENT_SECRET" ]]; then
  SH=$(secret_hash "$COGNITO_USER")
  RESP_PAYLOAD=$(echo "$RESP_PAYLOAD" | jq --arg sh "$SH" '.ChallengeResponses.SECRET_HASH=$sh')
fi

RESP_RAW=$(curl -sS -X POST "$COGNITO_EP" \
  -H "Content-Type: application/x-amz-json-1.1" \
  -H "X-Amz-Target: AWSCognitoIdentityProviderService.RespondToAuthChallenge" \
  --data-binary "$RESP_PAYLOAD" \
  -w "\n%{http_code}")

RESP_STATUS=$(echo "$RESP_RAW" | tail -n1)
RESP_BODY=$(echo "$RESP_RAW" | sed '$d')

if [[ "$RESP_STATUS" != "200" ]]; then
  echo "[ERR] RespondToAuthChallenge failed ($RESP_STATUS):" >&2
  echo "$RESP_BODY" | jq . >&2 || echo "$RESP_BODY" >&2
  exit 1
fi

ID=$(echo "$RESP_BODY" | jq -r '.AuthenticationResult.IdToken // empty')
if [[ -z "$ID" || "$ID" == "null" ]]; then
  echo "[ERR] No IdToken in response:" >&2
  echo "$RESP_BODY" | jq . >&2 || echo "$RESP_BODY" >&2
  exit 1
fi

# Success: print JSON token line on stdout
printf '{"token":"%s"}\n' "$ID"
