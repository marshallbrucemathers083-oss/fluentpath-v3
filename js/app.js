import { supabase, backendMessage } from './supabase.js';
import { attachSpeechInput } from './speech.js';
import { createAnswerQueue, parseFeedback } from './answer-state.js';
import { mountWorkbench } from './admin-workbench.js';
import { askReportReason, mountMyReports } from './reporting.js';
import { observeLearningMotion } from './motion.js';

const view = document.querySelector('#view');
observeLearningMotion(view);
const toast = document.querySelector('#toast');
let user = null;
let profile = null;
let allLessons = [];
let toastTimer;
let examTimer;
const levelLabels = { A1: 'Beginner', A2: 'Elementary', B1: 'Intermediate', B2: 'Upper intermediate', C1: 'Advanced', C2: 'Proficient' };
const skills = ['grammar', 'vocabulary', 'reading', 'listening', 'writing', 'speaking'];

function notify(text, kind = 'success') {
  toast.textContent = text;
  toast.dataset.kind = kind;
  toast.dataset.show = 'true';
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { toast.dataset.show = 'false'; }, 3800);
}
function esc(value = '') {
  return String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}
function titleCase(value = '') { return value.replaceAll('_', ' ').replace(/\b\w/g, c => c.toUpperCase()); }
function setHeading(value) {
  document.querySelector('#page-label').textContent = value;
  document.title = `${value} · FluentPath`;
}
function errorBox(error, retry = 'Reload this view') {
  return `<div class="panel error-state"><h2>We could not load this page</h2><p>${esc(backendMessage(error))}</p><button class="button button-secondary" data-action="reload">${esc(retry)}</button><p class="muted">If this continues, contact a FluentPath administrator.</p></div>`;
}
function bindReload() { document.querySelector('[data-action="reload"]')?.addEventListener('click', () => route()); }
function requireData(data, error) { if (error) throw error; return data || []; }
async function loadProfile() {
  const { data, error } = await supabase.from('profiles').select('*').eq('id', user.id).single();
  if (error) throw error;
  profile = data;
  const initials = (profile.full_name || profile.email || 'F').split(/\s+/).slice(0, 2).map(s => s[0]).join('').toUpperCase();
  document.querySelector('#side-name').textContent = profile.full_name || 'Student';
  document.querySelector('#side-level').textContent = `${profile.current_cefr_level} · ${levelLabels[profile.current_cefr_level]}`;
  document.querySelector('#user-avatar').textContent = initials;
  document.querySelector('#top-avatar').textContent = initials;
  document.querySelector('#streak-indicator').innerHTML = `<span aria-hidden="true">◷</span> <span>${profile.streak_count || 0} day streak</span>`;
  document.querySelector('#streak-indicator').setAttribute('aria-label', `Current study streak: ${profile.streak_count || 0} days`);
  if (profile.role === 'admin') {
    document.querySelector('#admin-nav').hidden = false;
    document.querySelector('#mobile-admin-nav').hidden = false;
  }
}
async function fetchLessons() {
  const { data, error } = await supabase.from('lessons').select('id,title,slug,description,cefr_level,category,order_index,xp_reward,estimated_minutes').eq('is_published', true).order('cefr_level').order('order_index');
  if (error) throw error;
  allLessons = data || [];
  return allLessons;
}
function pageHead(eyebrow, heading, description, actions = '') {
  return `<div class="page-head"><div><div class="eyebrow">${esc(eyebrow)}</div><h1>${heading}</h1><p>${esc(description)}</p></div>${actions}</div>`;
}
function lessonRow(lesson, i = 0, status = '') {
  return `<article class="lesson-row"><span class="lesson-marker">${status === 'completed' ? '✓' : esc(lesson.cefr_level)}</span><div><h3>${esc(lesson.title)}</h3><small>${esc(titleCase(lesson.category))} · ${esc(lesson.estimated_minutes)} min · ${esc(lesson.xp_reward)} XP</small></div><a class="button button-secondary" href="#/lesson/${encodeURIComponent(lesson.slug)}">${status === 'completed' ? 'Review' : 'Start lesson'}</a></article>`;
}
async function dashboard() {
  setHeading('Overview');
  view.innerHTML = '<div class="loading-state" role="status">Loading your progress…</div>';
  try {
    const { error: questError } = await supabase.rpc('ensure_daily_quests');
    if (questError) throw questError;
    const [lessons, progressResult, questResult, leaderboardResult, earnedResult, achievementResult, rankResult] = await Promise.all([
      fetchLessons(),
      supabase.from('lesson_progress').select('lesson_id,status,score_percentage').eq('user_id', user.id),
      supabase.from('user_quests').select('id,progress,is_completed,daily_quests(title,description,target_count,xp_reward)').eq('user_id', user.id).eq('quest_date', new Date().toISOString().slice(0, 10)),
      supabase.from('public_leaderboard').select('id,full_name,total_xp').order('total_xp', { ascending: false }).limit(5),
      supabase.from('user_achievements').select('achievement_id,earned_at').eq('user_id', user.id),
      supabase.from('achievements').select('id,title,description,icon'),
      supabase.rpc('get_my_leaderboard_rank')
    ]);
    const progress = requireData(progressResult.data, progressResult.error);
    const quests = requireData(questResult.data, questResult.error);
    const leaders = requireData(leaderboardResult.data, leaderboardResult.error);
    if (earnedResult.error) throw earnedResult.error;
    if (achievementResult.error) throw achievementResult.error;
    if (rankResult.error) throw rankResult.error;
    const earned = new Set((earnedResult.data || []).map(row => row.achievement_id));
    const achievements = (achievementResult.data || []).filter(item => earned.has(item.id));
    const completed = progress.filter(row => row.status === 'completed').length;
    const progressMap = new Map(progress.map(row => [row.lesson_id, row.status]));
    const myRank = rankResult.data;
    const next = lessons.filter(lesson => progressMap.get(lesson.id) !== 'completed').slice(0, 4);
    view.innerHTML = `<section class="welcome-panel"><div><div class="eyebrow">${esc(profile.current_cefr_level)} · ${esc(levelLabels[profile.current_cefr_level])}</div><h1>Welcome back, ${esc((profile.full_name || 'learner').split(' ')[0])}.</h1><p>Good learning happens one clear step at a time. Here is a useful place to begin.</p><a class="button button-primary" href="#/path">Continue your path</a></div><div class="welcome-art" aria-hidden="true">Aa</div></section>
      <div class="metric-row"><div class="metric"><b>${profile.total_xp || 0}</b><span>experience points</span></div><div class="metric"><b>${completed}</b><span>lessons completed</span></div><div class="metric"><b>${myRank ? `#${myRank}` : 'Not ranked'}</b><span>leaderboard place</span></div></div>
      <div class="app-grid" style="margin-top:20px"><div class="stack"><section class="panel"><div class="panel-heading"><h2>Next in your path</h2><a href="#/path">View all</a></div>${next.length ? next.map((lesson, i) => lessonRow(lesson, i, progressMap.get(lesson.id))).join('') : `<div class="empty-state"><h2>A fresh start</h2><p>No published lessons are available yet. Ask an admin to publish the first lesson.</p></div>`}</section>
      <section class="panel"><div class="panel-heading"><h2>Today’s practice</h2><a href="#/academy">Open academy</a></div>${quests.length ? quests.map(quest => { const q = quest.daily_quests; const percent = q?.target_count ? Math.min(100, quest.progress / q.target_count * 100) : 0; return `<div><div class="panel-heading"><div><b>${esc(q?.title || 'Daily practice')}</b><div class="muted">${esc(q?.description || '')}</div></div><b>${quest.progress}/${q?.target_count || 0}</b></div><div class="progress-track" aria-label="Quest progress"><i style="width:${percent}%"></i></div></div>`; }).join('') : `<div class="empty-state">Your daily quests will appear here after the migrations are applied.</div>`}</section></div>
      <div class="stack"><section class="panel"><div class="panel-heading"><h2>Community board</h2><a href="#/leaderboard">Ranks</a></div>${leaders.length ? leaders.map((row, i) => `<div class="rank-row"><span class="rank-number">${i + 1}</span><div><strong>${esc(row.full_name || 'Learner')}</strong><small>${row.id === user.id ? 'That’s you' : 'FluentPath learner'}</small></div><span class="rank-xp">${row.total_xp} XP</span></div>`).join('') : '<div class="empty-state">Be the first learner on the board.</div>'}</section><section class="panel"><h2>Milestones</h2>${achievements.length ? achievements.map(item => `<div class="achievement-row"><span class="achievement-mark" aria-hidden="true">${esc(item.icon)}</span><div><strong>${esc(item.title)}</strong><small>${esc(item.description)}</small></div></div>`).join('') : '<div class="empty-state">Your first milestone will appear when you complete a lesson.</div>'}</section><section class="panel"><h2>Your level</h2><p class="muted">You are working at <strong>${esc(profile.current_cefr_level)}</strong>. Your level can be changed from your profile.</p><a href="#/profile" class="button button-secondary">View profile</a></section></div></div>`;
  } catch (error) { view.innerHTML = errorBox(error); bindReload(); }
}
async function pathPage() {
  setHeading('Learning path');
  view.innerHTML = '<div class="loading-state" role="status">Opening the learning path…</div>';
  try {
    const [lessons, progressResult] = await Promise.all([fetchLessons(), supabase.from('lesson_progress').select('lesson_id,status,score_percentage').eq('user_id', user.id)]);
    if (progressResult.error) throw progressResult.error;
    const progress = new Map((progressResult.data || []).map(row => [row.lesson_id, row]));
    let selected = profile.current_cefr_level;
    const render = () => {
      const rows = lessons.filter(item => item.cefr_level === selected);
      view.innerHTML = `${pageHead('Your curriculum', 'The next step is yours.', 'Move through six CEFR levels with lessons across grammar, vocabulary, and communication.')}<div class="level-list">${Object.keys(levelLabels).map(level => `<button class="level-choice" data-level="${level}" aria-pressed="${level === selected}"><strong>${level}</strong><small>${levelLabels[level]}</small></button>`).join('')}</div><section class="panel" style="margin-top:20px"><div class="panel-heading"><h2>${selected} · ${levelLabels[selected]}</h2><span class="muted">${rows.length} lessons</span></div>${rows.length ? rows.map(lesson => lessonRow(lesson, 0, progress.get(lesson.id)?.status)).join('') : `<div class="empty-state"><h2>This level is being prepared</h2><p>There are no published lessons at this level yet.</p></div>`}</section>`;
      view.querySelectorAll('[data-level]').forEach(button => button.addEventListener('click', () => { selected = button.dataset.level; render(); }));
    };
    render();
  } catch (error) { view.innerHTML = errorBox(error); bindReload(); }
}
async function academyPage() {
  setHeading('Academy');
  view.innerHTML = '<div class="loading-state" role="status">Loading practice…</div>';
  try {
    const lessons = await fetchLessons();
    let skill = 'all';
    const render = () => {
      const filtered = skill === 'all' ? lessons : lessons.filter(lesson => lesson.category === skill);
      view.innerHTML = `${pageHead('Focused practice', 'The Academy', 'Choose a skill and work through a lesson with clear feedback.')}<div class="filters" role="group" aria-label="Filter lessons by skill"><button class="filter-button" data-skill="all" aria-pressed="${skill === 'all'}">All skills</button>${skills.map(item => `<button class="filter-button" data-skill="${item}" aria-pressed="${skill === item}">${titleCase(item)}</button>`).join('')}</div><section class="panel">${filtered.length ? filtered.map(lesson => lessonRow(lesson)).join('') : `<div class="empty-state"><h2>No ${titleCase(skill).toLowerCase()} lessons yet</h2><p>Choose another skill or check back after more lessons are published.</p></div>`}</section>`;
      view.querySelectorAll('[data-skill]').forEach(button => button.addEventListener('click', () => { skill = button.dataset.skill; render(); }));
    };
    render();
  } catch (error) { view.innerHTML = errorBox(error); bindReload(); }
}
function renderLessonText(content = '') {
  return esc(content).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/\*(.+?)\*/g, '<em>$1</em>').replace(/\n/g, '<br>');
}
async function lessonPage(slug) {
  view.innerHTML = '<div class="loading-state" role="status">Loading lesson…</div>';
  try {
    const { data, error } = await supabase.rpc('get_lesson', { p_slug: slug });
    if (error) throw error;
    const lesson = data?.lesson;
    if (!lesson) throw new Error('This lesson is unavailable or has not been published.');
    setHeading(lesson.title);
    const sections = data.sections || [];
    const exercises = data.exercises || [];
    view.innerHTML = `<div class="lesson-content" data-skill="${esc(lesson.category)}">${pageHead(`${lesson.cefr_level} · ${titleCase(lesson.category)}`, esc(lesson.title), esc(lesson.description), `<a class="button button-secondary" href="#/path">Back to path</a>`)}<div class="panel"><div class="panel-heading"><h2>Lesson notes</h2><span class="muted">${lesson.estimated_minutes} min</span></div>${sections.map(section => `<section class="lesson-section"><h2>${esc(section.title)}</h2><p>${renderLessonText(section.content)}</p></section>`).join('') || '<p class="muted">No lesson notes have been added yet.</p>'}</div>${exercises.map((exercise, index) => `<section class="exercise-card" data-exercise="${esc(exercise.id)}" data-type="${esc(exercise.exercise_type)}" data-skill="${esc(lesson.category)}"><div class="eyebrow">Practice ${index + 1} of ${exercises.length}</div><h2>${esc(exercise.prompt)}</h2>${exercise.passage ? `<p>${esc(exercise.passage)}</p>` : ''}${exercise.audio_script ? `<div class="audio-practice"><button class="button button-secondary" type="button" data-play-audio>Play example audio</button><details><summary>Read the transcript</summary><p>${esc(exercise.audio_script)}</p></details></div>` : ''}${exercise.exercise_type === 'short_response' ? `<div class="field"><label for="response-${esc(exercise.id)}">Your response</label><textarea id="response-${esc(exercise.id)}" data-response maxlength="4000" minlength="20" placeholder="Write a few sentences to try the idea."></textarea></div><p class="muted">${esc(exercise.rubric || 'Aim for a clear message, accurate language, and a useful example.')}</p>` : `<div class="options">${(exercise.options || []).map(option => `<button class="exercise-option" type="button" data-option="${esc(option.id)}" aria-pressed="false">${esc(option.option_text)}</button>`).join('')}</div>`}<div class="exercise-actions"><button type="button" class="button button-primary" data-submit-exercise disabled>${exercise.exercise_type === 'short_response' ? 'Send for feedback' : 'Check answer'}</button><span class="muted">${exercise.exercise_type === 'short_response' ? 'Practice response' : `${exercise.points} points`}</span></div><div class="feedback" hidden role="status" aria-live="polite"></div></section>`).join('')}</div>`;
    view.querySelectorAll('[data-exercise]').forEach(card => bindExercise(card));
  } catch (error) { setHeading('Lesson'); view.innerHTML = errorBox(error); bindReload(); }
}
function bindExercise(card) {
  let selected = null;
  let submitting = false;
  const check = card.querySelector('[data-submit-exercise]');
  const feedback = card.querySelector('.feedback');
  const response = card.querySelector('[data-response]');
  if (response && card.dataset.skill === 'speaking') attachSpeechInput(card, response, 'Speak your response');
  if (response) response.addEventListener('input', () => { check.disabled = response.value.trim().length < 20; });
  card.querySelector('[data-play-audio]')?.addEventListener('click', () => {
    const transcript = card.querySelector('details p')?.textContent;
    if (!transcript || !('speechSynthesis' in window)) return notify('Audio playback is not available in this browser.', 'error');
    window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(transcript);
    utterance.lang = 'en-US'; utterance.rate = .88;
    window.speechSynthesis.speak(utterance);
  });
  card.querySelectorAll('[data-option]').forEach(option => option.addEventListener('click', () => {
    if (submitting) return;
    selected = option.dataset.option;
    card.querySelectorAll('[data-option]').forEach(item => item.setAttribute('aria-pressed', String(item === option)));
    check.disabled = false;
    feedback.hidden = true;
  }));
  check.addEventListener('click', async () => {
    if (submitting) return;
    if (!response && !selected) return;
    submitting = true;
    card.querySelectorAll('[data-option], [data-response]').forEach(input => { input.disabled = true; });
    check.disabled = true; check.textContent = 'Checking…';
    try {
      const { data: rawData, error } = response
        ? await supabase.rpc('submit_written_response', { p_exercise_id: card.dataset.exercise, p_response: response.value.trim() })
        : await supabase.rpc('submit_exercise', { p_exercise_id: card.dataset.exercise, p_option_id: selected });
      if (error) throw error;
      const data = parseFeedback(rawData, !response);
      feedback.hidden = false;
      feedback.classList.remove('incorrect');
      if (typeof data.correct === 'boolean') feedback.classList.toggle('incorrect', !data.correct);
      feedback.innerHTML = `<strong>${typeof data.correct === 'boolean' ? (data.correct ? 'That is right.' : 'Not quite yet.') : 'A useful practice response.'}</strong> ${esc(data.feedback || '')}${data.xp_awarded ? `<br><strong>+${data.xp_awarded} XP</strong>` : ''}${data.lesson_completed ? '<br><strong>Lesson completed. Nice work.</strong>' : ''}`;
      check.textContent = typeof data.correct === 'boolean' ? (data.correct ? 'Answer checked' : 'Try another answer') : 'Response saved';
      await loadProfile();
      if (data.correct || response) notify(data.lesson_completed ? 'Lesson complete. Your progress is saved.' : `You earned ${data.xp_awarded || 0} XP.`);
    } catch (error) { feedback.hidden = false; feedback.classList.add('incorrect'); feedback.textContent = backendMessage(error); check.disabled = false; check.textContent = 'Check answer'; }
    finally {
      submitting = false;
      card.querySelectorAll('[data-option], [data-response]').forEach(input => { input.disabled = false; });
    }
  });
}
async function leaderboardPage() {
  setHeading('Leaderboard'); view.innerHTML = '<div class="loading-state">Loading learners…</div>';
  try {
    const { data, error } = await supabase.from('public_leaderboard').select('id,full_name,current_cefr_level,total_xp,streak_count').order('total_xp', { ascending: false }).limit(100);
    if (error) throw error;
    view.innerHTML = `${pageHead('Learning together', 'Leaderboard', 'A community view of the XP learners have earned through practice.')}<section class="panel">${data?.length ? data.map((row, i) => `<div class="rank-row"><span class="rank-number">${i + 1}</span><div><strong>${esc(row.full_name || 'Learner')}${row.id === user.id ? ' · You' : ''}</strong><small>${esc(row.current_cefr_level)} · ${esc(row.streak_count)} day streak</small></div><span class="rank-xp">${row.total_xp} XP</span></div>`).join('') : '<div class="empty-state"><h2>No learners on the board yet</h2><p>Complete a lesson to earn the first place.</p></div>'}</section>`;
  } catch (error) { view.innerHTML = errorBox(error); bindReload(); }
}
async function profilePage() {
  setHeading('Your profile');
  view.innerHTML = `${pageHead('Your account', 'Your profile', 'Keep your name and level up to date.')}<section class="panel" style="max-width:650px"><form id="profile-form"><div class="field"><label for="profile-name">Name</label><input id="profile-name" name="full_name" required maxlength="80" value="${esc(profile.full_name)}"></div><div class="field"><label for="profile-bio">A little about you</label><textarea id="profile-bio" name="bio" maxlength="280">${esc(profile.bio || '')}</textarea></div><div class="field"><label for="profile-level">Current learning level</label><select id="profile-level" name="level">${Object.keys(levelLabels).map(level => `<option value="${level}" ${level === profile.current_cefr_level ? 'selected' : ''}>${level} · ${levelLabels[level]}</option>`).join('')}</select></div><div class="field"><label>Email</label><input value="${esc(profile.email)}" readonly aria-readonly="true"></div><button class="button button-primary" type="submit">Save profile</button><p class="status" id="profile-status" role="status" aria-live="polite"></p></form></section>`;
  document.querySelector('#profile-form').addEventListener('submit', async event => {
    event.preventDefault(); const button = event.currentTarget.querySelector('button'); button.disabled = true;
    try {
      const { data, error } = await supabase.rpc('update_my_profile', { p_full_name: document.querySelector('#profile-name').value.trim(), p_bio: document.querySelector('#profile-bio').value.trim(), p_level: document.querySelector('#profile-level').value });
      if (error) throw error; profile = data; await loadProfile(); notify('Your profile has been saved.');
    } catch (error) { document.querySelector('#profile-status').textContent = backendMessage(error); document.querySelector('#profile-status').dataset.kind = 'error'; }
    finally { button.disabled = false; }
  });
}

async function toeflPage() {
  setHeading('TOEFL practice');
  view.innerHTML = `${pageHead('Timed practice', 'TOEFL-style practice', 'Try a practice set, then review your score report. Answers are scored when you finish.')}<section class="panel" style="max-width:760px"><h2>Ready when you are</h2><p class="muted">The practice set includes reading, listening, writing, and speaking questions. Your answers save as you go. The timer keeps running if you leave.</p><button class="button button-primary" id="start-exam">Start simulation</button><div id="exam-area"></div></section><section class="panel" style="max-width:760px;margin-top:16px"><h2>Recent score reports</h2><div id="exam-history"><div class="loading-state">Loading your reports…</div></div></section>`;
  loadExamHistory();
  document.querySelector('#start-exam').addEventListener('click', startExam);
}
async function loadExamHistory() {
  const target = document.querySelector('#exam-history');
  try {
    const { data, error } = await supabase.from('exam_attempts').select('id,status,score_percentage,started_at,completed_at,exam_sets(title)').eq('user_id', user.id).order('started_at', { ascending: false }).limit(6);
    if (error) throw error;
    target.innerHTML = data?.length ? data.map(row => `<article class="lesson-row"><div><h3>${esc(row.exam_sets?.title || 'TOEFL-style practice')}</h3><small>${row.status === 'completed' ? `Completed · ${new Date(row.completed_at).toLocaleDateString()}` : row.status === 'abandoned' ? 'Time expired before submission' : 'In progress'}</small></div>${row.status === 'in_progress' ? '<button class="button button-secondary" data-resume>Resume</button>' : `<strong>${row.score_percentage == null ? 'Not scored' : `${row.score_percentage}%`}</strong>`}</article>`).join('') : '<div class="empty-state">You do not have a score report yet. Start a practice run when you are ready.</div>';
    target.querySelectorAll('[data-resume]').forEach(button => button.addEventListener('click', () => startExam(button)));
  } catch (error) { target.innerHTML = `<p class="notice error">${esc(backendMessage(error))}</p>`; }
}
async function startExam(button = document.querySelector('#start-exam')) {
  const launchButtons = [...document.querySelectorAll('#start-exam,[data-resume]')];
  const originalLabels = launchButtons.map(item => item.textContent);
  launchButtons.forEach(item => { item.disabled = true; });
  if (button) button.textContent = 'Preparing questions…';
  try {
    const { data, error } = await supabase.rpc('start_toefl_attempt');
    if (error) throw error;
    renderExam(data);
  } catch (error) { notify(backendMessage(error), 'error'); launchButtons.forEach((item, index) => { item.disabled = false; item.textContent = originalLabels[index]; }); }
}
function renderExam(exam) {
  const target = document.querySelector('#exam-area');
  const questions = exam.questions || [];
  const pendingSaves = new Map();
  const elapsed = exam.started_at ? Math.max(0, Math.floor((Date.now() - Date.parse(exam.started_at)) / 1000)) : 0;
  let remaining = Math.max(0, (exam.duration_seconds || 1200) - elapsed);
  let completed = false;
  const savedAnswers = new Map((exam.saved_answers || []).map(item => [item.question_id, item.answer]));
  target.innerHTML = `<div class="exam-header"><div><h2>${esc(exam.title || 'Practice simulation')}</h2><p class="muted">${questions.length} questions · Writing and speaking responses are not included in the automatic score.</p></div><div class="exam-clock" id="exam-clock" role="timer" aria-live="off">${String(Math.floor(remaining / 60)).padStart(2,'0')}:${String(remaining % 60).padStart(2,'0')}</div></div><form id="exam-form">${questions.map((question, index) => `<fieldset class="exam-question" data-question="${esc(question.id)}" data-skill="${esc(question.category)}"><legend><span class="eyebrow">${esc(titleCase(question.category))} · ${index + 1}</span><br>${esc(question.prompt)}</legend>${question.passage ? `<p>${esc(question.passage)}</p>` : ''}${question.audio_script ? `<div class="audio-practice"><button class="button button-secondary" type="button" data-exam-audio>Play audio</button><details><summary>Read the transcript</summary><p>${esc(question.audio_script)}</p></details></div>` : ''}${question.options?.length ? question.options.map(option => `<label class="exam-option"><input type="radio" name="q-${esc(question.id)}" value="${esc(option.id)}" ${savedAnswers.get(question.id) === option.id ? 'checked' : ''}> ${esc(option.option_text)}</label>`).join('') : `<label class="field"><span class="sr-only">Your response</span><textarea data-response name="q-${esc(question.id)}" maxlength="1800" placeholder="Write or outline your response here.">${esc(savedAnswers.get(question.id) || '')}</textarea></label>${question.rubric ? `<p class="muted">${esc(question.rubric)}</p>` : ''}`}</fieldset>`).join('')}<button class="button button-primary" type="submit">Finish and score</button><p class="status" id="exam-status" role="status"></p></form>`;
  target.scrollIntoView({ behavior: 'smooth', block: 'start' });
  const status = document.querySelector('#exam-status');
  const persistAnswer = createAnswerQueue(async (questionId, answer) => {
    const { error } = await supabase.rpc('submit_toefl_answer', { p_attempt_id: exam.attempt_id, p_question_id: questionId, p_answer: answer });
    if (error) throw error;
  });
  const saveAnswer = async (questionId, answer) => {
    if (completed || !answer?.trim()) return;
    const promise = persistAnswer(questionId, answer.trim());
    promise.catch(error => { if (!completed) { status.textContent = backendMessage(error); status.dataset.kind = 'error'; } });
    pendingSaves.set(questionId, promise);
    return promise;
  };
  document.querySelectorAll('.exam-question').forEach(fieldset => {
    const questionId = fieldset.dataset.question;
    fieldset.querySelectorAll('input[type=radio]').forEach(input => input.addEventListener('change', () => saveAnswer(questionId, input.value)));
    const textarea = fieldset.querySelector('textarea');
    if (textarea && fieldset.dataset.skill === 'speaking') attachSpeechInput(fieldset, textarea, 'Speak your response');
    textarea?.addEventListener('change', () => saveAnswer(questionId, textarea.value));
    textarea?.addEventListener('blur', () => saveAnswer(questionId, textarea.value));
  });
  document.querySelectorAll('[data-exam-audio]').forEach(button => button.addEventListener('click', () => {
    const text = button.closest('.exam-question').querySelector('details p')?.textContent;
    if (!text || !('speechSynthesis' in window)) return notify('Audio playback is not available in this browser.', 'error');
    window.speechSynthesis.cancel(); const speech = new SpeechSynthesisUtterance(text); speech.lang = 'en-US'; speech.rate = .9; window.speechSynthesis.speak(speech);
  }));
  examTimer = setInterval(async () => {
    remaining = Math.max(0, remaining - 1);
    document.querySelector('#exam-clock').textContent = `${String(Math.floor(remaining / 60)).padStart(2, '0')}:${String(remaining % 60).padStart(2, '0')}`;
    if (!remaining) { clearInterval(examTimer); status.textContent = 'Time is up. We are scoring the answers saved so far.'; await finish(true); }
  }, 1000);
  const finish = async timedOut => {
    if (completed) return;
    const form = document.querySelector('#exam-form');
    const answers = new Map();
    for (const question of questions) {
      const answer = form.elements[`q-${question.id}`];
      const value = answer?.length ? [...answer].find(input => input.checked)?.value : answer?.value?.trim();
      if (value) answers.set(question.id, value);
      else if (!timedOut) { status.textContent = 'Please answer each question before finishing.'; questionElementFocus(question.id); return; }
    }
    try {
    if (!timedOut) {
      for (const [questionId, answer] of answers) await saveAnswer(questionId, answer);
    }
    await Promise.all(pendingSaves.values());
    } catch (error) { status.textContent = `Answers could not be saved: ${backendMessage(error)}. Retry before finishing.`; status.dataset.kind = 'error'; return; }
    const button = form.querySelector('button[type="submit"]'); button.disabled = true; button.textContent = 'Scoring…';
    try {
      const { data, error } = await supabase.rpc('finish_toefl_attempt', { p_attempt_id: exam.attempt_id });
      if (error) throw error;
      completed = true; clearInterval(examTimer);
      const report = typeof data === 'string' ? JSON.parse(data) : data;
      target.innerHTML = `<div class="feedback"><h2>Your practice score</h2><p><strong>${report.score_percentage}%</strong> overall · ${report.correct_answers} of ${report.total_questions} objectively scored answers. This is a FluentPath practice score, not an official TOEFL score.</p><p>${esc(report.feedback || '')}</p><div class="skill-breakdown"><h3>By skill</h3>${(report.skill_breakdown || []).map(item => `<div class="skill-score"><span>${esc(titleCase(item.category))}</span><strong>${item.total ? `${item.score_percentage}% (${item.correct}/${item.total})` : 'Practice response'}</strong></div>`).join('')}</div><section class="exam-review"><h3>Answer review</h3>${(report.review || []).map(item => `<article><div class="eyebrow">${esc(titleCase(item.category))}</div><h4>${esc(item.prompt)}</h4><p>${item.is_correct ? 'Correct' : 'Review this answer'} · Your answer: ${esc(item.selected_answer || 'No answer submitted')}</p>${!item.is_correct ? `<p><strong>Suggested answer:</strong> ${esc(item.correct_answer || '')}</p>` : ''}<p>${esc(item.explanation || '')}</p></article>`).join('')}</section><p>Writing and speaking responses were saved as practice and are not included in this automatic score.</p><p>${report.xp_awarded ? `You earned ${report.xp_awarded} XP.` : ''}</p><a class="button button-secondary" href="#/toefl">Back to TOEFL practice</a></div>`;
      await loadProfile();
      await loadExamHistory();
      const startButton = document.querySelector('#start-exam');
      if (startButton) { startButton.disabled = false; startButton.textContent = 'Start another simulation'; }
    } catch (error) {
      button.disabled = false; button.textContent = timedOut ? 'Retry score report' : 'Finish and score';
      status.textContent = backendMessage(error); status.dataset.kind = 'error';
      if (timedOut && /Answer each question/.test(backendMessage(error))) setTimeout(() => finish(true), 1200);
    }
  };
  document.querySelector('#exam-form').addEventListener('submit', async event => {
    event.preventDefault(); await finish(false);
  });
}
function questionElementFocus(id) { document.querySelector(`[data-question="${CSS.escape(id)}"]`)?.scrollIntoView({ behavior: 'smooth', block: 'center' }); }

async function communityPage() {
  setHeading('Community');
  view.innerHTML = '<div class="loading-state">Loading the community…</div>';
  try {
    const [threadsResult, peopleResult] = await Promise.all([
      supabase.from('forum_threads').select('id,user_id,title,body,created_at,reply_count').eq('status', 'published').order('created_at', { ascending: false }).limit(40),
      supabase.from('community_profiles').select('id,full_name,current_cefr_level')
    ]);
    if (threadsResult.error) throw threadsResult.error;
    if (peopleResult.error) throw peopleResult.error;
    const posts = threadsResult.data || [];
    const people = new Map((peopleResult.data || []).map(person => [person.id, person]));
    view.innerHTML = `${pageHead('Learn with others', 'Community', 'Share a question, offer a useful answer, and keep the conversation kind.', '<button class="button button-primary" id="new-thread">Write a post</button>')}<section class="panel">${posts.length ? posts.map(post => { const person = people.get(post.user_id); return `<article class="forum-post" data-thread="${esc(post.id)}"><div class="forum-meta"><span>${esc(person?.full_name || 'Learner')}</span><span>${esc(person?.current_cefr_level || '')}</span><time datetime="${esc(post.created_at)}">${new Date(post.created_at).toLocaleDateString()}</time></div><h3>${esc(post.title)}</h3><p>${esc(post.body)}</p><div class="post-actions"><button data-replies="${esc(post.id)}">${post.reply_count || 0} replies</button><button data-report="${esc(post.id)}">Report post</button></div><div class="reply-list" id="replies-${esc(post.id)}" hidden></div></article>`; }).join('') : '<div class="empty-state"><h2>Start a conversation</h2><p>There are no community posts yet. Share something you are working on.</p></div>'}</section><dialog class="app-dialog" id="thread-dialog"><form id="thread-form"><div class="panel-heading"><h2>Write a post</h2><button type="button" class="icon-close" data-close-dialog aria-label="Close">×</button></div><div class="field"><label for="thread-title">Title</label><input id="thread-title" maxlength="120" required></div><div class="field"><label for="thread-body">Message</label><textarea id="thread-body" maxlength="3000" required></textarea></div><button class="button button-primary" type="submit">Publish post</button><p class="status" id="thread-status" role="status"></p></form></dialog><dialog class="app-dialog" id="reply-dialog"><form id="reply-form"><div class="panel-heading"><h2>Reply to this post</h2><button type="button" class="icon-close" data-close-dialog aria-label="Close">×</button></div><input id="reply-thread" type="hidden"><div class="field"><label for="reply-body">Your reply</label><textarea id="reply-body" maxlength="2000" required></textarea></div><button class="button button-primary" type="submit">Send reply</button><p class="status" id="reply-status" role="status"></p></form></dialog>`;
    const threadDialog = document.querySelector('#thread-dialog'); const replyDialog = document.querySelector('#reply-dialog');
    document.querySelector('#new-thread').addEventListener('click', () => threadDialog.showModal());
    document.querySelectorAll('[data-close-dialog]').forEach(button => button.addEventListener('click', () => button.closest('dialog').close()));
    document.querySelectorAll('[data-replies]').forEach(button => button.addEventListener('click', async () => {
      const id = button.dataset.replies; const target = document.querySelector(`#replies-${CSS.escape(id)}`);
      if (!target.hidden) { target.hidden = true; return; }
      target.hidden = false; target.innerHTML = '<p class="muted">Loading replies…</p>';
      const { data, error } = await supabase.from('forum_replies').select('id,user_id,body,created_at').eq('thread_id', id).eq('status', 'published').order('created_at');
      if (error) { target.innerHTML = `<p class="notice error">${esc(backendMessage(error))}</p>`; return; }
      const memberResult = data?.length ? await supabase.from('community_profiles').select('id,full_name').in('id', data.map(item => item.user_id)) : { data: [], error: null };
      if (memberResult.error) { target.innerHTML = `<p class="notice error">${esc(backendMessage(memberResult.error))}</p>`; return; }
      const memberData = memberResult.data;
      const members = new Map((memberData || []).map(item => [item.id, item.full_name]));
      target.innerHTML = `${data?.length ? data.map(reply => `<div class="reply"><div class="forum-meta"><b>${esc(members.get(reply.user_id) || 'Learner')}</b><time>${new Date(reply.created_at).toLocaleDateString()}</time></div><p>${esc(reply.body)}</p><button class="button button-text" data-reply-report="${esc(reply.id)}">Report reply</button></div>`).join('') : '<p class="muted">No replies yet.</p>'}<button class="button button-secondary" data-reply-to="${esc(id)}">Write a reply</button>`;
      target.querySelector('[data-reply-to]').addEventListener('click', () => { document.querySelector('#reply-thread').value = id; replyDialog.showModal(); });
      target.querySelectorAll('[data-reply-report]').forEach(reportButton => reportButton.addEventListener('click', async () => {
        const reason = await askReportReason();
        if (!reason?.trim()) return;
        const { error } = await supabase.rpc('report_forum_content', { p_content_type: 'reply', p_content_id: reportButton.dataset.replyReport, p_reason: reason.trim() });
        notify(error ? backendMessage(error) : 'Your report has been sent to the moderators.', error ? 'error' : 'success');
      }));
    }));
    document.querySelectorAll('[data-report]').forEach(button => button.addEventListener('click', async () => {
      const reason = await askReportReason();
      if (!reason?.trim()) return;
      const { error } = await supabase.rpc('report_forum_content', { p_content_type: 'thread', p_content_id: button.dataset.report, p_reason: reason.trim() });
      notify(error ? backendMessage(error) : 'Your report has been sent to the moderators.', error ? 'error' : 'success');
    }));
    document.querySelector('#thread-form').addEventListener('submit', async event => {
      event.preventDefault(); const button = event.currentTarget.querySelector('button[type=submit]'); button.disabled = true;
      const { data, error } = await supabase.rpc('create_forum_thread', { p_title: document.querySelector('#thread-title').value.trim(), p_body: document.querySelector('#thread-body').value.trim() });
      if (error) { document.querySelector('#thread-status').textContent = backendMessage(error); button.disabled = false; return; }
      threadDialog.close(); await communityPage(); notify('Your post is published.');
    });
    document.querySelector('#reply-form').addEventListener('submit', async event => {
      event.preventDefault(); const button = event.currentTarget.querySelector('button[type=submit]'); button.disabled = true;
      const { error } = await supabase.rpc('create_forum_reply', { p_thread_id: document.querySelector('#reply-thread').value, p_body: document.querySelector('#reply-body').value.trim() });
      if (error) { document.querySelector('#reply-status').textContent = backendMessage(error); button.disabled = false; return; }
      replyDialog.close(); await communityPage(); notify('Your reply has been posted.');
    });
  } catch (error) { view.innerHTML = errorBox(error); bindReload(); }
}

async function adminPage() {
  setHeading('Admin desk');
  if (profile.role !== 'admin') { view.innerHTML = `<div class="panel error-state"><h2>Administrator access required</h2><p>Your account does not have access to the admin desk.</p></div>`; return; }
  view.innerHTML = '<div class="loading-state">Loading the admin desk…</div>';
  try {
    const [lessonsResult, reportsResult, usersResult] = await Promise.all([
      supabase.from('lessons').select('id,title,slug,cefr_level,category,is_published').order('created_at', { ascending: false }),
      supabase.from('forum_reports').select('id,content_type,content_id,reason,status,created_at').eq('status', 'open').order('created_at', { ascending: true }),
      profile.role === 'admin' ? supabase.rpc('admin_list_users') : Promise.resolve({ data: [], error: null })
    ]);
    if (lessonsResult.error) throw lessonsResult.error;
    if (reportsResult.error) throw reportsResult.error;
    if (usersResult.error) throw usersResult.error;
    const reports = reportsResult.data || [];
    const threadIds = reports.filter(item => item.content_type === 'thread').map(item => item.content_id);
    const replyIds = reports.filter(item => item.content_type === 'reply').map(item => item.content_id);
    const [reportedThreads, reportedReplies] = await Promise.all([
      threadIds.length ? supabase.from('forum_threads').select('id,title,body').in('id', threadIds) : Promise.resolve({ data: [], error: null }),
      replyIds.length ? supabase.from('forum_replies').select('id,body').in('id', replyIds) : Promise.resolve({ data: [], error: null })
    ]);
    if (reportedThreads.error) throw reportedThreads.error;
    if (reportedReplies.error) throw reportedReplies.error;
    const reportContent = new Map([...(reportedThreads.data || []).map(row => [row.id, row]), ...(reportedReplies.data || []).map(row => [row.id, row])]);
    view.innerHTML = `${pageHead('Authorized staff', 'Admin desk', 'Manage published learning content and review community reports.')}<div class="app-grid"><div class="stack"><section class="panel"><div class="panel-heading"><h2>Learning content</h2><button class="button button-primary" id="add-lesson">Add lesson</button></div><div class="admin-lesson-list">${(lessonsResult.data || []).map(lesson => `<div class="lesson-row"><div><h3>${esc(lesson.title)}</h3><small>${lesson.cefr_level} · ${titleCase(lesson.category)} · ${lesson.is_published ? 'Published' : 'Draft'}</small></div><div class="form-actions"><button class="button button-secondary" data-edit-content="${lesson.id}" data-title="${esc(lesson.title)}" data-category="${lesson.category}">Manage</button><button class="button button-secondary" data-publish="${lesson.id}" data-state="${lesson.is_published}">${lesson.is_published ? 'Unpublish' : 'Publish'}</button></div></div>`).join('')}</div></section><section class="panel"><h2>Open reports</h2>${reports.length ? reports.map(report => { const item = reportContent.get(report.content_id); return `<article class="forum-post"><div class="forum-meta"><span>${esc(titleCase(report.content_type))}</span><time>${new Date(report.created_at).toLocaleDateString()}</time></div><h3>${esc(item?.title || 'Reported reply')}</h3><p>${esc(item?.body || 'The reported content is unavailable.')}</p><div class="notice"><strong>Report:</strong> ${esc(report.reason)}</div><div class="post-actions"><button data-resolve="${report.id}">Resolve report</button><button data-remove-content="${report.content_type}:${report.content_id}">Hide content</button></div></article>`; }).join('') : '<div class="empty-state">There are no open reports.</div>'}</section></div><div class="stack">${profile.role === 'admin' ? `<section class="panel"><h2>Member access</h2><p class="muted">Administrators can adjust roles and suspend accounts.</p><div id="admin-users">${(usersResult.data || []).map(member => `<div class="member-row"><div class="member-main"><h3>${esc(member.full_name || member.email || 'Member')}</h3><small>${esc(member.email || '')} · ${esc(member.role)}${member.is_banned ? ' · Suspended' : ''}</small></div><div class="member-actions"><select aria-label="Role for ${esc(member.full_name || 'member')}" data-member-role="${member.id}" ${member.role === 'admin' ? 'disabled' : ''}>${['student','moderator','admin'].map(role => `<option value="${role}" ${role === member.role ? 'selected' : ''}>${titleCase(role)}</option>`).join('')}</select><button class="button ${member.is_banned ? 'button-secondary' : 'button-danger'}" data-ban="${member.id}" data-banned="${member.is_banned}" ${member.role === 'admin' ? 'disabled' : ''}>${member.is_banned ? 'Restore' : 'Suspend'}</button></div></div>`).join('')}</div></section>` : ''}<section class="panel"><h2>Content checklist</h2><p class="muted">Add a lesson note and at least one complete exercise before publishing. Objective exercises need answer choices with one correct answer.</p></section></div></div><dialog id="lesson-dialog" class="app-dialog"><form id="lesson-form"><div class="panel-heading"><h2>Add a lesson</h2><button type="button" class="icon-close" data-close-dialog aria-label="Close">×</button></div><div class="field"><label for="new-title">Title</label><input id="new-title" maxlength="120" required></div><div class="field"><label for="new-slug">URL slug</label><input id="new-slug" maxlength="140" required pattern="[a-z0-9]+(-[a-z0-9]+)*"></div><div class="field"><label for="new-description">Description</label><textarea id="new-description" maxlength="500" required></textarea></div><div class="option-row"><div class="field"><label for="new-level">CEFR level</label><select id="new-level">${Object.keys(levelLabels).map(level => `<option>${level}</option>`).join('')}</select></div><div class="field"><label for="new-skill">Skill</label><select id="new-skill">${skills.map(skill => `<option value="${skill}">${titleCase(skill)}</option>`).join('')}</select></div></div><button class="button button-primary" type="submit">Save as draft</button><p class="status" id="lesson-status" role="status"></p></form></dialog><dialog id="content-dialog" class="app-dialog content-dialog"><div class="panel-heading"><div><span class="eyebrow">Lesson editor</span><h2 id="content-lesson-title"></h2></div><button type="button" class="icon-close" data-close-dialog aria-label="Close">×</button></div><div id="content-inventory"></div><form id="section-form"><h3>Add lesson note</h3><div class="field"><label for="section-title">Heading</label><input id="section-title" maxlength="120" required></div><div class="field"><label for="section-content">Explanation</label><textarea id="section-content" maxlength="5000" required></textarea></div><button class="button button-secondary" type="submit">Add note</button><p class="status" id="section-status" role="status"></p></form><form id="exercise-form"><h3>Add an exercise</h3><div class="field"><label for="exercise-prompt">Prompt</label><textarea id="exercise-prompt" maxlength="1000" required></textarea></div><div class="field" id="passage-field"><label for="exercise-passage">Reading passage or listening transcript</label><textarea id="exercise-passage" maxlength="4000"></textarea></div><div class="field"><label for="exercise-type">Response style</label><select id="exercise-type"><option value="multiple_choice">Choose an answer</option><option value="short_response">Write or speak a response</option></select></div><div id="choice-fields"><div class="field"><label for="choice-one">Choice 1</label><input id="choice-one" maxlength="300"></div><div class="field"><label for="choice-two">Choice 2</label><input id="choice-two" maxlength="300"></div><div class="field"><label for="choice-three">Choice 3</label><input id="choice-three" maxlength="300"></div><div class="field"><label for="correct-choice">Correct choice</label><select id="correct-choice"><option value="0">Choice 1</option><option value="1">Choice 2</option><option value="2">Choice 3</option></select></div></div><div class="field" id="rubric-field" hidden><label for="exercise-rubric">Feedback rubric</label><textarea id="exercise-rubric" maxlength="1500"></textarea></div><button class="button button-primary" type="submit">Save exercise</button><p class="status" id="exercise-status" role="status"></p></form></dialog>`;
    view.querySelectorAll('[data-publish]').forEach(button => button.addEventListener('click', async () => {
      const publish = button.dataset.state !== 'true';
      const { error } = await supabase.from('lessons').update({ is_published: publish }).eq('id', button.dataset.publish);
      if (error) return notify(backendMessage(error), 'error');
      await adminPage(); notify(publish ? 'Lesson published.' : 'Lesson moved to draft.');
    }));
    view.querySelectorAll('[data-edit-content]').forEach(button => button.addEventListener('click', async () => {
      const dialog = document.querySelector('#content-dialog');
      dialog.dataset.lessonId = button.dataset.editContent;
      dialog.dataset.category = button.dataset.category;
      document.querySelector('#content-lesson-title').textContent = button.dataset.title;
      const passageLabel = document.querySelector('#passage-field label');
      passageLabel.textContent = button.dataset.category === 'listening' ? 'Listening transcript' : 'Reading passage';
      document.querySelector('#passage-field').hidden = !['reading','listening'].includes(button.dataset.category);
      const target = document.querySelector('#content-inventory'); target.innerHTML = '<p class="muted">Loading lesson materials…</p>';
      dialog.showModal();
      const [sections, exercises] = await Promise.all([
        supabase.from('lesson_sections').select('title,section_type').eq('lesson_id', dialog.dataset.lessonId).order('order_index'),
        supabase.from('exercises').select('id,prompt,exercise_type,order_index').eq('lesson_id', dialog.dataset.lessonId).order('order_index')
      ]);
      if (sections.error || exercises.error) { target.innerHTML = `<p class="notice error">${esc(backendMessage(sections.error || exercises.error))}</p>`; return; }
      target.innerHTML = `<h3>Current materials</h3><ul class="inventory-list">${(sections.data || []).map(item => `<li>Note: ${esc(item.title)}</li>`).concat((exercises.data || []).map(item => `<li>Exercise: ${esc(item.prompt)} <small>(${esc(item.exercise_type.replaceAll('_',' '))})</small></li>`)).join('') || '<li>No materials added yet.</li>'}</ul>`;
    }));
    document.querySelectorAll('[data-member-role]').forEach(select => select.addEventListener('change', async () => {
      const { error } = await supabase.rpc('admin_set_user_role', { p_user_id: select.dataset.memberRole, p_role: select.value });
      if (error) { notify(backendMessage(error), 'error'); await adminPage(); return; } await adminPage(); notify('Member role updated.');
    }));
    view.querySelectorAll('[data-resolve]').forEach(button => button.addEventListener('click', async () => {
      const { error } = await supabase.rpc('moderate_forum_report', { p_report_id: button.dataset.resolve, p_decision: 'resolve' });
      if (error) return notify(backendMessage(error), 'error'); await adminPage(); notify('Report resolved.');
    }));
    view.querySelectorAll('[data-remove-content]').forEach(button => button.addEventListener('click', async () => {
      const [type, id] = button.dataset.removeContent.split(':');
      const { error } = await supabase.rpc('moderate_forum_content', { p_content_type: type, p_content_id: id, p_status: 'hidden' });
      if (error) return notify(backendMessage(error), 'error'); await adminPage(); notify('Content hidden.');
    }));
    view.querySelectorAll('[data-resolve]').forEach(button => {
      const dismiss = document.createElement('button');
      dismiss.type = 'button'; dismiss.textContent = 'Dismiss report';
      button.after(dismiss);
      dismiss.addEventListener('click', async () => {
        dismiss.disabled = true;
        const { error } = await supabase.rpc('moderate_forum_report', { p_report_id: button.dataset.resolve, p_decision: 'dismiss' });
        if (error) { dismiss.disabled = false; return notify(backendMessage(error), 'error'); }
        await adminPage(); notify('Report dismissed. No account restriction was issued.');
      });
    });
    view.querySelectorAll('[data-ban]').forEach(button => button.addEventListener('click', async () => {
      const banned = button.dataset.banned !== 'true';
      const { error } = await supabase.rpc('admin_set_user_ban', { p_user_id: button.dataset.ban, p_is_banned: banned });
      if (error) return notify(backendMessage(error), 'error'); await adminPage(); notify(banned ? 'Member banned.' : 'Member restored.');
    }));
    view.querySelectorAll('[data-ban]').forEach(button => { button.textContent = button.dataset.banned === 'true' ? 'Restore access' : 'Ban account'; });
    const dialog = document.querySelector('#lesson-dialog');
    document.querySelector('#add-lesson').addEventListener('click', () => dialog.showModal());
    document.querySelector('[data-close-dialog]').addEventListener('click', () => dialog.close());
    document.querySelector('#lesson-form').addEventListener('submit', async event => {
      event.preventDefault(); const button = event.currentTarget.querySelector('button[type=submit]'); button.disabled = true;
      const { error } = await supabase.from('lessons').insert({ title: document.querySelector('#new-title').value.trim(), slug: document.querySelector('#new-slug').value.trim(), description: document.querySelector('#new-description').value.trim(), cefr_level: document.querySelector('#new-level').value, category: document.querySelector('#new-skill').value, is_published: false });
      if (error) { document.querySelector('#lesson-status').textContent = backendMessage(error); document.querySelector('#lesson-status').dataset.kind = 'error'; button.disabled = false; return; }
      dialog.close(); await adminPage(); notify('Draft lesson created.');
    });
    document.querySelectorAll('#content-dialog [data-close-dialog]').forEach(button => button.addEventListener('click', () => button.closest('dialog').close()));
    for (const index of [0,1,2]) {
      const field = document.createElement('div'); field.className = 'field';
      const label = document.createElement('label'); label.htmlFor = `new-choice-feedback-${index}`; label.textContent = `Explanation for choice ${index+1}`;
      const textarea = document.createElement('textarea'); textarea.id = label.htmlFor; textarea.required = true; textarea.minLength = 5; textarea.maxLength = 1500;
      field.append(label,textarea); document.querySelector('#choice-fields').append(field);
    }
    document.querySelector('#exercise-type').addEventListener('change', event => {
      const writing = event.target.value === 'short_response';
      document.querySelector('#choice-fields').hidden = writing;
      document.querySelector('#rubric-field').hidden = !writing;
      document.querySelector('#choice-fields').querySelectorAll('input').forEach(input => input.required = !writing);
      document.querySelector('#choice-fields').querySelectorAll('textarea').forEach(input => { input.required = !writing; input.disabled = writing; });
      document.querySelector('#exercise-rubric').required = writing;
    });
    document.querySelector('#section-form').addEventListener('submit', async event => {
      event.preventDefault(); const button = event.currentTarget.querySelector('button[type=submit]'); button.disabled = true;
      const lessonId = document.querySelector('#content-dialog').dataset.lessonId;
      const { data: current } = await supabase.from('lesson_sections').select('order_index').eq('lesson_id', lessonId).order('order_index', { ascending: false }).limit(1);
      const { error } = await supabase.from('lesson_sections').insert({ lesson_id: lessonId, title: document.querySelector('#section-title').value.trim(), content: document.querySelector('#section-content').value.trim(), order_index: (current?.[0]?.order_index || 0) + 1 });
      if (error) { document.querySelector('#section-status').textContent = backendMessage(error); document.querySelector('#section-status').dataset.kind = 'error'; button.disabled = false; return; }
      event.currentTarget.reset(); document.querySelector('#section-status').textContent = 'Lesson note added.'; button.disabled = false;
      document.querySelector('#content-dialog').close();
      document.querySelector('[data-edit-content="' + CSS.escape(lessonId) + '"]')?.click();
    });
    document.querySelector('#exercise-form').addEventListener('submit', async event => {
      event.preventDefault(); const button = event.currentTarget.querySelector('button[type=submit]'); button.disabled = true;
      const lessonId = document.querySelector('#content-dialog').dataset.lessonId;
      const type = document.querySelector('#exercise-type').value;
      const options = type === 'short_response' ? [] : [0,1,2].map(index => ({ option_text: document.querySelector(`#choice-${['one','two','three'][index]}`).value.trim(), is_correct: Number(document.querySelector('#correct-choice').value) === index, explanation: document.querySelector(`#new-choice-feedback-${index}`).value.trim() }));
      const { error } = await supabase.rpc('admin_save_material', { p_kind: 'exercise', p_id: null, p_data: { lesson_id: lessonId, exercise_type: type, prompt: document.querySelector('#exercise-prompt').value.trim(), passage: document.querySelector('#exercise-passage').value.trim() || null, rubric: document.querySelector('#exercise-rubric').value.trim(), options } });
      if (error) { document.querySelector('#exercise-status').textContent = backendMessage(error); document.querySelector('#exercise-status').dataset.kind = 'error'; button.disabled = false; return; }
      event.currentTarget.reset(); document.querySelector('#exercise-status').textContent = 'Exercise added.'; button.disabled = false;
      document.querySelector('#exercise-type').dispatchEvent(new Event('change'));
      document.querySelector('#content-dialog').close();
      document.querySelector('[data-edit-content="' + CSS.escape(lessonId) + '"]')?.click();
    });
    document.querySelector('#exercise-type').dispatchEvent(new Event('change'));
    await mountWorkbench(view, notify);
  } catch (error) { view.innerHTML = errorBox(error); bindReload(); }
}

async function route() {
  clearInterval(examTimer);
  try { await loadProfile(); }
  catch (error) { view.innerHTML = errorBox(error); bindReload(); return; }
  if (profile.is_banned || (profile.suspended_until && Date.parse(profile.suspended_until) > Date.now())) {
    view.innerHTML = '<section class="panel error-state"><h1>Account access restricted</h1><p>Contact an administrator to request a review. You can sign out using the navigation.</p></section>';
    return;
  }
  const path = location.hash.replace(/^#\/?/, '') || 'dashboard';
  const [name, ...args] = path.split('/');
  document.querySelectorAll('.sidebar nav a[data-route]').forEach(link => link.setAttribute('aria-current', link.dataset.route === name ? 'page' : 'false'));
  document.querySelector('#mobile-nav').hidden = true;
  document.querySelector('#mobile-menu').setAttribute('aria-expanded', 'false');
  try {
    if (name === 'dashboard') return await dashboard();
    if (name === 'path') return await pathPage();
    if (name === 'academy') return await academyPage();
    if (name === 'lesson') return await lessonPage(decodeURIComponent(args.join('/')));
    if (name === 'leaderboard') return await leaderboardPage();
    if (name === 'profile') return await profilePage();
    if (name === 'toefl') return await toeflPage();
    if (name === 'community') { await communityPage(); await mountMyReports(view); return; }
    if (name === 'admin') {
      await adminPage();
      return;
    }
    location.hash = '#/dashboard';
  } catch (error) { view.innerHTML = errorBox(error); bindReload(); }
}

document.querySelector('#mobile-menu').addEventListener('click', event => {
  const open = event.currentTarget.getAttribute('aria-expanded') !== 'true';
  event.currentTarget.setAttribute('aria-expanded', String(open));
  document.querySelector('#mobile-nav').hidden = !open;
});
document.querySelector('#mobile-nav').addEventListener('click', event => {
  if (event.target.closest('a')) { document.querySelector('#mobile-menu').setAttribute('aria-expanded', 'false'); document.querySelector('#mobile-nav').hidden = true; }
});
async function logout() {
  const { error } = await supabase.auth.signOut(); if (error) return notify(backendMessage(error), 'error'); location.assign('/login.html');
}
document.querySelector('#logout').addEventListener('click', logout);
document.querySelector('#mobile-logout').addEventListener('click', logout);
document.querySelector('#profile-link').addEventListener('click', () => { location.hash = '#/profile'; });
document.querySelector('#top-avatar').addEventListener('click', () => { location.hash = '#/profile'; });
window.addEventListener('hashchange', route);

if (!supabase) {
  view.innerHTML = `<div class="panel error-state"><h2>Supabase is not configured</h2><p>${esc(backendMessage())}</p></div>`;
} else {
  const { data: { user: currentUser }, error } = await supabase.auth.getUser();
  if (error || !currentUser) location.replace('/login.html');
  else {
    user = currentUser;
    try {
      await loadProfile();
      if (profile.is_banned) view.innerHTML = `<div class="panel error-state"><h2>This account is suspended</h2><p>Contact a FluentPath administrator if you think this is a mistake.</p><button class="button button-secondary" id="suspended-logout">Sign out</button></div>`;
      else await route();
      document.querySelector('#suspended-logout')?.addEventListener('click', logout);
    }
    catch (profileError) { view.innerHTML = errorBox(profileError); bindReload(); }
  }
}
