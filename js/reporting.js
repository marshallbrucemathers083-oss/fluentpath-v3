import { supabase, backendMessage } from './supabase.js';

export function askReportReason() {
  return new Promise(resolve => {
    const dialog = document.createElement('dialog');
    dialog.className = 'app-dialog';
    dialog.innerHTML = `<form><h2>Report content</h2><p>A moderator will review your report. Reporting does not automatically restrict anyone’s account.</p><div class="field"><label for="report-reason">Reason</label><select id="report-reason"><option>Harassment or bullying</option><option>Hate or discrimination</option><option>Spam or advertising</option><option>Inappropriate content</option><option>Other concern</option></select></div><div class="field"><label for="report-detail">Explanation (optional)</label><textarea id="report-detail" maxlength="800"></textarea></div><div class="form-actions"><button class="button button-primary">Submit report</button><button class="button button-secondary" type="button" data-cancel>Cancel</button></div></form>`;
    document.body.append(dialog);
    dialog.addEventListener('close', () => { resolve(dialog.returnValue || null); dialog.remove(); }, { once: true });
    dialog.querySelector('[data-cancel]').addEventListener('click', () => dialog.close());
    dialog.querySelector('form').addEventListener('submit', event => {
      event.preventDefault();
      dialog.close(`${dialog.querySelector('select').value}: ${dialog.querySelector('textarea').value.trim()}`);
    });
    dialog.showModal();
  });
}

export async function mountMyReports(view) {
  const section = document.createElement('section'); section.className = 'panel';
  const heading = document.createElement('h2'); heading.textContent = 'Your reports'; section.append(heading);
  const status = document.createElement('p'); status.setAttribute('role', 'status'); status.textContent = 'Loading report statuses…'; section.append(status); view.append(section);
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) { status.textContent = 'Sign in again to view your reports.'; return; }
  const { data, error } = await supabase.from('forum_reports').select('reason,status,created_at').eq('reporter_id', auth.user.id).order('created_at', { ascending: false }).limit(30);
  status.textContent = error ? backendMessage(error) : data?.length ? '' : 'You have no visible reports yet.';
  for (const report of data || []) {
    const line = document.createElement('p'); line.textContent = `${report.status} · ${report.reason} · ${new Date(report.created_at).toLocaleDateString()}`; section.append(line);
  }
  const { data: warnings, error: warningError } = await supabase.from('user_warnings').select('reason,created_at').eq('user_id', auth.user.id).order('created_at', { ascending: false });
  const label = document.createElement('h3'); label.textContent = 'Messages from moderators'; section.append(label);
  if (warningError) { const line = document.createElement('p'); line.textContent = backendMessage(warningError); section.append(line); }
  else if (!warnings?.length) { const line = document.createElement('p'); line.textContent = 'No warnings have been issued to your account.'; section.append(line); }
  for (const warning of warnings || []) { const line = document.createElement('p'); line.textContent = `${new Date(warning.created_at).toLocaleDateString()}: ${warning.reason}`; section.append(line); }
}
