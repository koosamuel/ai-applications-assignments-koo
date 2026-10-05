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
