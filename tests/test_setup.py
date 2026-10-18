"""Exercise setup's Git synchronization without installing/building the app."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

INSTALLER = Path(__file__).resolve().parents[1] / 'install.sh'
FUNCTION = INSTALLER.read_text().split('prepare_source() {', 1)[1].split('# ── main', 1)[0]
FUNCTION = 'prepare_source() {' + FUNCTION
FUNCTION = FUNCTION.replace('exec bash "$SOURCE_DIR/setup.sh" "${ORIGINAL_ARGS[@]}"', 'echo ready')


class SetupTests(unittest.TestCase):
    def git(self, cwd, *args):
        return subprocess.check_output(['git', '-C', str(cwd), *args], stderr=subprocess.DEVNULL, text=True).strip()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.remote = self.root / 'remote'
        self.repo = self.root / 'checkout'
        self.remote.mkdir()
        self.git(self.remote, 'init', '-b', 'main')
        self.commit(self.remote, 'initial')
        self.git(self.root, 'clone', str(self.remote), str(self.repo))

    def commit(self, repo, text):
        (repo / 'file').write_text(text)
        self.git(repo, 'add', 'file')
        self.git(repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-m', text)

    def run_setup(self, check=False, source_dir=None, share_dir=None):
        env = dict(os.environ, SOURCE_DIR=str(source_dir or self.repo),
                   SHARE_DIR=str(share_dir or (self.root / 'share')),
                   SOURCE_REF='main', CHECK_ONLY=str(int(check)), SCREEN_AI_SOURCE_READY='0', REPO='unused')
        return subprocess.run(['bash', '-c', 'set -eu\nORIGINAL_ARGS=()\n' + FUNCTION + '\nprepare_source'], env=env, text=True, capture_output=True)

    def test_check_fetches_without_moving_checkout(self):
        previous = self.git(self.repo, 'rev-parse', 'HEAD')
        self.commit(self.remote, 'new version')
        result = self.run_setup(check=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [self.git(self.remote, 'rev-parse', 'HEAD'), 'new version'])
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), previous)

    def test_update_fast_forwards(self):
        self.commit(self.remote, 'new version')
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), self.git(self.remote, 'rev-parse', 'HEAD'))

    def test_dirty_checkout_is_preserved(self):
        (self.repo / 'file').write_text('local edits')
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('local changes', result.stderr)
        self.assertEqual((self.repo / 'file').read_text(), 'local edits')

    def test_divergent_checkout_is_preserved(self):
        self.commit(self.repo, 'local commit')
        previous = self.git(self.repo, 'rev-parse', 'HEAD')
        self.commit(self.remote, 'remote commit')
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), previous)

    def test_detached_development_checkout_is_preserved(self):
        self.git(self.repo, 'checkout', '--detach')
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Detached development checkout', result.stderr)

    def test_untracked_scratch_file_does_not_block_update(self):
        (self.repo / 'notes.txt').write_text('scratch')
        self.commit(self.remote, 'new version')
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.repo / 'notes.txt').read_text(), 'scratch')

    def test_managed_checkout_recovers_from_a_half_applied_update(self):
        # The in-app updater builds from $SHARE_DIR/source, which the app owns:
        # a dirty or detached managed checkout must still reach main, otherwise
        # "Update" inside the app silently stops working.
        share = self.root / 'share'
        managed = share / 'source'
        subprocess.run(['git', 'clone', str(self.remote), str(managed)], check=True, capture_output=True)
        (managed / 'file').write_text('half-applied update')
        self.git(managed, 'checkout', '--detach')
        self.commit(self.remote, 'new version')
        result = self.run_setup(source_dir=managed, share_dir=share)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git(managed, 'rev-parse', 'HEAD'), self.git(self.remote, 'rev-parse', 'HEAD'))
        self.assertEqual((managed / 'file').read_text(), 'new version')


if __name__ == '__main__':
    unittest.main()
