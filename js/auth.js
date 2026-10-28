import { supabase, backendMessage } from './supabase.js';

if (location.pathname.endsWith('/verify-email.html') && supabase) {
  const statusNode = document.querySelector('#verification-status');
  supabase.auth.getSession().then(({ data, error }) => {
    if (error) { statusNode.textContent = 'We could not confirm this link. Try signing in or request a new confirmation email.'; return; }
    if (data.session) statusNode.textContent = 'Your email is confirmed. You can sign in and continue your learning path.';
  });
}

const form = document.querySelector('#auth-form');
const status = document.querySelector('#auth-status');
const notice = document.querySelector('#auth-notice');
const submit = document.querySelector('#submit-button');

function message(text, kind = 'success') {
  if (notice) {
    notice.textContent = text;
    notice.hidden = false;
    notice.classList.toggle('error', kind === 'error');
  } else if (status) {
    status.textContent = text;
    status.dataset.kind = kind;
  }
}

form?.addEventListener('submit', async event => {
  event.preventDefault();
  if (!form.reportValidity()) return;
  if (!supabase) return message(backendMessage(), 'error');
  const data = new FormData(form);
  const email = String(data.get('email') || '').trim();
  const password = String(data.get('password') || '');
  const mode = form.dataset.mode || 'login';
  submit.disabled = true;
  submit.textContent = mode === 'register' ? 'Creating account…' : 'Signing in…';
  try {
    if (mode === 'register') {
      const name = String(data.get('name') || '').trim();
      const { error } = await supabase.auth.signUp({
        email, password,
        options: { data: { full_name: name }, emailRedirectTo: `${location.origin}/verify-email.html` }
      });
      if (error) throw error;
      message('Account created. Check your inbox for a confirmation link.');
      form.reset();
    } else {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;
      location.assign('/app.html');
    }
  } catch (error) {
    message(backendMessage(error), 'error');
  } finally {
    submit.disabled = false;
    submit.textContent = mode === 'register' ? 'Create account' : 'Sign in';
  }
});

document.querySelector('#reset-request-form')?.addEventListener('submit', async event => {
  event.preventDefault();
  const email = new FormData(event.currentTarget).get('email');
  if (!supabase) return message(backendMessage(), 'error');
  const button = event.currentTarget.querySelector('button');
  button.disabled = true;
  try {
    const { error } = await supabase.auth.resetPasswordForEmail(String(email), { redirectTo: `${location.origin}/reset-password.html` });
    if (error) throw error;
    message('If an account exists for this address, a reset link is on its way.');
  } catch (error) { message(backendMessage(error), 'error'); }
  finally { button.disabled = false; }
});

document.querySelector('#password-update-form')?.addEventListener('submit', async event => {
  event.preventDefault();
  const password = document.querySelector('#password').value;
  const confirm = document.querySelector('#confirm-password').value;
  if (password !== confirm) return message('The passwords do not match.', 'error');
  if (!supabase) return message(backendMessage(), 'error');
  try {
    const { error } = await supabase.auth.updateUser({ password });
    if (error) throw error;
    message('Your password has been updated. You can sign in now.');
  } catch (error) { message(backendMessage(error), 'error'); }
});
