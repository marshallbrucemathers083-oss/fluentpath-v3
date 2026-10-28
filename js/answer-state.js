export function createAnswerQueue(save) {
  let tail = Promise.resolve();
  return (...args) => {
    const result = tail.catch(() => {}).then(() => save(...args));
    tail = result;
    return result;
  };
}

export function parseFeedback(value, objective) {
  const result = typeof value === 'string' ? JSON.parse(value) : value;
  if (!result || (objective && typeof result.correct !== 'boolean')) {
    throw new Error('The server returned an invalid score. Please retry.');
  }
  return result;
}
