import test from 'node:test';
import assert from 'node:assert/strict';
import { createAnswerQueue, parseFeedback } from '../js/answer-state.js';

test('correct and incorrect RPC feedback remains boolean for every objective exercise style', () => {
  for (const type of ['multiple_choice', 'fill_blank', 'reading_comprehension', 'listening']) {
    for (const correct of [true, false]) {
      for (const encode of [x => x, JSON.stringify]) {
        assert.equal(parseFeedback(encode({ correct, feedback: type }), true).correct, correct);
      }
    }
  }
  assert.throws(() => parseFeedback({ correct: 'false' }, true));
  assert.throws(() => parseFeedback(null, true));
  assert.equal(parseFeedback({ feedback: 'Review your structure' }, false).correct, undefined);
});

test('rapid answer changes persist in selection order even with a slow first request', async () => {
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const saved = [];
  const save = createAnswerQueue(async value => {
    if (value === 'first') await gate;
    saved.push(value);
  });
  const first = save('first');
  const second = save('second');
  await Promise.resolve();
  assert.deepEqual(saved, []);
  release(); await Promise.all([first, second]);
  assert.deepEqual(saved, ['first', 'second']);
});

test('save failures reach the caller and do not block retrying', async () => {
  const save = createAnswerQueue(async value => {
    if (value === 'failure') throw new Error('offline');
    return value;
  });
  await assert.rejects(save('failure'), /offline/);
  assert.equal(await save('retry'), 'retry');
});
