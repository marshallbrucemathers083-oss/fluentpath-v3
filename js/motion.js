const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
const seen = new WeakSet();
const observer = 'IntersectionObserver' in window ? new IntersectionObserver(entries => {
  for (const entry of entries) {
    if (!entry.isIntersecting) continue;
    observer.unobserve(entry.target);
    if (!reduced.matches) entry.target.animate([{ opacity: .8, transform: 'translateY(5px)' }, { opacity: 1, transform: 'translateY(0)' }], { duration: 180, easing: 'ease-out' });
  }
}, { threshold: .08 }) : null;

export function observeLearningMotion(view) {
  const watch = () => {
    for (const element of view.querySelectorAll('.exercise-card, .lesson-row, .forum-post')) {
      if (seen.has(element)) continue;
      seen.add(element); observer?.observe(element);
    }
  };
  new MutationObserver(watch).observe(view, { childList: true, subtree: true });
  watch();
}
