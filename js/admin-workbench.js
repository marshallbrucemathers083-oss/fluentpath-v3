import { supabase, backendMessage } from './supabase.js';
import { materialEditor } from './material-editor.js';
import { mountPracticeManager } from './practice-manager.js';
import { attachReportReview } from './report-review.js';

const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

export async function mountWorkbench(view, notify) {
  const host = document.createElement('section');
  host.className = 'panel';
  host.innerHTML = '<h2>Content and moderation workbench</h2><p role="status">Loading administrative records…</p>';
  view.append(host);
  try {
    const results = await Promise.all([
      supabase.rpc('admin_list_users'),
      supabase.from('lessons').select('*').order('created_at'),
      supabase.from('lesson_sections').select('*').order('order_index'),
      supabase.from('exercises').select('*,exercise_options(*)').order('order_index'),
      supabase.from('exam_questions').select('*,exam_question_options(*)').order('order_index'),
      supabase.from('moderation_history').select('action,details,created_at').order('created_at', { ascending: false }).limit(50)
    ]);
    for (const result of results) if (result.error) throw result.error;
    const [users, lessons, sections, exercises, questions, history] = results.map(result => result.data || []);
    const materials = [
      ...lessons.map(item => ({ kind: 'lesson', item, label: item.title })),
      ...sections.map(item => ({ kind: 'section', item, label: item.title })),
      ...exercises.map(item => ({ kind: 'exercise', item: { ...item, options: item.exercise_options }, label: item.prompt })),
      ...questions.map(item => ({ kind: 'exam_question', item: { ...item, options: item.exam_question_options }, label: item.prompt }))
    ];
    host.innerHTML = `<h2>Platform overview</h2><p>${users.length} registered users (up to 500 displayed) · ${lessons.length} lessons · ${lessons.filter(l => l.is_published).length} published · ${questions.length} practice questions</p>
      <form data-material-form><h3>Edit learning materials</h3><p>Unpublish lessons before changing exercises. Keep option positions stable to preserve historical answers. Set archived to true to archive a lesson.</p><div class="field"><label for="material-record">Material</label><select id="material-record">${materials.map((m, i) => `<option value="${i}">${escape(m.kind)}: ${escape(m.label)}</option>`).join('')}</select></div><div class="field"><label for="material-data">Material fields (JSON)</label><textarea id="material-data" rows="14" spellcheck="false" required></textarea></div><button class="button button-primary">Save material</button><p data-material-status role="status"></p></form>
      <form data-moderation-form><h3>Account moderation</h3><p>Reports are allegations. Review content and context before taking action.</p><div class="field"><label for="moderation-user">Member</label><select id="moderation-user">${users.filter(u => u.role !== 'admin').map(u => `<option value="${u.id}">${escape(u.full_name)} (${escape(u.email)})</option>`).join('')}</select></div><div class="field"><label for="moderation-action">Action</label><select id="moderation-action"><option value="warn">Issue warning</option><option value="suspend">Temporary suspension</option><option value="ban">Ban</option><option value="restore">Restore access</option></select></div><div class="field"><label for="moderation-until">Suspension ends (local time, required for suspension)</label><input id="moderation-until" type="datetime-local"></div><div class="field"><label for="moderation-reason">Reason</label><textarea id="moderation-reason" minlength="5" maxlength="1000" required></textarea></div><button class="button button-secondary">Record moderation action</button><p data-moderation-status role="status"></p></form>
      <h3>Recent moderation history</h3>${history.length ? history.map(h => `<details><summary>${escape(h.created_at)} · ${escape(h.action)}</summary><pre>${escape(JSON.stringify(h.details, null, 2))}</pre></details>`).join('') : '<p>No moderation actions recorded.</p>'}`;
    const select = host.querySelector('#material-record');
    const editor = host.querySelector('#material-data');
    editor.closest('.field').remove();
    const fields = document.createElement('div');
    select.closest('.field').after(fields);
    host.querySelector('[data-material-form] > p').textContent = 'Unpublish a lesson before changing its exercises. Archive substantially revised lessons to preserve historical results.';
    let readMaterial;
    const load = () => {
      const m = materials[Number(select.value)];
      if (m) readMaterial = materialEditor(fields, m);
      else { fields.textContent = 'No materials are available yet. Create a draft lesson above.'; host.querySelector('[data-material-form] button').disabled = true; }
    };
    select.addEventListener('change', load); load();
    host.querySelector('[data-material-form]').addEventListener('submit', async event => {
      event.preventDefault();
      const button = event.currentTarget.querySelector('button'); button.disabled = true;
      const status = host.querySelector('[data-material-status]');
      try {
        const m = materials[Number(select.value)];
        const payload = readMaterial();
        const { error } = await supabase.rpc('admin_save_material', { p_kind: m.kind, p_id: m.item.id, p_data: payload });
        if (error) throw error;
        m.item = payload; status.textContent = 'Material saved.';
      } catch (error) { status.textContent = backendMessage(error); }
      finally { button.disabled = false; }
    });
    host.querySelector('[data-moderation-form]').addEventListener('submit', async event => {
      event.preventDefault();
      const button = event.currentTarget.querySelector('button'); button.disabled = true;
      try {
        const date = host.querySelector('#moderation-until').value;
        const { error } = await supabase.rpc('admin_moderate_user', { p_user_id: host.querySelector('#moderation-user').value, p_action: host.querySelector('#moderation-action').value, p_reason: host.querySelector('#moderation-reason').value, p_until: date ? new Date(date).toISOString() : null });
        if (error) throw error;
        host.querySelector('[data-moderation-status]').textContent = 'Moderation action saved to the audit history.';
      } catch (error) { host.querySelector('[data-moderation-status]').textContent = backendMessage(error); }
      finally { button.disabled = false; }
    });
    await mountPracticeManager(host);
    const stats = await supabase.rpc('admin_platform_stats');
    if (stats.error) throw stats.error;
    const overview = document.createElement('div'); overview.className = 'metric-row';
    for (const [key, value] of Object.entries(stats.data)) {
      const metric = document.createElement('div'); metric.className = 'metric';
      const number = document.createElement('b'); number.textContent = value;
      const label = document.createElement('span'); label.textContent = key.replaceAll('_', ' ');
      metric.append(number,label); overview.append(metric);
    }
    host.prepend(overview);
    attachReportReview(view);
  } catch (error) { host.innerHTML = `<h2>Workbench unavailable</h2><p role="status">${escape(backendMessage(error))}</p><p>The reviewed admin migrations must be applied before using this workbench.</p>`; }
}
