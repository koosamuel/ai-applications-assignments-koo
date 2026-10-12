import test from "node:test";
import assert from "node:assert/strict";
import worker from "../src/worker.js";

const assets = { fetch: () => new Response("not found", { status: 404 }) };

async function post(message, { messages = [], cart = [], env = {} } = {}) {
  const request = new Request("https://example.test/api/rag-kiosk", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message, messages, cart }),
  });
  const response = await worker.fetch(request, { ASSETS: assets, ...env });
  return { response, body: await response.json() };
}

test("식사 페어링은 판매 메뉴의 이유와 가격을 함께 제시한다", async () => {
  const { response, body } = await post("샌드위치와 어울리는 음료를 추천해줘");
  assert.equal(response.status, 200);
  assert.match(body.answer, /아메리카노 \(S 4,000원 \/ M 4,500원 \/ L 5,000원\)/);
  assert.match(body.answer, /풍미를 정리/);
});

test("아아 두 잔 주문 뒤 한 잔 취소 시 수량과 합계가 감소한다", async () => {
  const first = await post("아아 두 잔 주문할게요");
  assert.equal(first.body.cart[0].item_id, "americano");
  assert.equal(first.body.cart[0].temperature, "ice");
  assert.equal(first.body.cart[0].size, "M");
  assert.equal(first.body.cart[0].quantity, 2);
  assert.equal(first.body.cart_total, 9000);

  const second = await post("1잔 취소", { cart: first.body.cart });
  assert.equal(second.body.cart[0].quantity, 1);
  assert.equal(second.body.cart_total, 4500);
  assert.match(second.body.answer, /1잔을 취소/);
});

test("샷과 오트밀크가 포함된 카페라떼 단가는 서버가 6,600원으로 계산한다", async () => {
  const { body } = await post("카페라떼 M 아이스에 샷 추가하고 오트밀크 변경해서 1잔 주문할게요");
  assert.equal(body.cart[0].unit_price, 6600);
  assert.equal(body.cart_total, 6600);
  assert.match(body.answer, /6,600원/);
});

test("짧은 주문 확인은 장바구니를 확정하고 추가 질문을 반복하지 않는다", async () => {
  const initial = await post("아아 한 잔 주문해줘");
  const confirmed = await post("네", { cart: initial.body.cart });
  assert.equal(confirmed.body.order_completed, true);
  assert.equal(confirmed.body.cart_total, 4500);
  assert.match(confirmed.body.answer, /주문을 확정/);
});

test("빈 장바구니에서도 직전 사용자 메뉴와 옵션을 복원해 주문한다", async () => {
  const { body } = await post("네 주문할게요", {
    messages: [
      { role: "user", content: "아이스 카페라떼 M에 샷 추가와 오트밀크 변경으로 추천해줘" },
      { role: "assistant", content: "카페라떼 M 아이스를 주문하시겠어요?" },
    ],
  });
  assert.equal(body.order_completed, true);
  assert.equal(body.cart[0].unit_price, 6600);
  assert.match(body.answer, /주문을 확정/);
});

test("둘 다 같은 짧은 답은 직전 대화와 합쳐 RAG 검색한다", async () => {
  const originalFetch = globalThis.fetch;
  let providerPrompt = null;
  globalThis.fetch = async (_url, options) => {
    providerPrompt = JSON.parse(options.body);
    return new Response(JSON.stringify({
      content: [{ type: "text", text: JSON.stringify({
        answer: "두 메뉴를 함께 비교했습니다.",
        intent: "compare",
        cited_menu_ids: ["americano", "cappuccino"],
        cart_operation: "none",
        cart_item: { item_id: "americano", size: "M", temperature: "ice", options: [], quantity: 1 },
      }) }],
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  };
  try {
    const { body } = await post("둘 다", {
      messages: [{ role: "user", content: "아메리카노와 카푸치노 가격을 알려줘" }],
      env: { ANTHROPIC_API_KEY: "test-key" },
    });
    assert.deepEqual(body.retrieved.slice(0, 2).map((row) => row.id).sort(), ["americano", "cappuccino"]);
    const prompt = JSON.parse(providerPrompt.messages[0].content);
    assert.equal(prompt.user_request, "둘 다");
    assert.equal(prompt.recent_conversation[0].content, "아메리카노와 카푸치노 가격을 알려줘");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("전체 메뉴 API는 15개 메뉴와 옵션 추가금을 반환한다", async () => {
  const response = await worker.fetch(new Request("https://example.test/api/menu"), { ASSETS: assets });
  const body = await response.json();
  assert.equal(body.menu.length, 15);
  assert.equal(body.option_prices["샷 추가"], 700);
  assert.equal(body.option_prices["오트밀크 변경"], 700);
});
