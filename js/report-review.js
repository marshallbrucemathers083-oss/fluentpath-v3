import { supabase, backendMessage } from './supabase.js';

export function attachReportReview(view) {
  for (const resolve of view.querySelectorAll('[data-resolve]')) {
    const button = document.createElement('button'); button.type = 'button'; button.textContent = 'Inspect context';
    resolve.before(button);
    button.addEventListener('click', async () => {
      const dialog = document.createElement('dialog'); dialog.className = 'app-dialog';
      const heading = document.createElement('h2'); heading.textContent = 'Review reported content';
      const close = document.createElement('button'); close.className = 'button button-secondary'; close.textContent = 'Close review';
      close.addEventListener('click', () => dialog.close());
      const content = document.createElement('div'); content.setAttribute('role','status'); content.textContent = 'Loading report context…';
      dialog.append(heading,content,close); document.body.append(dialog);
      dialog.addEventListener('close', () => dialog.remove(), { once: true }); dialog.showModal();
      const { data, error } = await supabase.rpc('admin_report_context', { p_id: resolve.dataset.resolve });
      content.textContent = '';
      const line = (title,text) => { const h = document.createElement('h3'); h.textContent = title; const p = document.createElement('p'); p.textContent = text; content.append(h,p); };
      if (error) { line('Review unavailable',backendMessage(error)); return; }
      line('Report allegation',data.report.reason);
      line('Reported content',data.content?.body || 'Content unavailable.');
      if (data.content) {
        const field = document.createElement('div'); field.className = 'field';
        const label = document.createElement('label'); label.textContent = 'Content visibility'; label.htmlFor = 'review-content-status';
        const select = document.createElement('select'); select.id = 'review-content-status';
        for (const [value,text] of [['published','Restore published content'],['hidden','Hide pending review'],['removed','Remove inappropriate content']]) {
          const option = document.createElement('option'); option.value = value; option.textContent = text; option.selected = value === data.content.status; select.append(option);
        }
        const save = document.createElement('button'); save.className = 'button button-secondary'; save.textContent = 'Save content visibility';
        const status = document.createElement('p'); status.setAttribute('role','status');
        save.addEventListener('click', async () => {
          save.disabled = true;
          const { error } = await supabase.rpc('moderate_forum_content', { p_content_type: data.report.content_type, p_content_id: data.report.content_id, p_status: select.value });
          status.textContent = error ? backendMessage(error) : 'Content visibility saved. The report remains available for a separate decision.';
          save.disabled = false;
        });
        field.append(label,select,save,status); content.append(field);
      }
      if (data.parent) line(data.parent.title || 'Parent post',data.parent.body);
      line('Author',`${data.author?.full_name || 'Unavailable'} · ${data.author?.is_banned ? 'Banned' : data.author?.suspended_until && Date.parse(data.author.suspended_until)>Date.now() ? 'Temporarily suspended' : 'Active'}`);
      for (const warning of data.warnings || []) line('Previous warning',`${warning.created_at}: ${warning.reason}`);
      if (data.author) {
        const action = document.createElement('button'); action.className = 'button button-secondary'; action.textContent = 'Select author for account review';
        action.addEventListener('click', () => { const select = view.querySelector('#moderation-user'); if (select) { select.value = data.author.id; dialog.close(); select.focus(); select.scrollIntoView({ block: 'center' }); } }); content.append(action);
      }
    });
  }
}
