import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

const [service, action, encodedBody] = process.argv.slice(2);
if (!service || !action) {
  console.error('Usage: node tool/tcb_api.mjs <service> <action> [base64-json]');
  process.exit(2);
}

const cli = join(
  process.env.APPDATA,
  'npm',
  'node_modules',
  '@cloudbase',
  'cli',
  'bin',
  'tcb',
);
const args = [cli, 'api', service, action, '--json'];
if (encodedBody) {
  args.push('--body', Buffer.from(encodedBody, 'base64').toString('utf8'));
}
const result = spawnSync(process.execPath, args, {
  encoding: 'utf8',
  stdio: ['ignore', 'pipe', 'pipe'],
});
if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
process.exit(result.status ?? 1);
