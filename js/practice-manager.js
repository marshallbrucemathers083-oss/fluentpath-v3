import { supabase, backendMessage } from './supabase.js';

const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export async function mountPracticeManager(parent) {
  const host = document.createElement('section'); parent.append(host);
  host.innerHTML = '<h3>TOEFL-style practice content</h3><p role="status">Loading practice sets…</p>';
  const { data, error } = await supabase.from('exam_sets').select('*').order('created_at');
  if (error) { host.querySelector('p').textContent = backendMessage(error); return; }
  host.innerHTML = `<h3>TOEFL-style practice content</h3><p>These are unofficial practice sets. Draft sets must contain complete objective questions before publishing.</p><div>${data.map(set => `<div class="lesson-row"><div><strong>${esc(set.title)}</strong><p>${set.is_published ? 'Published' : 'Draft'} · ${esc(set.cefr_level)}</p></div><button class="button button-secondary" data-practice-status="${set.id}" data-published="${set.is_published}">${set.is_published ? 'Unpublish' : 'Publish'}</button></div>`).join('') || '<p>No practice sets yet.</p>'}</div>
  <form data-new-set><h4>Create a practice set</h4><div class="field"><label for="practice-title">Title</label><input id="practice-title" name="title" maxlength="120" required></div><div class="field"><label for="practice-description">Description</label><textarea id="practice-description" name="description" maxlength="1000" required></textarea></div><div class="field"><label for="practice-level">CEFR level</label><select id="practice-level" name="cefr_level">${['A1','A2','B1','B2','C1','C2'].map(l => `<option>${l}</option>`).join('')}</select></div><div class="field"><label for="practice-duration">Time limit in minutes</label><input id="practice-duration" name="minutes" type="number" min="5" max="180" value="20" required></div><button class="button button-primary">Create draft set</button><p role="status"></p></form>
  <form data-new-question><h4>Add a practice question</h4><div class="field"><label for="practice-parent">Draft set</label><select id="practice-parent" name="exam_id" required><option value="">Choose a draft set</option>${data.filter(s => !s.is_published).map(s => `<option value="${s.id}">${esc(s.title)}</option>`).join('')}</select></div><div class="field"><label for="practice-skill">Skill</label><select id="practice-skill" name="category">${['reading','listening','grammar','vocabulary','writing','speaking'].map(s => `<option>${s}</option>`).join('')}</select></div><div class="field"><label for="practice-prompt">Question</label><textarea id="practice-prompt" name="prompt" required maxlength="2000"></textarea></div><div class="field"><label for="practice-passage">Passage or browser speech transcript</label><textarea id="practice-passage" name="passage" maxlength="10000"></textarea></div><div class="field"><label for="practice-rubric">Response rubric (required for writing and speaking)</label><textarea id="practice-rubric" name="rubric" maxlength="2000"></textarea></div><fieldset data-practice-options><legend>Objective answer choices</legend>${[0,1,2].map(i => `<div class="field"><label for="practice-choice-${i}">Choice ${i+1}</label><input id="practice-choice-${i}" data-choice="${i}"><label><input name="practice-correct" type="radio" value="${i}" ${i===0 ? 'checked' : ''}> Correct answer</label><label for="practice-explanation-${i}">Explanation for choice ${i+1}</label><textarea id="practice-explanation-${i}" data-explanation="${i}"></textarea></div>`).join('')}</fieldset><button class="button button-primary">Add question</button><p role="status"></p></form><p data-practice-status role="status"></p>`;
  const reload = async () => { host.remove(); await mountPracticeManager(parent); };
  host.querySelectorAll('button[data-practice-status]').forEach(button => button.addEventListener('click', async () => {
    button.disabled = true;
    const { error } = await supabase.rpc('admin_set_practice_status', { p_id: button.dataset.practiceStatus, p_published: button.dataset.published !== 'true' });
    if (error) { host.querySelector('p[data-practice-status]').textContent = backendMessage(error); button.disabled = false; }
    else await reload();
  }));
  const skill = host.querySelector('#practice-skill');
  const toggle = () => { host.querySelector('[data-practice-options]').hidden = ['writing','speaking'].includes(skill.value); };
  skill.addEventListener('change', toggle);
  for (const form of host.querySelectorAll('form')) form.addEventListener('submit', async event => {
    event.preventDefault(); const button = form.querySelector('button'); button.disabled = true;
    const values = Object.fromEntries(new FormData(form));
    const isSet = form.hasAttribute('data-new-set');
    const objective = !['writing','speaking'].includes(values.category);
    const payload = isSet ? { ...values, kind: 'set', duration_seconds: Number(values.minutes)*60 } : { ...values, kind: 'question', is_objective: objective, options: objective ? [0,1,2].map(i => ({ option_text: form.querySelector(`[data-choice="${i}"]`).value.trim(), explanation: form.querySelector(`[data-explanation="${i}"]`).value.trim(), is_correct: values['practice-correct']===String(i) })) : [] };
    const { error } = await supabase.rpc('admin_create_practice', { p_data: payload });
    if (error) { form.querySelector('[role="status"]').textContent = backendMessage(error); button.disabled = false; }
    else await reload();
  });
}
