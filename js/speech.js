export function attachSpeechInput(container, textarea, buttonLabel = 'Speak your response') {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition || !container || !textarea) return;

  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'button button-secondary speech-button';
  button.textContent = buttonLabel;
  button.setAttribute('aria-pressed', 'false');
  const status = document.createElement('span');
  status.className = 'speech-status muted';
  status.setAttribute('role', 'status');
  status.setAttribute('aria-live', 'polite');
  button.insertAdjacentElement('afterend', status);
  container.insertBefore(button, textarea.closest('.field') || textarea);

  let recognition = null;
  button.addEventListener('click', () => {
    if (recognition) { recognition.stop(); return; }
    recognition = new SpeechRecognition();
    recognition.lang = 'en-US';
    recognition.continuous = true;
    recognition.interimResults = false;
    button.setAttribute('aria-pressed', 'true');
    button.textContent = 'Stop speaking';
    status.textContent = 'Listening. Speak clearly, then select Stop speaking.';
    recognition.onresult = event => {
      const words = [...event.results].slice(event.resultIndex).map(result => result[0].transcript.trim()).filter(Boolean).join(' ');
      if (!words) return;
      textarea.value = `${textarea.value.trim()} ${words}`.trim();
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
      textarea.dispatchEvent(new Event('change', { bubbles: true }));
    };
    recognition.onerror = event => { status.textContent = event.error === 'not-allowed' ? 'Microphone access was denied. You can type your response instead.' : 'Speech input stopped. You can continue by typing.'; };
    recognition.onend = () => {
      recognition = null;
      button.setAttribute('aria-pressed', 'false');
      button.textContent = buttonLabel;
      if (!status.textContent.includes('denied')) status.textContent = 'Speech input stopped. You can edit the transcript before submitting.';
    };
    try { recognition.start(); }
    catch {
      recognition = null;
      button.setAttribute('aria-pressed', 'false');
      button.textContent = buttonLabel;
      status.textContent = 'Speech input could not start. You can type your response instead.';
    }
  });
}
