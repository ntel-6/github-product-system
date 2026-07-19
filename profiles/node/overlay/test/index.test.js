import assert from "node:assert/strict";
import test from "node:test";

import { health } from "../src/index.js";

test("health reports readiness", () => {
  assert.deepEqual(health(), { ok: true });
});
