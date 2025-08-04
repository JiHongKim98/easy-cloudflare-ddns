#!/usr/bin/env bash
set -euo pipefail

### 로그 파일 설정 ###
LOG_FILES="/var/log/easy-cloudflare-ddns.log"
# 로그 파일 초기 설정
touch "$LOG_FILES"
chmod 644 "$LOG_FILES"
# stdout/stderr를 로그에 append
exec >>"$LOG_FILES" 2>&1

### 사용법 안내 ###
usage() {
  cat <<EOF
Usage: $0 <ZONE_ID> <RECORD_NAME> <API_TOKEN_FILE>
  ZONE_ID           Cloudflare Zone ID
  RECORD_NAME       갱신할 DNS 레코드 이름 (예: test.example.com)
  API_TOKEN_FILE    API 토큰이 저장된 파일 경로
EOF
  exit 1
}

#### 인자 개수 체크 ###
if [ $# -ne 3 ]; then
  echo "[ERROR] 인자가 부족합니다."
  usage
fi

ZONE_ID="$1"
RECORD_NAME="$2"
TOKEN_FILE="$3"

### 토큰 파일 유효성 검사 ###
if [ ! -r "$TOKEN_FILE" ]; then
  echo "[ERROR] API 토큰 파일을 읽을 수 없습니다: $TOKEN_FILE"
  exit 1
fi
API_TOKEN=$(cat "$TOKEN_FILE")

### 외부 IP 조회 ###
get_external_ip() {
  local ip
  # 주요 서비스 순으로 시도
  ip=$(curl -fsS https://ifconfig.me/ip)    || \
  ip=$(curl -fsS https://ifconfig.co/ip)    || \
  ip=$(curl -fsS https://api.ipify.org)     || \
  { echo "[ERROR] 외부 IP 조회 실패"; exit 1; }
}

### DNS 레코드 목록 조회 ###
fetch_record() {
  curl -fsS -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${RECORD_NAME}" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json"
}

### DNS 레코드 업데이트 ###
update_record() {
  local record_id="$1" new_ip="$2"
  curl -fsS -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${record_id}" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"${RECORD_NAME}\",\"content\":\"${new_ip}\",\"ttl\":120,\"proxied\":false}"
}

### 메인 스크립트 ###
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 스크립트 시작: ZONE=${ZONE_ID}, RECORD=${RECORD_NAME}"

EXT_IP=$(get_external_ip)
echo "외부 IP: ${EXT_IP}"

# 조회 후 JSON 파싱
RAW_JSON=$(fetch_record)

RECORD_ID=$(echo "$RAW_JSON" | jq -r '.result[0].id')
CURRENT_IP=$(echo "$RAW_JSON" | jq -r '.result[0].content')
echo "현재 DNS IP: ${CURRENT_IP}"

if [ "$EXT_IP" != "$CURRENT_IP" ]; then
  echo "IP 변경 감지: ${CURRENT_IP} → ${EXT_IP}"
  RESULT_JSON=$(update_record "$RECORD_ID" "$EXT_IP")
  SUCCESS=$(echo "$RESULT_JSON" | jq -r '.success')
  if [ "$SUCCESS" = "true" ]; then
    echo "DNS 레코드 업데이트 성공: ${EXT_IP}"
  else
    echo "[ERROR] 업데이트 실패: $RESULT_JSON"
    exit 1
  fi
else
  echo "IP 동일: 업데이트 불필요"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 스크립트 종료"
