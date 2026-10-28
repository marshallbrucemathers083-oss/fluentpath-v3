const toggle = document.querySelector('.nav-toggle');
const nav = document.querySelector('#primary-nav');
toggle?.addEventListener('click', () => {
  const open = toggle.getAttribute('aria-expanded') !== 'true';
  toggle.setAttribute('aria-expanded', String(open));
  nav?.setAttribute('data-open', String(open));
});
nav?.querySelectorAll('a').forEach(link => link.addEventListener('click', () => {
  toggle?.setAttribute('aria-expanded', 'false');
  nav.setAttribute('data-open', 'false');
}));
