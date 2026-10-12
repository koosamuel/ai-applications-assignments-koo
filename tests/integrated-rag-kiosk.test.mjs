import test from "node:test";
import assert from "node:assert/strict";
import worker from "../dist/server/index.js";

async function post(message, { messages = [], cart = [] } = {}) {
  const response = await worker.fetch(new Request("https://example.test/api/rag-kiosk", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message, messages, cart }),
  }), {});
  return { response, body: await response.json() };
}

test("통합 서버 메뉴 API는 15개 메뉴와 옵션 가격을 제공한다", async () => {
  const response = await worker.fetch(new Request("https://example.test/api/menu"), {});
  const body = await response.json();
  assert.equal(body.menu.length, 15);
  assert.equal(body.option_prices["샷 추가"], 700);
  assert.equal(body.option_prices["오트밀크 변경"], 700);
});

test("통합 서버는 두 잔 주문 후 한 잔만 취소한다", async () => {
  const ordered = await post("아아 두 잔 주문할게요");
  assert.equal(ordered.body.cart[0].quantity, 2);
  assert.equal(ordered.body.cart_total, 9000);

  const cancelled = await post("1잔 취소", { cart: ordered.body.cart });
  assert.equal(cancelled.body.cart[0].quantity, 1);
  assert.equal(cancelled.body.cart_total, 4500);
});

test("통합 서버는 직전 사용자 주문의 옵션까지 복원한다", async () => {
  const { body } = await post("네 주문할게요", {
    messages: [
      { role: "user", content: "카페라떼 M 아이스에 샷 추가하고 오트밀크로 변경해줘" },
      { role: "assistant", content: "카페라떼 M 아이스를 주문하시겠어요?" },
    ],
  });
  assert.equal(body.order_completed, true);
  assert.equal(body.cart[0].unit_price, 6600);
  assert.equal(body.cart_total, 6600);
});

test("통합 서버 식사 페어링은 실제 메뉴의 이유와 가격을 제공한다", async () => {
  const { body } = await post("치킨과 어울리는 음료를 추천해줘");
  assert.match(body.answer, /유자차/);
  assert.match(body.answer, /4,500원/);
  assert.ok(body.retrieved.every((row) => row.price_label));
});
