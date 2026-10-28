const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const levels = ['A1','A2','B1','B2','C1','C2'];
const skills = ['grammar','vocabulary','reading','listening','writing','speaking'];

export function materialEditor(host, material) {
  const { kind, item } = material;
  const field = (name, label, multiline = false, required = true) => `<div class="field"><label for="edit-${name}">${label}</label>${multiline ? `<textarea id="edit-${name}" name="${name}" rows="5" ${required ? 'required' : ''}>${esc(item[name])}</textarea>` : `<input id="edit-${name}" name="${name}" value="${esc(item[name])}" ${required ? 'required' : ''}>`}</div>`;
  const choice = (name, label, options) => `<div class="field"><label for="edit-${name}">${label}</label><select id="edit-${name}" name="${name}">${options.map(v => `<option ${item[name] === v ? 'selected' : ''}>${v}</option>`).join('')}</select></div>`;
  let html = '';
  if (kind === 'lesson') {
    html = field('title','Lesson title') + field('description','Description', true) + choice('cefr_level','CEFR level', levels) + choice('category','Skill',skills) + `<div class="field"><label><input name="is_published" type="checkbox" ${item.is_published ? 'checked' : ''}> Published</label></div><div class="field"><label><input name="archived" type="checkbox" ${(item.archived ?? Boolean(item.archived_at)) ? 'checked' : ''}> Archived (removes the lesson from the published path)</label></div>`;
  } else if (kind === 'section') html = field('title','Section heading') + field('content','Explanation and examples',true);
  else {
    html = field('prompt','Question',true) + field('passage','Reading passage or listening transcript',true,false) + field('rubric','Writing or speaking feedback guidance',true,false);
    if (kind === 'exercise') html += choice('exercise_type','Exercise type',['multiple_choice','fill_blank','reading_comprehension','listening','short_response']);
    if (item.options?.length) html += `<fieldset><legend>Answer options</legend><p>Choose one correct answer and explain each choice. Keep existing choices in their original positions.</p>${item.options.map((o,i) => `<div class="option-editor"><div class="field"><label for="option-text-${i}">Choice ${i+1}</label><input id="option-text-${i}" data-option-text="${i}" value="${esc(o.option_text)}" required></div><label><input type="radio" name="correct_option" value="${i}" ${o.is_correct ? 'checked' : ''} required> Correct answer</label><div class="field"><label for="option-feedback-${i}">Explanation for choice ${i+1}</label><textarea id="option-feedback-${i}" data-option-feedback="${i}" required>${esc(o.explanation)}</textarea></div></div>`).join('')}</fieldset>`;
  }
  host.innerHTML = html;
  return () => {
    const payload = { ...item };
    host.querySelectorAll('[name]').forEach(input => {
      if (input.name === 'correct_option') return;
      payload[input.name] = input.type === 'checkbox' ? input.checked : input.value.trim();
    });
    if (item.options?.length) payload.options = item.options.map((option,i) => ({ ...option, option_text: host.querySelector(`[data-option-text="${i}"]`).value.trim(), explanation: host.querySelector(`[data-option-feedback="${i}"]`).value.trim(), is_correct: host.querySelector('[name="correct_option"]:checked')?.value === String(i) }));
    return payload;
  };
}
