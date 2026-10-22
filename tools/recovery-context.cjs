const fs = require('node:fs'), path = require('node:path');
const { createHash, randomUUID } = require('node:crypto');
const recovery = require('./native-recovery.cjs');
const postgres = require('./recovery-postgres.cjs');
function read(file) {
  if (fs.statSync(file).size > 16 * 1024 * 1024) throw Error('RECOVERY_INVALID_MANIFEST');
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}
function loadContext(workspace, reportFile, env) {
  if (!reportFile) throw Error('RECOVERY_CONTEXT_REQUIRED');
  const loc = recovery.locations(workspace), relative = path.relative(loc.base, path.resolve(reportFile)).split(path.sep).join('/');
  if (!/^restore-\d{13}_[a-f0-9]{8}\/result\.json$/.test(relative)) throw Error('RECOVERY_CONTEXT_REQUIRED');
  const file = recovery.safeFile(loc.base, relative), report = read(file);
  const config = recovery.validateConfig(env);
  if (report.version !== 1 || report.status !== 'complete' || report.stage !== 'QUARANTINED' || report.exactSnapshotVerified !== true ||
      report.target?.database !== config.database.database || report.target?.bucket !== config.bucket ||
      !/^\d{13}-[a-f0-9-]{36}$/.test(report.archive)) throw Error('RECOVERY_CONTEXT_MISMATCH');
  const manifestFile = recovery.safeFile(loc.base, report.archive + '/manifest.json'), directory = path.dirname(manifestFile), manifest = read(manifestFile);
  recovery.verifyFiles(directory, manifest);
  postgres.validateSnapshot(manifest.snapshot);
  if (!Array.isArray(manifest.bundled)) throw Error('RECOVERY_INVALID_MANIFEST');
  const indexed = new Map(manifest.files.map(row => [row.file, row]));
  let matches = true;
  for (const asset of manifest.bundled) {
    if (!/^frontend\/assets\/images\/[a-zA-Z0-9_.-]+$/.test(asset.source) || asset.file !== 'bundled/' + path.basename(asset.source) || !indexed.has(asset.file)) throw Error('RECOVERY_INVALID_MANIFEST');
    try {
      const source = recovery.safeFile(loc.workspace, asset.source);
      matches &&= fs.statSync(source).size === indexed.get(asset.file).size && createHash('sha256').update(fs.readFileSync(source)).digest('hex') === indexed.get(asset.file).sha256;
    } catch { matches = false; }
  }
  report.workspaceAssetsMatch = matches;
  delete report.applicationChecks;
  report.applicationCompatibility = { assets: matches ? 'verified' : 'mismatched', schema: 'unverified', api: 'unverified' };
  const save = () => {
    const temporary = recovery.safeFile(path.dirname(file), 'result-' + randomUUID() + '.tmp');
    fs.writeFileSync(temporary, JSON.stringify(report, null, 2), { flag: 'wx', mode: 0o600 });
    fs.renameSync(temporary, file);
  };
  save();
  if (!matches) throw Error('RECOVERY_ASSETS_MISMATCH');
  return { report, save, config };
}
module.exports = { loadContext };
