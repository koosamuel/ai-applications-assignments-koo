# RAG 카페 Kiosk · 구범용

통합 과제 사이트에서 **RAG 카페 키오스크 기능만 분리한 제출용 코드**입니다. 메뉴 문서를 검색한 뒤 검색 결과만 근거로 설명·추천·비교하고, 서버에서 옵션을 검증해 장바구니를 갱신합니다. 샌드위치·샐러드·파스타·치킨은 판매 메뉴가 아닌 식사 조건으로 해석하여 실제 판매 중인 음료만 추천합니다.

## 운영 주소

- [RAG 카페 Kiosk 실행](https://ai-applications-assignments-koo.koosamuel1.chatgpt.site/?v=22#ragkiosk/results)
- [피드백 반영 기록](https://ai-applications-assignments-koo.koosamuel1.chatgpt.site/?v=22#ragkiosk/feedback)

운영 화면은 같은 배포 도메인의 `/api/rag-kiosk`를 호출합니다. 서버 코드는 `src/worker.js`에 있으며, 실제 Claude API 키는 GitHub에 저장하지 않고 서버 환경변수로만 주입합니다. GitHub Pages 단독으로는 Worker API와 비밀키를 실행할 수 없습니다.

## 포함 파일

- `notebook/팀과제_RAG_카페_Kiosk_구범용.ipynb`: 최종 실행 노트북
- `public/index.html`: 단독 키오스크 화면과 브라우저 상태 관리
- `src/worker.js`: 메뉴 검색, Claude 호출, 주문 검증 API
- `wrangler.toml`: Cloudflare Worker 및 정적 파일 설정
- `.dev.vars.example`: 비밀키 값이 비어 있는 환경변수 예시

Claude API 키, 개인 경로, 실행 캐시, 다른 실습 코드는 포함하지 않았습니다.

## 주요 구현

1. 15개 메뉴 문서를 문자 2-gram으로 검색합니다.
2. 검색 결과와 최근 대화, 현재 장바구니만 Claude에 전달합니다.
3. JSON Schema로 응답 형식을 고정합니다.
4. 설명·추천·비교·주문·재질문·범위 밖 요청을 구분합니다.
5. 메뉴 ID, 사이즈, 온도, 옵션, 수량과 가격을 서버에서 다시 검증합니다.
6. 브라우저에는 API 키를 전달하지 않습니다.
7. `네`, `둘 다`, `그걸로` 같은 짧은 답변은 최근 사용자 대화와 결합해 메뉴 문맥을 유지합니다.
8. 동일 옵션 주문은 수량을 합치고, 일부 취소는 해당 수량만 차감한 뒤 총액을 다시 계산합니다.
9. 전체 메뉴판과 옵션 가격을 처음부터 표시하고, 추천에는 이유와 사이즈별 가격을 함께 제공합니다.
10. 이름과 내용만 입력하는 피드백 검토창을 제공하며 상태 이력과 JSON·CSV·Markdown 로그를 브라우저에 저장합니다.

## 로컬 실행

Node.js가 설치된 환경에서 다음 순서로 실행합니다.

```bash
npm install
cp .dev.vars.example .dev.vars
```

`.dev.vars` 파일의 `ANTHROPIC_API_KEY=` 오른쪽에 개인 키를 입력한 뒤 실행합니다.

```bash
npm run dev
```

화면에 표시되는 로컬 주소를 브라우저에서 엽니다. 회귀 테스트와 코드 문법 검사는 다음 명령으로 실행합니다.

```bash
npm test
npm run check
```

회귀 테스트는 식사 페어링, 2잔 주문 후 1잔 취소, 옵션 포함 6,600원 계산, 짧은 확인 응답의 주문 확정, 직전 사용자 메뉴 복원, 대화 문맥 검색, 15개 메뉴 API를 확인합니다.

## 배포

Cloudflare 계정에 로그인한 뒤 비밀키를 서버 측 secret으로 등록합니다.

```bash
npx wrangler secret put ANTHROPIC_API_KEY
npm run deploy
```

실제 키는 `.dev.vars`, `.env`, 소스 코드 또는 압축파일에 넣지 않습니다.

## API

### `GET /api/health`

서버 실행 여부, Claude 키 설정 여부, 메뉴 문서 수를 반환합니다.

### `POST /api/rag-kiosk`

요청 예시:

```json
{
  "message": "카페라떼 M 아이스에 바닐라 시럽 추가해서 1잔 주문할게.",
  "messages": [],
  "cart": []
}
```

응답에는 자연어 답변, 분류된 의도, 검색된 메뉴 근거, 검증된 장바구니와 합계가 포함됩니다.

### `GET /api/menu`

전체 15개 메뉴, 사이즈별 가격, 옵션 추가금을 반환합니다. 화면의 전체 메뉴판과 서버 검증 데이터는 같은 카탈로그를 기준으로 합니다.

## HTI 검증 범위

| HTI 상위 과업 | 대표 과업 | 검증 예시 |
| --- | --- | --- |
| 탐색 | 설명·가격·사이즈·옵션 | 아메리카노 사이즈별 가격 |
| 추천 | 맛·카페인·식이 제한·식사 페어링 | 샌드위치와 어울리는 판매 음료 추천 |
| 비교 | 맛·가격·카페인 | 아메리카노와 카푸치노 비교 |
| 주문 | 추가·변경·삭제·합계 | 라떼 M 아이스, 바닐라 시럽 |
| 복구 | 재질문·없는 옵션·범위 밖 | 유자차에 샷 추가 |

`HTI`는 `Hierarchical Task Inventory`, 즉 계층적 과업 목록을 뜻합니다.
