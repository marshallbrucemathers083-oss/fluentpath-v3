import { cp, mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
export async function buildSite(root = process.cwd()) {
  const out = path.join(root, 'dist');
  await rm(out, { recursive: true, force: true }); await mkdir(out);
  for (const entry of await readdir(root)) {
    if (entry.endsWith('.html') || ['_headers','_redirects'].includes(entry)) await cp(path.join(root,entry),path.join(out,entry));
  }
  for (const directory of ['css','js']) await cp(path.join(root,directory),path.join(out,directory),{ recursive: true });
  await writeFile(path.join(out,'404.html'), '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Page not found · FluentPath</title><link rel="stylesheet" href="/css/tokens.css"><link rel="stylesheet" href="/css/base.css"><main class="wrap"><h1>Page not found</h1><p>This address is unavailable.</p><a class="button button-primary" href="/">Return to FluentPath</a></main></html>');
  const files = await readdir(out,{recursive:true});
  for (const file of files) {
    if (!/\.(html|js|css)$/.test(file)) continue;
    const content = await readFile(path.join(out,file),'utf8');
    if (/sb_secret_[A-Za-z0-9_-]+|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(content)) throw new Error(`Secret detected in ${file}`);
    for (const match of content.matchAll(/(?:src|href)=["'](\/[^"'#?]*)["']/g)) {
      if (match[1] === '/') continue;
      if (!files.includes(match[1].slice(1))) throw new Error(`Missing public asset: ${file} -> ${match[1]}`);
    }
  }
  return files;
}
if (process.argv[1] === new URL(import.meta.url).pathname) console.log(`Built ${(await buildSite()).length} public entries in dist/`);
