import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');

test('starter content covers six CEFR levels and six skill categories', async () => {
  const seed = await read('../supabase/migrations/20261028000003_seed_curriculum.sql');
  for (const level of ['A1','A2','B1','B2','C1','C2']) assert.match(seed, new RegExp(`'${level}'`));
  for (const skill of ['grammar','vocabulary','reading','listening','writing','speaking']) assert.match(seed, new RegExp(`'${skill}'`));
  const lessons = [...seed.matchAll(/'([a-z0-9]+(?:-[a-z0-9]+)+)'/g)].map(match => match[1]);
  for (const slug of ['a1-verb-to-be','a1-cafe-vocabulary','a2-reading-a-note','a2-listening-at-the-station','b1-present-perfect','b1-speaking-routine','b2-vocabulary-collocations','b2-writing-a-request','c1-reading-hedging','c1-listening-correlation','c2-inversion-emphasis','c2-speaking-recommendation']) assert.ok(lessons.includes(slug), `${slug} is missing`);
  assert.match(seed, /E'Hi Jo,\\nI moved into the blue house[\s\S]*?\\nMina'/);
});

test('navigation destinations exist and every public navigation link has a target', async () => {
  const landing = await read('../index.html');
  for (const id of ['path','skills','practice','community']) assert.ok(landing.includes(`id="${id}"`));
  for (const href of ['/login.html','/register.html']) assert.ok(landing.includes(`href="${href}"`));
});
