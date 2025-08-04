## 참고 사항

1. ipv4만 지원 (A 레코드)
2. curl, jq 설치 필요
3. Debian 계열 및 Alpine Linux 에서 테스트 완료

## 사용법

### 스크립트 다운로드

```bash
curl -fsSL https://raw.githubusercontent.com/JiHongKim98/easy-cloudflare-ddns/refs/heads/main/easy-cloudflare-ddns.sh -o easy-cloudflare-ddns.sh
```

### 스크립트 실행 방법

`--api-token` 과 `--api-token-file` 이 모두 주어질때 `--api-token` 값만 사용합니다.<br/>
즉, `--api-token-file` 값은 무시되니 둘중 하나만 사용하는 것을 권장합니다. <br/>

자세한 로그 정보가 필요하다면, 로그 레벨을 `debug`로 설정하여 스크립트를 실행합니다. <br/>
기본 로그 레벨은 `info` 이며, `info` 레벨에서는 ip가 변경될때만 로그를 남깁니다.

cron 스케쥴러에 등록하여 주기적으로 동작하도록 설정하여 사용하는 것을 권장합니다.

```bash
# --zone-id : cloudflare 의 zone id (영역 id)
# --record-name : 적용할 DNS 레코드 이름
# --api-token : cloudflare API 토큰 값
# --api-token-file : cloudflare API 토큰 값이 있는 파일 경로
# --log-level : 로그 수준 (debug, info, warn, error), 기본값 info
sh easy-cloudflare-ddns.sh \
  --zone-id=1q2w3e4r5t6y7u8i9o0p \
  --record-name=test.example.com \
  --api-token=1234567890abcdefgh \
  --log-level=info
```

### 실행 로그 보기

```bash
tail -n 50 /var/log/easy-cloudflare-ddns.log
```

## TODO

- [ ] README에 가독성 개선
- [ ] README에 cloudflare 설정부터 cron 스케쥴러까지 자세한 설명 추가
- [ ] README 영문 추가
- [ ] setup 스크립트 추가
