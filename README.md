# 오키도키 (Okidoki)

6자리 키 하나로 친구와 즉시 워키토키 통화. 가입·광고·추적 없음.

WebRTC 기반 P2P 음성 통화. 시그널링 서버는 단지 짝짓기 역할만.

## 구성

| 폴더 | 역할 | 스택 |
|------|------|------|
| `mobile/` | Flutter 앱 (Android + iOS) | Flutter, flutter_webrtc, socket_io_client |
| `server/` | 키 매칭 + 시그널링 + TURN 자격증명 발급 | Node.js, Socket.IO |
| `docs/` | 아키텍처/프로토콜/운영 매뉴얼/개인정보처리방침 | Markdown + HTML |
| `releases/` | 버전별 빌드 산출물 보관 | AAB / APK |
| `android/` | (legacy) 초기 네이티브 Kotlin 안드로이드 — 참고용 | Kotlin, Compose |

> 모바일 앱은 `mobile/`(Flutter) 하나로 통합. 옛 `android/`(Kotlin) 폴더는 참고용으로만 남김.

## 핵심 설계 원칙

1. **서버는 가볍다** — 키 매칭 + SDP/ICE 중계 + TURN credential 발급만. 음성은 절대 통과 X.
2. **6자리 키 = 주파수** — `000000`~`999999`. 룸은 메모리, 빠짐과 동시에 사라짐.
3. **두 가지 대화 모드** — PTT (눌러서 송신) / VOX (항상 켜기).
4. **로그인·계정 없음** — 키만 알면 들어감. 익명 통신.
5. **개인정보 최소** — 음성 녹음 X, 광고 ID X, 분석 도구 X.

## 문서

| 파일 | 설명 |
|------|------|
| **[docs/architecture.md](docs/architecture.md)** | 시스템 전체 구성도, 컴포넌트, 통신 흐름, 비용 |
| **[docs/operations.md](docs/operations.md)** | 배포·재배포·환경변수·롤백·문제대응·백업 |
| [docs/protocol.md](docs/protocol.md) | Socket.IO 시그널링 이벤트 사양 |
| [docs/store-description.md](docs/store-description.md) | Play Store 등록 텍스트 |
| [docs/privacy.html](docs/privacy.html) | 개인정보처리방침 (GitHub Pages 배포) |
| [releases/README.md](releases/README.md) | 빌드 산출물 버전 관리 |

## 외부 인프라

| 서비스 | URL | 용도 |
|--------|-----|------|
| **GitHub** | github.com/airflex25/wktk | 코드 + GitHub Pages |
| **Render** | wktk-signaling.onrender.com | 시그널링 서버 호스팅 (Node.js) |
| **Cloudflare Realtime** | dash.cloudflare.com | TURN 서비스 (1TB/월 무료) |
| **Google Play Console** | play.google.com/console | Android 배포 |

자세한 외부 인프라 설정은 [docs/operations.md](docs/operations.md) 참고.

## 빠른 빌드

```bash
cd mobile

# Play Store 업로드용 (AAB)
flutter build appbundle --release

# 직접 공유용 (APK, ABI별)
flutter build apk --release --split-per-abi

# 개발 / 테스트
flutter run -d <device-id>
```

빌드 산출물은 [releases/](releases/)에 버전별로 보관. 자세한 절차: [releases/README.md](releases/README.md).
