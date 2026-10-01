"""tools/version.py: a regra "todo push sobe a versao" (docs/VERSIONAMENTO.md)."""

from __future__ import annotations

import importlib.util
import pathlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

TOOL = pathlib.Path(__file__).resolve().parents[3] / "tools" / "version.py"
spec = importlib.util.spec_from_file_location("version_tool", TOOL)
version_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version_tool)

ZERO = "0" * 40


class TestRepositorioReal(unittest.TestCase):
    def test_versao_do_repositorio_esta_consistente(self):
        self.assertEqual(version_tool.problems(version_tool.worktree_reader), [])


class TestVersaoEmRepoTemporario(unittest.TestCase):
    def setUp(self):
        self.root = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        patcher = patch.object(version_tool, "ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)
        self._git("init", "-q")
        self._git("config", "user.email", "t@t")
        self._git("config", "user.name", "t")
        (self.root / "engine/src/mobaile").mkdir(parents=True)
        self._escrever("1.0.0")
        (self.root / "CHANGELOG.md").write_text("# Changelog\n\n## [1.0.0] - 2026-01-01\n\n- base\n")
        self.v1 = self._commit("v1")

    def _git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, capture_output=True, text=True, check=True).stdout.strip()

    def _escrever(self, versao):
        (self.root / "VERSION").write_text(versao + "\n")
        (self.root / "engine/pyproject.toml").write_text(f'[project]\nversion = "{versao}"\n')
        (self.root / "engine/src/mobaile/__init__.py").write_text(f'__version__ = "{versao}"\n')

    def _commit(self, msg):
        self._git("add", "-A")
        self._git("commit", "-qm", msg)
        return self._git("rev-parse", "HEAD")

    def _push(self, local_sha, remote_sha, ref="refs/heads/main"):
        return version_tool.cmd_pre_push([f"{ref} {local_sha} {ref} {remote_sha}"])

    def test_copia_divergente_e_apontada(self):
        (self.root / "engine/pyproject.toml").write_text('[project]\nversion = "0.9.0"\n')
        found = version_tool.problems(version_tool.worktree_reader)
        self.assertTrue(any("engine/pyproject.toml diz 0.9.0" in item for item in found))

    def test_bump_propaga_e_abre_secao_no_changelog(self):
        version_tool.cmd_bump("minor")
        self.assertEqual(version_tool.read_version(version_tool.worktree_reader), "1.1.0")
        self.assertEqual(version_tool.problems(version_tool.worktree_reader), [])
        changelog = (self.root / "CHANGELOG.md").read_text()
        self.assertLess(changelog.index("## [1.1.0]"), changelog.index("## [1.0.0]"))

    def test_push_sem_subir_versao_e_recusado(self):
        (self.root / "x.txt").write_text("mudanca")
        sem_bump = self._commit("sem bump")
        with patch("sys.stderr"):
            self.assertEqual(self._push(sem_bump, self.v1), 1)

    def test_push_com_versao_nova_passa(self):
        version_tool.cmd_bump("patch")
        com_bump = self._commit("1.0.1")
        self.assertEqual(self._push(com_bump, self.v1), 0)

    def test_branch_nova_compara_com_a_maior_tag(self):
        self._git("tag", "-a", "v1.0.0", "-m", "1.0.0")
        (self.root / "x.txt").write_text("mudanca")
        sem_bump = self._commit("outra branch, mesma versao")
        with patch("sys.stderr"):
            self.assertEqual(self._push(sem_bump, ZERO, "refs/heads/nova"), 1)
        version_tool.cmd_bump("patch")
        self.assertEqual(self._push(self._commit("1.0.1"), ZERO, "refs/heads/nova"), 0)

    def test_branch_nova_com_a_tag_no_proprio_commit_passa(self):
        """Fluxo normal: `version.py tag` e depois `git push --follow-tags`."""
        self._git("tag", "-a", "v1.0.0", "-m", "1.0.0")
        self.assertEqual(self._push(self.v1, ZERO, "refs/heads/nova"), 0)

    def test_tag_precisa_bater_com_a_versao_do_commit(self):
        self._git("tag", "-a", "v9.9.9", "-m", "errada")
        tag_sha = self._git("rev-parse", "v9.9.9")
        with patch("sys.stderr"):
            self.assertEqual(self._push(tag_sha, ZERO, "refs/tags/v9.9.9"), 1)


if __name__ == "__main__":
    unittest.main()
