#!/usr/bin/env bash
set -euo pipefail

### 로그 설정 ###
LOG_FILE="/var/log/easy-cloudflare-ddns.log"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
exec >>"$LOG_FILE" 2>&1
TRACE_ID=$(cat /proc/sys/kernel/random/uuid)

### 기본 변수 초기화 ###
ZONE_ID=""
RECORD_NAME=""
API_TOKEN=""
API_TOKEN_FILE=""
TOKEN_ARG=""

### 명령행 옵션 파싱 ###
for arg in "$@"; do
  case "$arg" in
    --zone=*)
      ZONE_ID="${arg#*=}"
      ;;
    --record=*)
      RECORD_NAME="${arg#*=}"
      ;;
    --api-token=*)
      API_TOKEN="${arg#*=}"
      ;;
    --api-token-file=*)
      API_TOKEN_FILE="${arg#*=}"
      ;;
    *)
      echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] 알 수 없는 인자: $arg"
      exit 1
      ;;
  esac
done

### 필수 인자 유효성 검사 ###
if [ -z "$ZONE_ID" ] || [ -z "$RECORD_NAME" ]; then
  echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] --zone, --record 인자는 필수입니다."
  echo "Usage: $0 --zone=<ZONE_ID> --record=<RECORD_NAME> (--api-token=TOKEN | --api-token-file=FILE)"
  exit 1
fi

if [ -n "$API_TOKEN" ] && [ -n "$API_TOKEN_FILE" ]; then
  echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] --api-token과 --api-token-file은 동시에 사용할 수 없습니다."
  exit 1
elif [ -n "$API_TOKEN_FILE" ]; then
  if [ ! -f "$API_TOKEN_FILE" ] || [ ! -r "$API_TOKEN_FILE" ]; then
    echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] API 토큰 파일이 존재하지 않거나 읽을 수 없습니다: $API_TOKEN_FILE"
    exit 1
  fi
  TOKEN_ARG=$(cat "$API_TOKEN_FILE" | tr -d '\r\n[:space:]')
elif [ -n "$API_TOKEN" ]; then
  TOKEN_ARG=$(echo "$API_TOKEN" | tr -d '\r\n[:space:]')
else
  echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] --api-token 또는 --api-token-file 중 하나는 반드시 필요합니다."
  exit 1
fi

if [ -z "$TOKEN_ARG" ]; then
  echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] API 토큰 값이 비어 있습니다."
  exit 1
fi

### API 토큰 설정 ###
API_TOKEN="$TOKEN_ARG"

### 외부 IP 조회 ###
get_external_ip() {
  local ip
  ip=$(curl -fsS https://ifconfig.me/ip) || \
  ip=$(curl -fsS https://ifconfig.co/ip) || \
  ip=$(curl -fsS https://api.ipify.org) || \
  { echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] 외부 IP 조회 실패"; exit 1; }
  echo "$ip"
}

### 레코드 조회 ###
fetch_record() {
  curl -fsS -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${RECORD_NAME}" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json"
}

### 레코드 업데이트 ###
update_record() {
  local record_id="$1" new_ip="$2"
  curl -fsS -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${record_id}" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"${RECORD_NAME}\",\"content\":\"${new_ip}\",\"ttl\":120,\"proxied\":false}"
}

### 실행 시작 ###
echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] 스크립트 시작: ZONE=${ZONE_ID}, RECORD=${RECORD_NAME}"

EXT_IP=$(get_external_ip)
echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] 외부 IP: ${EXT_IP}"

RAW_JSON=$(fetch_record)

RECORD_ID=$(echo "$RAW_JSON" | jq -r '.result[0].id')
CURRENT_IP=$(echo "$RAW_JSON" | jq -r '.result[0].content')
echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] 현재 DNS IP: ${CURRENT_IP}"

if [ "$EXT_IP" != "$CURRENT_IP" ]; then
  echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] IP 변경 감지: ${CURRENT_IP} → ${EXT_IP}"
  RESULT_JSON=$(update_record "$RECORD_ID" "$EXT_IP")
  SUCCESS=$(echo "$RESULT_JSON" | jq -r '.success')
  if [ "$SUCCESS" = "true" ]; then
    echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] DNS 레코드 업데이트 성공: ${EXT_IP}"
  else
    echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] 업데이트 실패: $RESULT_JSON"
    exit 1
  fi
else
  echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] IP 동일: 업데이트 불필요"
fi

echo "($TRACE_ID) [$(date '+%Y-%m-%d %H:%M:%S')] 스크립트 종료"
