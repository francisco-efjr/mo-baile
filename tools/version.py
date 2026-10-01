#!/usr/bin/env python3
"""Versionamento do Mo baile — fonte unica, conferencia e portao de push.

A versao do produto mora em `VERSION` (raiz), no formato SemVer `X.Y.Z`. Os
outros lugares que precisam dela sao copias que este script mantem e confere.

    python3 tools/version.py show            # versao atual
    python3 tools/version.py check           # copias e CHANGELOG batem com VERSION
    python3 tools/version.py bump minor      # sobe (major|minor|patch) e propaga
    python3 tools/version.py tag             # tag anotada vX.Y.Z no HEAD
    python3 tools/version.py pre-push ...    # chamado pelo hook .githooks/pre-push

Regra (ver docs/VERSIONAMENTO.md): todo push de branch leva uma versao maior que
a que o remoto ja tem naquela branch, com secao no CHANGELOG. Sem dependencia
fora da biblioteca padrao: roda no hook, no CI e em qualquer Python 3.
"""

from __future__ import annotations

import datetime
import re
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION_FILE = "VERSION"
CHANGELOG = "CHANGELOG.md"
SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
ZERO_SHA = "0" * 40

# Copias da versao: (arquivo, regex com um grupo que captura a versao).
COPIES: tuple[tuple[str, str], ...] = (
    ("engine/pyproject.toml", r'^version = "([^"]+)"'),
    ("engine/src/mobaile/__init__.py", r'^__version__ = "([^"]+)"'),
    ("apps/tk-legacy/pyproject.toml", r'^version = "([^"]+)"'),
    ("apps/tk-legacy/mobaile_tk/__init__.py", r'^__version__ = "([^"]+)"'),
)

Reader = Callable[[str], "str | None"]


def parse(version: str) -> tuple[int, int, int]:
    match = SEMVER.match(version.strip())
    if not match:
        raise ValueError(f"versao fora do SemVer X.Y.Z: {version!r}")
    return tuple(int(part) for part in match.groups())  # type: ignore[return-value]


def worktree_reader(path: str) -> str | None:
    file = ROOT / path
    return file.read_text(encoding="utf-8") if file.exists() else None


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=check)


def commit_reader(sha: str) -> Reader:
    def read(path: str) -> str | None:
        proc = git("show", f"{sha}:{path}", check=False)
        return proc.stdout if proc.returncode == 0 else None

    return read


def read_version(read: Reader) -> str | None:
    content = read(VERSION_FILE)
    return content.strip() if content is not None else None


def problems(read: Reader) -> list[str]:
    """O que impede esta arvore de ser uma versao valida. Vazio = ok."""
    version = read_version(read)
    if version is None:
        return [f"{VERSION_FILE} nao existe"]
    try:
        parse(version)
    except ValueError as exc:
        return [str(exc)]

    found: list[str] = []
    for path, pattern in COPIES:
        content = read(path)
        if content is None:
            continue
        match = re.search(pattern, content, re.MULTILINE)
        if not match:
            found.append(f"{path}: versao nao encontrada")
        elif match.group(1) != version:
            found.append(f"{path} diz {match.group(1)}, {VERSION_FILE} diz {version}")

    changelog = read(CHANGELOG) or ""
    if not re.search(rf"^## \[{re.escape(version)}\]", changelog, re.MULTILINE):
        found.append(f"{CHANGELOG} sem a secao '## [{version}]'")
    return found


# ------------------------------------------------------------------ comandos


def cmd_check() -> int:
    found = problems(worktree_reader)
    for item in found:
        print(f"versao: {item}", file=sys.stderr)
    if not found:
        print(f"versao {read_version(worktree_reader)} consistente")
    return 1 if found else 0


def cmd_bump(part: str) -> int:
    current = read_version(worktree_reader) or "0.0.0"
    major, minor, patch = parse(current)
    new = {
        "major": f"{major + 1}.0.0",
        "minor": f"{major}.{minor + 1}.0",
        "patch": f"{major}.{minor}.{patch + 1}",
    }[part]

    (ROOT / VERSION_FILE).write_text(new + "\n", encoding="utf-8")
    for path, pattern in COPIES:
        file = ROOT / path
        if not file.exists():
            continue
        text = file.read_text(encoding="utf-8")
        text = re.sub(pattern, lambda m: m.group(0).replace(m.group(1), new), text, count=1, flags=re.MULTILINE)
        file.write_text(text, encoding="utf-8")

    changelog = ROOT / CHANGELOG
    text = changelog.read_text(encoding="utf-8")
    if f"## [{new}]" not in text:
        today = datetime.date.today().isoformat()
        section = f"## [{new}] - {today}\n\n### Adicionado\n\n- \n\n"
        # Logo antes da versao mais recente: o CHANGELOG fica em ordem decrescente.
        first = re.search(r"^## \[", text, re.MULTILINE)
        text = text[: first.start()] + section + text[first.start():] if first else text + "\n" + section
        changelog.write_text(text, encoding="utf-8")

    print(f"{current} -> {new}. Descreva a mudanca em {CHANGELOG} e rode 'make fixtures'.")
    return 0


def cmd_tag() -> int:
    found = problems(worktree_reader)
    if found:
        return cmd_check()
    version = read_version(worktree_reader)
    tag = f"v{version}"
    if git("rev-parse", "-q", "--verify", f"refs/tags/{tag}", check=False).returncode == 0:
        print(f"a tag {tag} ja existe", file=sys.stderr)
        return 1
    git("tag", "-a", tag, "-m", f"Mo baile {version}")
    print(f"tag {tag} criada. Suba com: git push --follow-tags")
    return 0


def cmd_pre_push(lines: list[str]) -> int:
    """Recebe o stdin do hook: '<ref local> <sha local> <ref remota> <sha remoto>'."""
    failures: list[str] = []
    for line in lines:
        parts = line.split()
        if len(parts) != 4:
            continue
        local_ref, local_sha, _remote_ref, remote_sha = parts
        if local_sha == ZERO_SHA:  # apagando ref remota
            continue
        read = commit_reader(local_sha)
        version = read_version(read)

        if local_ref.startswith("refs/tags/"):
            tag = local_ref.removeprefix("refs/tags/")
            target = git("rev-parse", f"{local_sha}^{{commit}}", check=False).stdout.strip()
            tagged = read_version(commit_reader(target)) if target else None
            if tag.startswith("v") and tag != f"v{tagged}":
                failures.append(f"tag {tag} aponta para um commit com VERSION {tagged}")
            continue

        if not local_ref.startswith("refs/heads/"):
            continue
        for item in problems(read):
            failures.append(f"{local_ref}: {item}")
        if version is None:
            continue

        # Versao do que o remoto ja tem nessa branch. Branch nova compara com a
        # maior tag, para duas branches nao reusarem o mesmo numero — menos a
        # tag do proprio commit, que e o fluxo normal (tag e depois push).
        if remote_sha != ZERO_SHA and git("cat-file", "-e", remote_sha, check=False).returncode == 0:
            previous = read_version(commit_reader(remote_sha)) or "0.0.0"
        else:
            previous = latest_tag(exclude_commit=local_sha) or "0.0.0"
        try:
            if parse(version) <= parse(previous):
                failures.append(
                    f"{local_ref}: versao {version} nao e maior que {previous}. "
                    "Rode 'python3 tools/version.py bump patch|minor|major'."
                )
        except ValueError as exc:
            failures.append(f"{local_ref}: {exc}")

    for item in failures:
        print(f"push recusado — {item}", file=sys.stderr)
    if failures:
        print("Regra em docs/VERSIONAMENTO.md.", file=sys.stderr)
    return 1 if failures else 0


def latest_tag(exclude_commit: str | None = None) -> str | None:
    tags = git("tag", "-l", "v*", check=False).stdout.split()
    versions = []
    for tag in tags:
        if exclude_commit and git("rev-parse", f"{tag}^{{commit}}", check=False).stdout.strip() == exclude_commit:
            continue
        try:
            versions.append(parse(tag[1:]))
        except ValueError:
            continue
    return ".".join(map(str, max(versions))) if versions else None


def main(argv: list[str]) -> int:
    if not argv or argv[0] == "show":
        print(read_version(worktree_reader) or "")
        return 0
    command = argv[0]
    if command == "check":
        return cmd_check()
    if command == "bump" and len(argv) == 2 and argv[1] in ("major", "minor", "patch"):
        return cmd_bump(argv[1])
    if command == "tag":
        return cmd_tag()
    if command == "pre-push":
        return cmd_pre_push(sys.stdin.read().splitlines())
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
