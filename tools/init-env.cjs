const fs = require('node:fs');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const root = path.resolve(__dirname, '..');
const target = path.join(root, '.env');
if (fs.existsSync(target)) throw new Error('Root .env exists; refusing to overwrite secrets.');
let env = fs.readFileSync(path.join(root, '.env.example'), 'utf8');
for (const placeholder of ['replace-local-password','replace-with-at-least-32-random-characters','replace-with-a-different-32-character-secret','replace-local-access-key','replace-local-storage-secret']) {
  env = env.replaceAll(placeholder, randomBytes(32).toString('hex'));
}
fs.writeFileSync(target, env, { flag: 'wx' });
const backend = path.join(root, 'backend', '.env');
if (!fs.existsSync(backend)) fs.writeFileSync(backend, env, { flag: 'wx' });
console.log('Created ignored local environment files; values are not printed.');
