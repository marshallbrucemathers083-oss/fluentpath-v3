import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
import { parseFeedback } from '../js/answer-state.js';

const source = await readFile(new URL('../js/app.js', import.meta.url), 'utf8');
const handler = source.slice(source.indexOf('function bindExercise(card)'), source.indexOf('async function leaderboardPage()'));
class Control {
  constructor(dataset = {}) { this.dataset = dataset; this.events = {}; this.hidden = true; this.disabled = false; this.textContent = ''; this.value = ''; this.attributes = {}; }
  addEventListener(event, callback) { this.events[event] = callback; }
  setAttribute(name, value) { this.attributes[name] = value; }
  fire(event) { return this.events[event]?.(); }
}
function setup(type, rpc) {
  const options = [new Control({ option: 'wrong-id' }), new Control({ option: 'correct-id' })];
  const check = new Control(); const feedback = new Control(); const classes = new Set();
  feedback.classList = { remove: c => classes.delete(c), add: c => classes.add(c), toggle: (c, yes) => yes ? classes.add(c) : classes.delete(c) };
  const response = type === 'short_response' ? new Control() : null;
  const card = { dataset: { exercise: 'exercise-id', type, skill: 'grammar' }, querySelector: selector => ({ '[data-submit-exercise]': check, '.feedback': feedback, '[data-response]': response }[selector] || null), querySelectorAll: selector => selector === '[data-option]' ? options : [...options, ...(response ? [response] : [])] };
  const context = vm.createContext({ supabase: { rpc }, parseFeedback, esc: String, loadProfile: async () => {}, notify() {}, backendMessage: error => error.message, attachSpeechInput() {} });
  vm.runInContext(handler, context); context.bindExercise(card);
  return { options, check, feedback, classes, response };
}
for (const type of ['multiple_choice','fill_blank','reading_comprehension','listening']) {
  test(`${type}: selected option UUID reaches RPC and correct/incorrect feedback matches`, async () => {
    const calls = [];
    const ui = setup(type, async (name, args) => {
      calls.push({ name, exercise: args.p_exercise_id, option: args.p_option_id });
      return { data: { correct: args.p_option_id === 'correct-id', feedback: 'Explanation', xp_awarded: 0 } };
    });
    await ui.options[0].fire('click'); await ui.check.fire('click');
    assert.ok(ui.classes.has('incorrect'));
    await ui.options[1].fire('click'); await ui.check.fire('click');
    assert.ok(!ui.classes.has('incorrect'));
    assert.deepEqual(calls, [{ name: 'submit_exercise', exercise: 'exercise-id', option: 'wrong-id' }, { name: 'submit_exercise', exercise: 'exercise-id', option: 'correct-id' }]);
    assert.match(ui.feedback.innerHTML, /That is right/);
  });
}
test('changing choices during submission cannot attach a previous answer result to a new choice', async () => {
  let finish;
  const ui = setup('multiple_choice', () => new Promise(resolve => { finish = resolve; }));
  ui.options[0].fire('click'); const pending = ui.check.fire('click');
  ui.options[1].fire('click');
  assert.equal(ui.options[0].attributes['aria-pressed'], 'true');
  assert.equal(ui.options[1].disabled, true);
  finish({ data: { correct: false, feedback: 'Try again.' } }); await pending;
  assert.equal(ui.options[1].disabled, false);
});
test('written practice uses its RPC without selecting an option or inventing correctness', async () => {
  let called;
  const ui = setup('short_response', async (name,args) => { called = { name, response: args.p_response }; return { data: { feedback: 'Review your structure.' } }; });
  ui.response.value = 'A clear sentence with a useful example.';
  await ui.check.fire('click');
  assert.equal(called.name, 'submit_written_response');
  assert.equal(called.response, ui.response.value);
  assert.match(ui.feedback.innerHTML, /practice response/);
  assert.equal(ui.classes.has('incorrect'), false);
});
test('RPC failure displays an error and unlocks controls for retry', async () => {
  const ui = setup('multiple_choice', async () => ({ error: new Error('Network unavailable') }));
  ui.options[1].fire('click'); await ui.check.fire('click');
  assert.match(ui.feedback.textContent, /Network unavailable/);
  assert.equal(ui.check.disabled, false);
  assert.equal(ui.options[1].disabled, false);
});
