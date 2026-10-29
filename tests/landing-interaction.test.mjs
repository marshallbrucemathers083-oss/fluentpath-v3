import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

test('preview selection is exclusive and keyboard focus does not select', async () => {
  let focused;
  const rows = Array.from({ length: 4 }, (_, index) => ({
    handlers: {}, pressed: 'false',
    addEventListener(type, callback) { this.handlers[type] = callback; },
    setAttribute(name, value) { if (name === 'aria-pressed') this.pressed = value; },
    focus() { focused = index; }
  }));
  const source = (await readFile(new URL('../js/landing.js', import.meta.url), 'utf8')).replace(/^import .*;\n/, '');
  vm.runInNewContext(source, {
    document: { querySelector: () => null, querySelectorAll: () => rows, addEventListener() {} },
    window: { matchMedia: () => ({ addEventListener() {} }) },
    reveal() {}, observeLearningMotion() {}, setMenu() {}
  });
  assert.ok(rows.every(row => row.pressed === 'false'));
  rows[1].handlers.click();
  assert.deepEqual(rows.map(row => row.pressed), ['false', 'true', 'false', 'false']);
  rows[3].handlers.click();
  assert.deepEqual(rows.map(row => row.pressed), ['false', 'false', 'false', 'true']);
  rows[3].handlers.keydown({ key: 'ArrowDown', preventDefault() {} });
  assert.equal(focused, 0);
  rows[0].handlers.keydown({ key: 'End', preventDefault() {} });
  assert.equal(focused, 3);
  rows[3].handlers.keydown({ key: 'Home', preventDefault() {} });
  assert.equal(focused, 0);
  assert.equal(rows[3].pressed, 'true');
});
