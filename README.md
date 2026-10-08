# AI응용 개인·팀과제 통합 웹

공훈의 교수님 어린이 작가 프로젝트와 같은 정적 배포 구조를 사용한다.

```text
원본 과제 결과 → 통합 HTML 생성 → dist 정적 빌드 → 로컬 Python HTTP 서버 / Sites
```

## 어린이 작가 프로젝트와의 관계

- 정적 HTML → `dist` → Python 로컬 서버 / Sites 배포 흐름은 동일하다.
- Supabase 프로젝트는 어린이 작가 프로젝트와 공유하지 않고 별도로 생성한다.
- Supabase에는 공개 가능한 과제별 상태·요약·대표 지표만 저장한다.
- 고객 원본 정보, API 키, 노트북 전체 코드와 로컬 경로는 데이터베이스에 저장하지 않는다.
- 서비스워커는 HTML과 매니페스트를 캐시하고 네트워크 장애 시 정적 스냅샷을 표시한다.
- CSS, JavaScript와 과제 이미지는 `index.html`에 포함한다.

## 생성과 실행

```bash
/opt/anaconda3/bin/python ../01_구현관리/scripts/build_personal_assignments_html.py
./scripts/build-static.sh
/opt/anaconda3/bin/python server.py --port 8765
```

브라우저에서 `http://127.0.0.1:8765`를 연다.

## 전용 Supabase 프로젝트 연결

1. Supabase Dashboard에서 이 사이트 전용 프로젝트를 새로 만든다.
2. SQL Editor에서 `supabase/schema.sql`을 실행한다.
3. Project Settings의 Project URL과 Publishable Key를 환경변수로 지정한다.

```bash
export SUPABASE_URL="https://YOUR_PROJECT.supabase.co"
export SUPABASE_PUBLISHABLE_KEY="YOUR_PUBLIC_PUBLISHABLE_KEY"
```

4. 통합 HTML과 `dist`를 다시 생성한다.

```bash
/opt/anaconda3/bin/python ../01_구현관리/scripts/build_personal_assignments_html.py
./scripts/build-static.sh
```

5. 편집 권한이 필요하면 Supabase Auth에서 운영자 사용자를 만든 뒤 SQL Editor에서 해당 사용자 UUID를 등록한다.

```sql
insert into public.assignment_editors (user_id)
values ('운영자-auth-user-uuid');
```

Publishable Key는 브라우저 공개용 키다. 데이터베이스 비밀번호와 Secret/Service Role Key는 HTML, 저장소와 환경변수 빌드에 넣지 않는다.

## Realtime과 오프라인 동작

- 설정값이 없거나 연결에 실패하면 HTML에 포함된 정적 실행 결과를 그대로 표시한다.
- 연결되면 `assignment_sections`의 공개 행을 읽고 변경 사항을 Realtime으로 반영한다.
- 쓰기는 `assignment_editors`에 등록된 인증 사용자만 RLS를 통과한다.
- 서비스워커는 동일 출처의 앱 셸을 캐시하고, Supabase·CDN 요청은 네트워크에서 처리한다.

## 팀과제 대화형 챗봇

- Supabase 연결 전에는 팀과제 탭에서 로컬 규칙 기반 데모 코치가 입력에 응답한다.
- 연결 후에는 `supabase/functions/english-coach`가 Claude Messages API를 호출한다.
- 한국어 입력 자동 변환을 켜면 원문 아래에 영어 변환문을 표시하고, 영어 코치 답변 아래에는 한국어 해석을 표시한다.
- 서버는 Claude Structured Outputs로 `translated_input_en`, `reply_en`, `reply_ko`, `evidence`를 반환한다.
- Anthropic API 키는 브라우저나 Git에 넣지 않고 Edge Function Secret으로만 설정한다.
- 대화 본문은 기본적으로 데이터베이스에 저장하지 않는다.
- `api_usage_daily`와 `api_usage_events`에는 날짜·모델·토큰·비용만 기록하며 프롬프트, 응답, 이름과 API 키는 저장하지 않는다.
- 함수는 `@supabase/server`로 Publishable Key를 확인하고, 허용 Origin·12KB 요청 크기·8개 메시지·역할 순서를 검증한다.
- 원본 IP는 저장하지 않고 비밀 Salt로 만든 SHA-256 해시만 분당 호출 제한에 사용한다. 기본값은 클라이언트당 분당 6회다.
- 기본 예산은 충전액 US$20의 5%인 **US$1/일**이다. 동시 요청도 호출 전에 비용을 예약하며, 한도 초과 시 Claude를 호출하지 않고 HTTP 429를 반환한다.
- 15분 이상 정산되지 않은 예약은 다음 요청 시 보수적으로 예상 비용 전액을 사용한 것으로 정산해 예약 잠금을 해제한다.
- 예산 원장이나 정산이 동작하지 않으면 비용 보호를 위해 호출을 중단한다(fail closed).

Supabase CLI에서 전용 프로젝트를 연결한 뒤 아래 순서로 배포한다.

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set ANTHROPIC_API_KEY=YOUR_ANTHROPIC_API_KEY
supabase secrets set ANTHROPIC_MODEL=claude-haiku-5-5
supabase secrets set ANTHROPIC_MAX_OUTPUT_TOKENS=700
supabase secrets set ANTHROPIC_CREDIT_USD=20
supabase secrets set ANTHROPIC_DAILY_BUDGET_PERCENT=5
supabase secrets set ANTHROPIC_USAGE_TIMEZONE=Asia/Seoul
supabase secrets set RATE_LIMIT_REQUESTS_PER_MINUTE=6
supabase secrets set ALLOWED_ORIGINS=https://ai-applications-assignments-koo.koosamuel1.chatgpt.site
supabase functions deploy english-coach
```

`YOUR_ANTHROPIC_API_KEY`는 문서·HTML·셸 기록에 남기지 말고 안전한 로컬 환경에서 직접 입력한다. `SUPABASE_SERVICE_ROLE_KEY`는 Edge Function의 서버 측 내장 Secret으로만 읽으며 웹 빌드 환경에는 넣지 않는다.
로컬 키 메모 파일은 Edge Function에 자동 전송되지 않으며 파일명·경로·내용을 Git·Sites 배포물에 포함하지 않는다.

`RATE_LIMIT_SALT`는 32자 이상의 무작위 값을 Supabase Dashboard의 Edge Function Secret으로 직접 등록한다. 값 자체는 문서·셸 기록·브라우저 환경변수에 남기지 않는다. `supabase/config.toml`의 `verify_jwt=false`는 공개 웹 호출을 위한 설정이며, 함수 내부에서 Publishable Key를 다시 확인한다.

운영 중 집계는 Supabase SQL Editor에서 서버 권한으로 확인한다. 아래 조회는 대화 내용을 반환하지 않는다.

```sql
select
  usage_date,
  request_count,
  spent_microusd / 1000000.0 as spent_usd,
  daily_limit_microusd / 1000000.0 as daily_limit_usd,
  input_tokens,
  output_tokens
from public.api_usage_daily
order by usage_date desc;
```

이 일일 제한은 이 Edge Function을 통과한 호출에 적용된다. 같은 Anthropic 키를 다른 스크립트나 서비스에서 직접 사용한 비용까지 차단하려면 Anthropic Console의 Workspace 지출 한도도 별도로 설정한다.
