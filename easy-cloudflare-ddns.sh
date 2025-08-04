#!/usr/bin/env bash
set -euo pipefail

### 로그 설정 ###
LOG_FILE="/var/log/easy-cloudflare-ddns.log"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
exec >>"$LOG_FILE" 2>&1
TRACE_ID=$(cat /proc/sys/kernel/random/uuid | cut -c1-8)

### 로그 레벨 설정 ###
LOG_LEVEL="INFO"   # info, warn, error 중 하나 선택 (기본값: info)
log_level_to_number() {
  case "$1" in
    INFO) echo 0 ;;
    WARN) echo 1 ;;
    ERROR) echo 2 ;;
    *) echo 0 ;;  # 알 수 없는 레벨은 일단은 기본값이랑 똑같이 설정
  esac
}

### 로그 함수 ###
log_format() {
  local level="$1"
  shift

  local level_num current_level_num
  level_num=$(log_level_to_number "$level")
  current_level_num=$(log_level_to_number "$LOG_LEVEL")

  if [ "$level_num" -lt "$current_level_num" ]; then
    return 0
  fi

  local timestamp
  timestamp=$(date '+%m/%d/%Y-%H:%M:%S')
  echo "($TRACE_ID) [$level] [$timestamp] $*"
}

### 기본 변수 초기화 ###
ZONE_ID=""
RECORD_NAME=""
API_TOKEN=""
API_TOKEN_FILE=""
TOKEN_ARG=""

### 명령행 옵션 파싱 ###
for arg in "$@"; do
  case "$arg" in
    --zone-id=*)
      ZONE_ID="${arg#*=}"
      ;;
    --record-name=*)
      RECORD_NAME="${arg#*=}"
      ;;
    --api-token=*)
      API_TOKEN="${arg#*=}"
      ;;
    --api-token-file=*)
      API_TOKEN_FILE="${arg#*=}"
      ;;
    --log-level=*)
      LOG_LEVEL=$(echo "${arg#*=}" | tr '[:lower:]' '[:upper:]')
      ;;
    *)
      ;;    # 다른 인자값은 무시
  esac
done

### 필수 인자 유효성 검사 ###
if [ -z "$ZONE_ID" ] || [ -z "$RECORD_NAME" ]; then
  log_format ERROR "--zone, --record 인자는 필수입니다."
  echo "Usage: $0 --zone=<ZONE_ID> --record=<RECORD_NAME> (--api-token=TOKEN | --api-token-file=FILE)"
  exit 1
fi

if [ -n "$API_TOKEN" ] && [ -n "$API_TOKEN_FILE" ]; then
  log_format WARN "--api-token과 --api-token-file이 모두 제공되었습니다. --api-token을 우선 사용합니다."
  TOKEN_ARG=$(echo "$API_TOKEN" | tr -d '\r\n[:space:]')
elif [ -n "$API_TOKEN_FILE" ]; then
  if [ ! -f "$API_TOKEN_FILE" ] || [ ! -r "$API_TOKEN_FILE" ]; then
    log_format ERROR "API 토큰 파일이 존재하지 않거나 읽을 수 없습니다: $API_TOKEN_FILE"
    exit 1
  fi
  TOKEN_ARG=$(cat "$API_TOKEN_FILE" | tr -d '\r\n[:space:]')
elif [ -n "$API_TOKEN" ]; then
  TOKEN_ARG=$(echo "$API_TOKEN" | tr -d '\r\n[:space:]')
else
  log_format ERROR "--api-token 또는 --api-token-file 중 하나는 반드시 필요합니다."
  exit 1
fi

if [ -z "$TOKEN_ARG" ]; then
  log_format ERROR "API 토큰 값이 비어 있습니다."
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
  { log_format ERROR "외부 IP 조회 실패"; exit 1; }
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
  local record_id="$1" new_ip="$2" ttl="$3" proxied="$4"
  curl -fsS -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${record_id}" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"${RECORD_NAME}\",\"content\":\"${new_ip}\",\"ttl\":${ttl},\"proxied\":${proxied}}"
}

### 실행 시작 ###
log_format INFO "스크립트 시작: ZONE=${ZONE_ID}, RECORD=${RECORD_NAME}"

EXT_IP=$(get_external_ip)
log_format INFO "외부 IP: ${EXT_IP}"

RAW_JSON=$(fetch_record)

RECORD_ID=$(echo "$RAW_JSON" | jq -r '.result[0].id')
CURRENT_IP=$(echo "$RAW_JSON" | jq -r '.result[0].content')
CURRENT_TTL=$(echo "$RAW_JSON" | jq -r '.result[0].ttl')
CURRENT_PROXIED=$(echo "$RAW_JSON" | jq -r '.result[0].proxied')
log_format INFO "현재 DNS IP: ${CURRENT_IP} | 현재 TTL: ${CURRENT_TTL} | 현재 PROXIED: ${CURRENT_PROXIED}"

if [ "$EXT_IP" != "$CURRENT_IP" ]; then
  log_format INFO "IP 변경 감지: ${CURRENT_IP} → ${EXT_IP}"
  RESULT_JSON=$(update_record "$RECORD_ID" "$EXT_IP" "$CURRENT_TTL" "$CURRENT_PROXIED")
  SUCCESS=$(echo "$RESULT_JSON" | jq -r '.success')
  if [ "$SUCCESS" = "true" ]; then
    log_format INFO "DNS 레코드 업데이트 성공: ${EXT_IP}"
  else
    log_format ERROR "업데이트 실패: $RESULT_JSON"
    exit 1
  fi
else
  log_format INFO "IP 동일: 업데이트 불필요"
fi

log_format INFO "스크립트 종료"
