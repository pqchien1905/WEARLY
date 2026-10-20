import { createRequire } from 'node:module';
import { mkdtempSync, writeFileSync, unlinkSync, rmdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const fromBackend = createRequire(join(__dirname, '../package.json'));
const { loadNycConfig } = fromBackend('@istanbuljs/load-nyc-config') as {
  loadNycConfig(options: { cwd: string }): Promise<Record<string, unknown>>;
};
describe('Coverage YAML configuration compatibility', () => {
  it('loads inherited YAML arrays, flags and thresholds and rejects malformed YAML', async () => {
    const directory = mkdtempSync(join(tmpdir(), 'wearly-nyc-'));
    const files = ['package.json', 'base.yml', '.nycrc.yml'];
    try {
      writeFileSync(
        join(directory, files[0]),
        '{"name":"synthetic-coverage-fixture"}',
      );
      writeFileSync(
        join(directory, files[1]),
        'exclude:\n  - test/**\nall: true\n',
      );
      writeFileSync(
        join(directory, files[2]),
        'extends: ./base.yml\ninclude:\n  - src/**/*.ts\nextension: .ts\ncheck-coverage: true\nlines: 80\n',
      );
      const loaded = await loadNycConfig({ cwd: directory });
      expect(loaded).toMatchObject({
        cwd: directory,
        exclude: ['test/**'],
        include: ['src/**/*.ts'],
        extension: ['.ts'],
        all: true,
        checkCoverage: true,
        lines: 80,
      });
      writeFileSync(join(directory, files[2]), 'include: [unfinished\n');
      await expect(loadNycConfig({ cwd: directory })).rejects.toThrow();
    } finally {
      // Only exact synthetic files; no recursive deletion or computed shell commands.
      for (const file of files) {
        try {
          unlinkSync(join(directory, file));
        } catch {
          /* not created yet */
        }
      }
      rmdirSync(directory);
    }
  });
});
