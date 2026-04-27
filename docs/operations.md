# 운영 매뉴얼

배포·롤백·환경변수 관리·문제 대응 절차.
시스템 전체 구조는 [architecture.md](architecture.md) 참고.

---

## 외부 계정 / 서비스 한 곳 정리

| 서비스 | URL | 가입 계정 | 역할 |
|--------|-----|-----------|------|
| **GitHub** | https://github.com/airflex25/wktk | `airflex25` | 코드 저장소 + Pages |
| **Render** | https://dashboard.render.com | airflex25@gmail.com | 시그널링 서버 호스팅 |
| **Cloudflare** | https://dash.cloudflare.com | airflex25@gmail.com | TURN 서버 |
| **Google Play Console** | https://play.google.com/console | airflex25@gmail.com | Android 앱 배포 |
| **Apple Developer** | (미가입) | (예정) | iOS 앱 배포 |

---

## 시그널링 서버

### Render 서비스 정보
- **이름**: `wktk-signaling`
- **URL**: https://wktk-signaling.onrender.com
- **플랜**: Free
- **빌드 명령**: `npm install`
- **시작 명령**: `npm start`
- **루트 디렉토리**: `server/`
- **자동 배포**: GitHub `master` 브랜치 push 시 트리거 (`render.yaml` Blueprint)

### 환경 변수
Render Dashboard → wktk-signaling → Environment 메뉴에서 관리.

| Key | 값 | 비고 |
|-----|----|------|
| `CF_TURN_KEY_ID` | (Render env에 설정) | Cloudflare TURN Key ID |
| `CF_TURN_API_TOKEN` | (Render env에 설정) | Cloudflare App Token. 노출 시 즉시 회전 |
| `TURN_TTL` | `3600` (옵션) | TURN 자격증명 TTL (초) |
| `ROOM_LIMIT` | `8` (옵션) | 한 룸 최대 인원 |
| `CORS_ORIGIN` | `*` (옵션) | Socket.IO CORS |

> 실제 값은 Render Dashboard 의 **Environment** 탭에만 보관. 문서·git·채팅에 절대 적지 않음.

> 환경변수 변경 후 Render가 **자동 재배포**합니다 (1-2분 소요).

### 헬스체크
```bash
curl https://wktk-signaling.onrender.com/health
# {"ok":true,"ts":...}

curl https://wktk-signaling.onrender.com/turn-credentials
# {"iceServers":{"urls":[...turn.cloudflare.com...],"username":"...","credential":"..."}}
```

응답 안 오면 **15분 idle 후 sleep** 상태일 수 있음. 위 curl 한 번 치면 재기동 시작 (~30초 cold start).

### 로그 확인
Render Dashboard → wktk-signaling → **Logs** 탭. 실시간 streaming.

주요 로그 패턴:
- `[wktk] signaling listening on :3000` — 정상 부팅
- `[wktk] connect <peerId>` — 새 클라이언트 접속
- `[wktk] disconnect <peerId>` — 클라이언트 종료
- `[wktk] TURN cred error: ...` — Cloudflare API 호출 실패

### 수동 재배포
```
Render Dashboard → wktk-signaling → Manual Deploy → Deploy latest commit
```

또는 더미 커밋:
```bash
git commit --allow-empty -m "redeploy"
git push
```

### 롤백
이전 커밋으로 되돌리려면:
```bash
git revert <commit-sha>
git push
# Render 자동 재배포
```

또는 Render Dashboard → **Deploys** 탭 → 이전 성공 빌드의 **Rollback** 버튼.

---

## TURN 서버 (Cloudflare Realtime)

### 앱 정보
- **이름**: `withered-firefly-1ce8` (변경 불필요, 단순 라벨)
- **Key ID / App Token**: Render env (`CF_TURN_KEY_ID`, `CF_TURN_API_TOKEN`) 에만 보관

### 사용량 확인
1. https://dash.cloudflare.com 접속
2. **Realtime** 메뉴 → **Analytics**
3. 월별 GB 사용량 / 1TB 한도 대비 표시

1TB 가까워지면 알림 설정 권장 (Account Home → Notifications).

### 토큰 회전 (중요)
토큰이 노출되거나 정기 회전 시:

1. Cloudflare Dashboard → Realtime → **TURN Keys**
2. **새 Key 생성** → 새 Key ID + API Token 발급
3. Render 환경변수 `CF_TURN_KEY_ID`, `CF_TURN_API_TOKEN` 갱신
4. Render 자동 재배포 후 `/turn-credentials` 정상 동작 확인
5. 옛 Key **삭제 (Revoke)**

> 옛 Key 즉시 삭제하면 진행 중 통화의 TURN 연결이 끊길 수 있어요. 가능하면 새 Key 활성화 후 30분~1시간 텀 두고 옛 Key 삭제.

---

## GitHub Pages (개인정보처리방침)

### URL
- https://airflex25.github.io/wktk/privacy.html

### 갱신
1. `docs/privacy.html` 편집
2. `git push`
3. 1-2분 후 자동 반영

### 활성화 상태 확인
- https://github.com/airflex25/wktk/settings/pages
- Source: master / `/docs`

---

## 모바일 앱 빌드 + 배포

### 버전 관리
`mobile/pubspec.yaml`:
```yaml
version: 1.0.0+1
```
- `1.0.0` = 사용자에게 보이는 버전 (versionName / CFBundleShortVersionString)
- `+1` = 빌드 번호 (versionCode / CFBundleVersion)

새 빌드 올릴 때마다 **빌드 번호(+N)는 반드시 증가**해야 Play Store가 받음.

### Android 빌드

```bash
cd mobile
flutter pub get

# Play Store 업로드용 (AAB)
flutter build appbundle --release

# 직접 공유용 (APK, ABI별 분리)
flutter build apk --release --split-per-abi

# 디버그 (개발 시)
flutter build apk --debug
```

산출물:
- `mobile/build/app/outputs/bundle/release/app-release.aab` (~53MB)
- `mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (~28MB)
- `mobile/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` (~21MB)
- `mobile/build/app/outputs/flutter-apk/app-x86_64-release.apk` (~31MB)

### 버전 보관
빌드 후 [`releases/`](../releases/) 폴더에 버전별로 복사. 자세한 절차: [releases/README.md](../releases/README.md).

### 키스토어 (Android 서명)
- 위치: `~/keystores/okidoki-release.jks`
- 비밀번호 파일: `mobile/android/key.properties` (gitignored)
- **백업 필수**: 1Password / 외부 USB / 안전한 클라우드. **잃어버리면 같은 패키지명으로 업데이트 영영 불가.**

### Google Play Console 업로드
1. https://play.google.com/console
2. **오키도키** 앱 선택
3. **출시 → 테스트 → 내부 테스트** (또는 폐쇄/정식)
4. **새 버전 만들기** → AAB 업로드
5. **출시 노트** 입력 (한국어 ko-KR)
6. **저장 → 검토 → 출시**

검토 시간: 첫 등록 1-3일, 이후 업데이트 보통 몇 시간.

### iOS 빌드
```bash
cd mobile
flutter build ipa --release
```

산출물: `mobile/build/ios/ipa/오키도키.ipa`

App Store Connect 업로드는 **Transporter.app** 또는 Xcode Archive 메뉴 사용.

(Apple Developer Program $99/년 가입 필요)

---

## 흔한 문제 + 대응

### Q. 사용자가 "연결 안 됨"으로 신고
1. Render `/health` 확인 → 서버 사망 가능성
2. Render `/turn-credentials` 확인 → Cloudflare API 토큰 유효 확인
3. Render Logs 에서 해당 시각 connection 패턴 확인
4. 두 사용자 페어링 시도 시각 비교 → 같은 키 들어왔는지

### Q. "음성이 안 들려요"
일반적인 원인:
- 시뮬레이터 (iOS Simulator는 audio I/O 미지원)
- 같은 공간 다중 폰 + VOX 모드 (피드백)
- NAT 뚫기 실패 (TURN 미작동) — `/turn-credentials` 응답 확인

### Q. Render 무료 티어 한도 초과
1TB/월 (서버 부담 거의 없으니 이 한도 거의 도달 안 함). 도달하면:
- Starter 플랜 ($7/월) 으로 업그레이드
- 또는 Fly.io / DigitalOcean / Hetzner VPS 로 이전

### Q. Cloudflare TURN 1TB 초과
GB당 $0.05 자동 청구. 모니터링:
- Cloudflare Dashboard → Realtime → Analytics
- 천 명 동시 사용자라도 보통 50-200GB/월 수준 (대부분 직접 P2P)

### Q. 패키지명 변경이 필요한 경우
- Android: `mobile/android/app/build.gradle.kts` 의 `applicationId` + `namespace` + `mobile/android/app/src/main/kotlin/.../MainActivity.kt` 패키지 경로
- iOS: `mobile/ios/Runner.xcodeproj/project.pbxproj` 의 `PRODUCT_BUNDLE_IDENTIFIER`

> 한 번 출시한 후엔 **같은 패키지로만 업데이트 가능**. 패키지 바꾸면 새 앱으로 처음부터 등록.

### Q. APK 용량 너무 큼
- 디버그 빌드 (~186MB) → 릴리즈 + ABI 분리 빌드 (~27MB)
- Tree-shaking, R8/ProGuard, 리소스 압축은 릴리즈 빌드에서 자동 적용

---

## 백업 체크리스트

분실하면 큰일 나는 것들:

- [ ] **Android keystore** (`~/keystores/okidoki-release.jks`) + 비밀번호
- [ ] **Cloudflare API Token** (회전 시 새 토큰 즉시 어딘가에 저장)
- [ ] **Apple Developer 인증서** (가입 후 발급되는 .p12 파일)
- [ ] **Google Play Developer 계정 비밀번호**
- [ ] **Render 계정 비밀번호** (또는 GitHub OAuth로 들어가니 GitHub만 지키면 됨)

권장 백업처: 1Password / Bitwarden / 외부 암호화 USB.
