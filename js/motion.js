const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
const seen = new WeakSet();
const running = new Set();
export function reveal(element, delay = 0) {
  if (!element || reduced.matches || !element.animate) return;
  const animation = element.animate([
    { opacity: 0, transform: 'translateY(12px)' },
    { opacity: 1, transform: 'translateY(0)' }
  ], { duration: 480, delay, easing: 'cubic-bezier(.2,.7,.2,1)', fill: 'backwards' });
  running.add(animation);
  animation.finished.catch(() => {}).finally(() => running.delete(animation));
}
reduced.addEventListener('change', () => {
  if (reduced.matches) for (const animation of running) animation.cancel();
});
const observer = 'IntersectionObserver' in window ? new IntersectionObserver(entries => {
  let index = 0;
  for (const entry of entries) {
    if (!entry.isIntersecting) continue;
    observer.unobserve(entry.target);
    reveal(entry.target, Math.min(index++ * 55, 220));
  }
}, { threshold: .12 }) : null;
export function observeLearningMotion(view) {
  const watch = () => {
    for (const element of view.querySelectorAll('.section-heading, .level, .skill-list li, .practice-strip, .community-line, .page-head, .lesson-section, .exercise-card, .forum-post, .panel-heading')) {
      if (seen.has(element)) continue;
      seen.add(element);
      observer?.observe(element);
    }
  };
  const mutations = new MutationObserver(watch);
  mutations.observe(view, { childList: true, subtree: true });
  watch();
  return () => { mutations.disconnect(); };
}

// Keep menus in document flow; defer hiding until the closing feedback finishes.
export function setMenu(toggle, nav, open, landing = false) {
  nav.getAnimations().forEach(animation => animation.cancel());
  toggle.setAttribute('aria-expanded', String(open));
  nav.inert = !open;
  const show = () => landing ? nav.setAttribute('data-open', 'true') : nav.hidden = false;
  const hide = () => landing ? nav.setAttribute('data-open', 'false') : nav.hidden = true;
  if (open) { show(); reveal(nav); }
  else if (reduced.matches || !nav.animate) hide();
  else {
    const animation = nav.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 180, easing: 'ease-out' });
    animation.finished.then(hide).catch(() => {});
  }
}
