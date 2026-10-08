# AI응용 1조 팀과제 웹

StepUp English 회화 코치의 팀과제 전용 사이트다. 공개 화면에는 팀과제만 노출하며, 브라우저는 같은 출처의 Sites Worker API를 호출한다.

현재 화면은 대화를 첫 과업으로 배치하고, 자동 높이 입력창·Enter 전송·Shift+Enter 줄바꿈·600자 카운터·질문별 빈칸 예문·CEFR 진행 표시를 제공한다. 설정한 목표와 주제는 브라우저 메모리에서 첫 질문에만 반영하며 API·D1·로그에는 별도 프로필로 전송하거나 저장하지 않는다. 흐름 카드와 채팅 말풍선은 모바일부터 200% 확대까지 가로 잘림 없이 재배치되도록 구성했다.

```text
Part 1 프롬프트 → 팀과제 HTML 생성 → Worker 번들 생성 → Sites 배포
                                              ├─ Claude API
                                              └─ D1 사용량 원장
```

## 구조

- `index.html`: 생성된 팀과제 화면
- `worker-src/index.js`: 정적 파일 제공, `/api/health`, `/api/english-coach`
- `db/schema.ts`, `drizzle/`: D1 사용량·비용·속도 제한 스키마와 마이그레이션
- `scripts/build-worker.mjs`: HTML·매니페스트·서비스워커를 Worker 모듈에 포함
- `.openai/hosting.json`: Sites 프로젝트와 D1 바인딩 설정
- `supabase/`: 이전 대안 구현 보관본이며 현재 배포 경로에서는 사용하지 않음

## 생성과 로컬 정적 확인

```bash
/opt/anaconda3/bin/python ../01_구현관리/scripts/build_personal_assignments_html.py
npm run build
/opt/anaconda3/bin/python server.py --port 8765
```

로컬 `server.py`는 정적 화면 확인용이다. 실제 AI 응답과 D1은 Sites 배포 환경에서 동작한다.

## 서버 환경변수

아래 값은 Sites의 서버 환경변수로만 설정한다. `ANTHROPIC_API_KEY`와 `RATE_LIMIT_SALT`는 Secret이며 HTML, Git, 로그에 기록하지 않는다.

| 이름 | 기본/운영값 | 공개 여부 |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | Anthropic Console 키 | Secret |
| `RATE_LIMIT_SALT` | 32자 이상 무작위 값 | Secret |
| `ANTHROPIC_MODEL` | `claude-haiku-5-5` | 서버 전용 |
| `ANTHROPIC_MAX_OUTPUT_TOKENS` | `700` | 서버 전용 |
| `ANTHROPIC_CREDIT_USD` | `20` | 서버 전용 |
| `ANTHROPIC_DAILY_BUDGET_PERCENT` | `5` | 서버 전용 |
| `RATE_LIMIT_REQUESTS_PER_MINUTE` | `6` | 서버 전용 |

기본 일일 한도는 충전액 US$20의 5%인 **US$1/일**이다. 이 제한은 이 Worker를 통한 호출에만 적용되므로 같은 키를 다른 곳에서도 사용한다면 Anthropic Console의 Workspace 지출 한도도 별도로 설정한다.

## 개인정보·비용 보호

- 대화 본문, 이름, API 키, 원본 IP는 D1에 저장하지 않는다.
- `api_usage_daily`와 `api_usage_events`에는 날짜·모델·토큰·비용·상태만 저장한다.
- 원본 IP와 User-Agent는 비밀 Salt와 함께 SHA-256 해시로 바꿔 분당 6회 제한에만 사용한다.
- 요청 본문은 12KB, 대화는 14개 메시지, 메시지당 600자로 제한한다.
- 요청 전에 최대 예상 비용을 원장에 예약하고, 일일 예산을 넘으면 Claude를 호출하지 않는다.
- 네트워크 결과가 불확실한 호출과 15분 이상 미정산된 예약은 예상 비용 전액을 사용한 것으로 보수적으로 정산한다.
- 예산 원장이나 D1이 동작하지 않으면 호출을 중단한다(fail closed).
- CEFR 결과는 텍스트 기반 잠정 추정이며 공식 점수·진단·자격이 아니다.

## API

- `GET /api/health`: 키와 D1 연결 상태 확인
- `POST /api/english-coach`: 검증된 회화 메시지를 Claude에 전달하고 영어 답변·자연스러운 한국어 안내·질문별 빈칸 예문을 구조화해 반환

브라우저는 배포 도메인의 같은 출처 API만 사용한다. 서버는 Origin, 요청 크기, 메시지 역할·순서·길이, 수준·옵션 타입을 검증한다.

## 검증

```bash
node --check worker-src/index.js
npm run build
git diff --check
```

배포 후 `/api/health`가 `ok: true`를 반환하는지, 코치 API가 영어 응답·한국어 해석·잠정 수준을 반환하는지, D1 원장에 대화 내용 없이 사용량만 기록되는지 확인한다.
