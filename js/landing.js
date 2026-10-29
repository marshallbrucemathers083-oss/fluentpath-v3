import { reveal, observeLearningMotion, setMenu } from './motion.js';
const toggle = document.querySelector('.nav-toggle');
const nav = document.querySelector('#primary-nav');
toggle?.addEventListener('click', () => setMenu(toggle, nav, toggle.getAttribute('aria-expanded') !== 'true', true));
nav?.querySelectorAll('a').forEach(link => link.addEventListener('click', () => { if (window.matchMedia('(max-width: 740px)').matches) setMenu(toggle, nav, false, true); }));
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && toggle?.getAttribute('aria-expanded') === 'true') {
    setMenu(toggle, nav, false, true);
    toggle.focus();
  }
});
// Desktop navigation must remain available after closing the mobile menu.
window.matchMedia('(min-width: 741px)').addEventListener('change', event => {
  if (event.matches) { nav.inert = false; nav.getAnimations().forEach(animation => animation.cancel()); }
});
const lessons = [...document.querySelectorAll('.preview-lesson')];
lessons.forEach((lesson, index) => {
  lesson.addEventListener('click', () => lessons.forEach(row => row.setAttribute('aria-pressed', String(row === lesson))));
  lesson.addEventListener('keydown', event => {
    let next;
    if (event.key === 'ArrowDown' || event.key === 'ArrowRight') next = (index + 1) % lessons.length;
    if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') next = (index + lessons.length - 1) % lessons.length;
    if (event.key === 'Home') next = 0;
    if (event.key === 'End') next = lessons.length - 1;
    if (next !== undefined) { event.preventDefault(); lessons[next].focus(); }
  });
});
['.hero .eyebrow', '.headline-line:first-child', '.headline-line:last-child', '.hero-copy', '.hero-actions', '.proofline', '.path-preview'].forEach((selector, index) => reveal(document.querySelector(selector), index * 65));
observeLearningMotion(document.querySelector('main'));
