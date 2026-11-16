"""Projetos de automação do dono: registro e análise estática (B1).

O dono escolhe a pasta do projeto dele (o mesmo que abre no PyCharm) e o Mo
baile mostra o `main` resumido sem executar nada: entrada, config ativa e as
alternativas comentadas, suítes, features e cenários, e o interpretador que a
run configuration do PyCharm usaria.

Regras que valem para o módulo inteiro (docs/melhorias/2026-11-12-execucao-
projeto/CONTRATO.md):

- **Nada é importado nem executado.** O `main` é lido com `ast.parse` no
  processo do motor; os `# init(...)` comentados, com `tokenize`.
- **Nada é gravado na pasta do projeto.** O registro (`projetos.json`) fica no
  diretório de dados do motor, ao lado de `recentes.json`.
- **Leitura só de texto, sem seguir link simbólico**, até 1 MB por arquivo,
  com teto de arquivos lidos. Segredo comum de projeto (`.env*`, `*.pem`,
  keystore, `local.properties`, `google-services.json`) nunca é aberto, e
  `.venv`, `.git`, `node_modules` e afins nunca são lidos por dentro.
- **Valor só das chaves que identificam o alvo** (`platformName`, `udid`,
  `appPackage`...) e o host:porta do hub. Do resto sai só o nome da chave. Os
  valores literais sensíveis e os valores das `envs` da run configuration
  ficam no plano interno (`ProjectPlan`), que serve para montar o ambiente do
  filho e a máscara do console, e nunca vai para RPC, log ou disco.

As travas SEC-5 da pasta de trabalho (`services/workspace.py`) não mudam: um
projeto aberto aqui é só leitura, e só por este módulo.
"""

from __future__ import annotations

import ast
import base64
import errno
import hashlib
import io
import json
import logging
import os
import re
import stat
import subprocess
import tempfile
import threading
import time
import tokenize
import urllib.parse
from collections.abc import Callable, Iterable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from mobaile.domain.errors import InvalidInputError
from mobaile.security import parse_untrusted_xml, validate_input_dir, validate_input_file
from mobaile.security.paths import write_file_atomic
from mobaile.security.redaction import _is_sensitive_key

logger = logging.getLogger(__name__)

PROJECTS_FILE = "projetos.json"
MAX_FILE_BYTES = 1024 * 1024
MAX_FILES_READ = 200
MAX_ROOT_SCAN = 50
MAX_PROJECTS = 50
DYNAMIC = "dinâmico"

# Entradas procuradas na raiz, nesta ordem, antes de varrer os `.py` da raiz.
ENTRY_CANDIDATES = ("main.py", "run.py", "__main__.py")
MAIN_FUNCTION = "main_sem_args"

TEXT_SUFFIXES = frozenset({".py", ".feature", ".ini", ".cfg", ".toml", ".txt"})
# `.xml` só dentro de `.idea` (run configurations do PyCharm).
IDEA_DIR = ".idea"
SKIP_DIRS = frozenset({".venv", "venv", "env", ".git", "node_modules", "__pycache__", ".tox", ".mypy_cache",
                       ".pytest_cache", ".gradle", "build", "dist"})
FORBIDDEN_NAMES = frozenset({"local.properties", "google-services.json", "googleservice-info.plist"})
FORBIDDEN_SUFFIXES = frozenset({".pem", ".p12", ".pfx", ".key", ".keystore", ".jks", ".mobileprovision"})

# Chaves cujo valor literal aparece; o resto só pelo nome. `appium:` e afins
# são prefixos de fornecedor e saem do nome mostrado em `values`.
VALUE_KEYS = ("platformName", "automationName", "udid", "deviceName", "platformVersion", "app", "appPackage",
              "appActivity", "bundleId")
_VALUE_KEYS_LOWER = {k.lower(): k for k in VALUE_KEYS}
# Chaves que costumam guardar a URL do hub. Um valor literal com `://` em
# qualquer chave também conta; aqui é para saber quando o valor dinâmico é hub.
HUB_KEYS = frozenset({"url", "hub", "huburl", "hub_url", "remoteurl", "remote_url", "commandexecutor",
                      "command_executor", "executor", "server", "serverurl", "appiumurl", "appium_url",
                      "appiumserver"})
_LOOPBACK_HOSTS = frozenset({"127.0.0.1", "localhost", "::1"})
# Pedaços de nome de chave que já bastam para tratar o valor como segredo,
# além da lista da redação do proxy (`_is_sensitive_key`).
_SENSITIVE_FRAGMENTS = ("key", "token", "secret", "senha", "segredo", "pass", "pwd", "user", "credential",
                        "auth", "bearer", "session", "cookie", "cpf", "pin")
# Estados do hub (D-O3). `unknown` é falha fechada: a análise não provou que é local.
HUB_LOCAL, HUB_CLOUD, HUB_UNKNOWN = "local", "cloud", "unknown"
# Texto mais curto que isto não é mascarado: trocaria pedaço de palavra comum.
MIN_MASK = 3
# Valor de env da run configuration só vira máscara a partir deste tamanho,
# a menos que o nome da variável seja sensível: "1" e "true" mascarados
# estragariam o console inteiro.
MIN_ENV_MASK = 6

# Configurações globais do PyCharm, onde mora o caminho de cada SDK pelo nome
# (`options/jdk.table.xml`). Só leitura, e só deste arquivo.
PYCHARM_OPTIONS_BASE = Path.home() / "Library" / "Application Support" / "JetBrains"
JDK_TABLE_MAX_BYTES = 4 * 1024 * 1024
# Pythons da máquina oferecidos quando nada foi achado (`interpreter.candidates`).
CANDIDATE_PYTHONS = ("/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3",
                     "~/.pyenv/shims/python3", "~/.asdf/shims/python3")
CANDIDATE_TIMEOUT_S = 4.0
CANDIDATE_CACHE_S = 120.0
_CANDIDATE_CODE = (
    "import importlib.metadata as m, json, sys\n"
    "try:\n"
    "    b = m.version('behave')\n"
    "except m.PackageNotFoundError:\n"
    "    b = None\n"
    "print(json.dumps({'version': sys.version.split()[0], 'behave': b}))\n"
)
_INTERPRETER_MAX_BYTES = 512 * 1024 * 1024

_FEATURE_WORDS = ("Feature:", "Funcionalidade:", "Característica:", "Caracteristica:", "Ability:")
_SCENARIO_WORDS = ("Scenario Outline:", "Scenario Template:", "Esquema do Cenário:", "Esquema do Cenario:",
                   "Delineação do Cenário:", "Scenario:", "Cenário:", "Cenario:", "Example:", "Exemplo:")


class ProjectFileError(Exception):
    """Arquivo do projeto que o Mo baile não lê (proibido, link, grande demais)."""


# ------------------------------------------------------------------ leitura


def _is_forbidden(name: str) -> bool:
    lower = name.lower()
    if lower.startswith(".env"):
        return True
    if lower in FORBIDDEN_NAMES:
        return True
    return any(lower.endswith(sufixo) for sufixo in FORBIDDEN_SUFFIXES)


def read_project_text(root: Path, relative: str | Path) -> str:
    """Lê um arquivo de texto do projeto, ou levanta `ProjectFileError`.

    Recusa `..`, pasta de dependência e arquivo proibido, e abre cada
    componente relativo à pasta anterior com `O_NOFOLLOW` (nenhum link
    simbólico em nível nenhum, sem janela entre conferir e abrir).
    """
    rel = Path(relative)
    if rel.is_absolute() or any(parte in ("..", "") for parte in rel.parts):
        raise ProjectFileError(f"Caminho fora do projeto: {relative}")
    partes = rel.parts
    if not partes:
        raise ProjectFileError("Caminho vazio.")
    for pasta in partes[:-1]:
        if pasta in SKIP_DIRS:
            raise ProjectFileError(f"O Mo baile não lê dentro de {pasta}/.")
    nome = partes[-1]
    if _is_forbidden(nome):
        raise ProjectFileError(f"O Mo baile nunca abre {nome}.")
    sufixo = Path(nome).suffix.lower()
    dentro_do_idea = bool(partes) and partes[0] == IDEA_DIR
    if sufixo not in TEXT_SUFFIXES and not (sufixo == ".xml" and dentro_do_idea):
        raise ProjectFileError(f"Tipo de arquivo que o Mo baile não lê: {nome}")
    # Desce componente por componente com `dir_fd` e `O_NOFOLLOW`: uma pasta
    # trocada por link entre a conferência e a abertura não é atravessada
    # (SEC-B1-06), porque não há conferência separada da abertura.
    try:
        pasta = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
    except OSError as exc:
        raise ProjectFileError(f"Não consegui abrir a pasta do projeto: {exc.strerror or exc}") from exc
    try:
        for parte in partes[:-1]:
            try:
                proxima = os.open(parte, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=pasta)
            except OSError as exc:
                raise _open_error(relative, exc) from exc
            os.close(pasta)
            pasta = proxima
        try:
            fd = os.open(nome, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=pasta)
        except OSError as exc:
            raise _open_error(relative, exc) from exc
    finally:
        os.close(pasta)
    with os.fdopen(fd, "rb") as arquivo:
        info = os.fstat(arquivo.fileno())
        if not stat.S_ISREG(info.st_mode):
            raise ProjectFileError(f"{relative} não é um arquivo comum.")
        if info.st_size > MAX_FILE_BYTES:
            raise ProjectFileError(f"{relative} passa de 1 MB; o Mo baile não lê arquivos desse tamanho.")
        dados = arquivo.read(MAX_FILE_BYTES + 1)
    if len(dados) > MAX_FILE_BYTES:
        raise ProjectFileError(f"{relative} passa de 1 MB; o Mo baile não lê arquivos desse tamanho.")
    return dados.decode("utf-8", errors="replace")


def _open_error(relative: str | Path, exc: OSError) -> ProjectFileError:
    if exc.errno in (errno.ELOOP, errno.ENOTDIR):
        return ProjectFileError(f"{relative} passa por um link simbólico; o Mo baile não segue links.")
    if exc.errno == errno.ENOENT:
        return ProjectFileError(f"Arquivo não encontrado: {relative}")
    return ProjectFileError(f"Não consegui abrir {relative}: {exc.strerror or exc}")


def _exists_plain(root: Path, relative: str) -> bool:
    """O caminho existe dentro do projeto sem passar por link simbólico?"""
    atual = root
    for parte in Path(relative).parts:
        if parte in ("..", ""):
            return False
        atual = atual / parte
        try:
            if stat.S_ISLNK(os.lstat(atual).st_mode):
                return False
        except OSError:
            return False
    return True


def parse_feature_text(texto: str) -> tuple[str | None, list[str]]:
    """Título da feature e nomes dos cenários, lendo o `.feature` como texto."""
    titulo: str | None = None
    cenarios: list[str] = []
    for linha in texto.splitlines():
        limpa = linha.strip()
        if not limpa or limpa.startswith("#"):
            continue
        if titulo is None:
            palavra = next((p for p in _FEATURE_WORDS if limpa.startswith(p)), None)
            if palavra is not None:
                titulo = limpa[len(palavra):].strip()
                continue
        for palavra in _SCENARIO_WORDS:
            if limpa.startswith(palavra):
                cenarios.append(limpa[len(palavra):].strip())
                break
    return titulo, cenarios


# ------------------------------------------------------------------ registro


def _safe_xml(texto: str):
    """XML de arquivo alheio: DOCTYPE, entidade ou XML torto viram `None`, nunca exceção."""
    try:
        return parse_untrusted_xml(texto)
    except InvalidInputError:
        return None


def _str_or_none(valor: object) -> str | None:
    return valor if isinstance(valor, str) and valor else None


def project_id(root: Path) -> str:
    """sha1 curto do caminho real: o mesmo projeto aberto de novo tem o mesmo id."""
    return hashlib.sha1(str(root).encode("utf-8"), usedforsecurity=False).hexdigest()[:12]


class ProjectStore:
    """Lista de projetos autorizados num arquivo local, gravado de forma atômica."""

    def __init__(self, path: Path | Callable[[], Path], clock: Callable[[], float] = time.time) -> None:
        self._path = path
        self._clock = clock
        self._lock = threading.Lock()

    @property
    def path(self) -> Path:
        return self._path() if callable(self._path) else self._path

    def _read(self) -> list[dict[str, Any]]:
        try:
            dados = json.loads(self.path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return []
        except (OSError, ValueError) as exc:
            logger.warning("projetos.json ilegível; recomeçando a lista: %s", exc)
            return []
        itens = dados.get("projects") if isinstance(dados, dict) else None
        if not isinstance(itens, list):
            return []
        validos = []
        for item in itens:
            if isinstance(item, dict) and isinstance(item.get("id"), str) and isinstance(item.get("root"), str):
                validos.append({
                    "id": item["id"], "root": item["root"], "name": str(item.get("name") or Path(item["root"]).name),
                    "entry": item.get("entry") if isinstance(item.get("entry"), str) else None,
                    "trusted": item.get("trusted") is True,
                    "opened_at": float(item.get("opened_at") or 0.0),
                    "interpreter_override": _str_or_none(item.get("interpreter_override")),
                    "entry_override": _str_or_none(item.get("entry_override")),
                    "trusted_with": item.get("trusted_with") if isinstance(item.get("trusted_with"), dict) else None,
                })
        return validos

    def _write(self, itens: list[dict[str, Any]]) -> None:
        destino = self.path
        destino.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        texto = json.dumps({"version": 1, "projects": itens}, ensure_ascii=False, indent=2) + "\n"
        write_file_atomic(destino, texto.encode("utf-8"))

    def list(self) -> list[dict[str, Any]]:
        with self._lock:
            return sorted(self._read(), key=lambda p: p["opened_at"], reverse=True)

    def get(self, pid: str) -> dict[str, Any] | None:
        with self._lock:
            return next((p for p in self._read() if p["id"] == pid), None)

    def upsert(self, root: Path, entry: str | None) -> dict[str, Any]:
        with self._lock:
            itens = self._read()
            pid = project_id(root)
            anterior = next((p for p in itens if p["id"] == pid), None)
            item = {
                "id": pid, "root": str(root), "name": root.name or str(root),
                "entry": entry if entry is not None else (anterior or {}).get("entry"),
                "trusted": bool(anterior and anterior["trusted"]),
                "opened_at": float(self._clock()),
                "interpreter_override": (anterior or {}).get("interpreter_override"),
                "entry_override": (anterior or {}).get("entry_override"),
                "trusted_with": (anterior or {}).get("trusted_with"),
            }
            itens = [item, *[p for p in itens if p["id"] != pid]][:MAX_PROJECTS]
            self._write(itens)
            return dict(item)

    def update(self, pid: str, **campos: Any) -> dict[str, Any] | None:
        with self._lock:
            itens = self._read()
            for item in itens:
                if item["id"] == pid:
                    item.update(campos)
                    self._write(itens)
                    return dict(item)
            return None

    def remove(self, pid: str) -> bool:
        with self._lock:
            itens = self._read()
            restantes = [p for p in itens if p["id"] != pid]
            if len(restantes) == len(itens):
                return False
            self._write(restantes)
            return True


# ------------------------------------------------------------------ análise


@dataclass
class ConfigInfo:
    name: str
    active: bool
    found: bool = False
    file: str | None = None
    line: int | None = None
    values: dict[str, str] = field(default_factory=dict)
    hub: str | None = None
    hub_host: str | None = None
    keys: list[str] = field(default_factory=list)
    secrets: set[str] = field(default_factory=set)
    # Hosts de todas as URLs literais da config, em qualquer chave (D-O3).
    url_hosts: list[str] = field(default_factory=list)
    # Hub não provado: valor montado em tempo de execução numa chave de hub.
    hub_dynamic: bool = False
    # Pares usuário/segredo para a máscara do Basic em base64.
    users: set[str] = field(default_factory=set)
    # `init(...)` dentro de if/try/laço, ou por uma variável local: a análise
    # não sabe qual config roda (D-O3).
    conditional: bool = False
    indirect: bool = False

    @property
    def platform(self) -> str | None:
        valor = (self.values.get("platformName") or "").lower()
        if valor in ("android", "ios"):
            return valor
        automacao = (self.values.get("automationName") or "").lower()
        if automacao in ("uiautomator2", "espresso"):
            return "android"
        if automacao == "xcuitest":
            return "ios"
        return None

    @property
    def hub_state(self) -> str:
        """`cloud` com qualquer URL literal fora do loopback, em qualquer chave, ou `kobiton` no
        nome ou num host; `unknown` com config não encontrada ou hub montado em tempo de
        execução; `local` no resto (sem URL nenhuma, vale o Appium local padrão)."""
        hosts = [h.lower() for h in self.url_hosts]
        if "kobiton" in self.name.lower() or any("kobiton" in h for h in hosts):
            return HUB_CLOUD
        if any(h not in _LOOPBACK_HOSTS for h in hosts):
            return HUB_CLOUD
        if not self.found or self.hub_dynamic:
            return HUB_UNKNOWN
        return HUB_LOCAL

    @property
    def cloud(self) -> bool:
        return self.hub_state == HUB_CLOUD

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name, "active": self.active, "found": self.found, "file": self.file, "line": self.line,
            "platform": self.platform, "values": dict(self.values), "hub": self.hub, "cloud": self.cloud,
            "hub_state": self.hub_state, "keys": list(self.keys),
        }


@dataclass
class ProjectPlan:
    """Tudo que a análise achou, inclusive o que nunca sai do motor.

    `env` (valores das `envs` da run configuration) e `masks` (valores
    literais sensíveis) servem para o filho e para mascarar o console; o
    `to_dict` não os inclui.
    """

    project: dict[str, Any]
    root: Path
    entry_file: str | None
    entry_function: str | None
    interpreter: str | None
    interpreter_source: str | None
    working_dir: Path
    run_configuration: dict[str, Any] | None
    configs: list[ConfigInfo]
    suites: list[dict[str, Any]]
    unused_suites: list[str]
    problems: list[dict[str, Any]]
    env: dict[str, str] = field(default_factory=dict)
    masks: list[str] = field(default_factory=list)
    # Pythons da máquina, só quando nenhum interpretador foi achado. Preenchido
    # por `ProjectService.inspect`, nunca pelo `analyze` do `run.start`.
    candidates: list[dict[str, Any]] = field(default_factory=list)

    @property
    def active_config(self) -> ConfigInfo | None:
        return next((c for c in self.configs if c.active), None)

    @property
    def active_configs(self) -> list[ConfigInfo]:
        return [c for c in self.configs if c.active]

    def hub(self) -> tuple[str, str | None]:
        """Estado do hub da execução inteira e o motivo quando não é `local` (D-O3).

        Qualquer `init` ativo possível na nuvem: `cloud`. Senão, qualquer dúvida
        (config não achada, hub dinâmico, mais de um `init`, `init` condicional
        ou por variável, nenhum `init`): `unknown`.
        """
        ativas = self.active_configs
        if not ativas:
            return HUB_UNKNOWN, "Não achei um init(config_...) ativo no main."
        nuvem = [c for c in ativas if c.hub_state == HUB_CLOUD]
        if nuvem:
            c = nuvem[0]
            onde = f" ({c.hub})" if c.hub and c.hub != DYNAMIC else ""
            return HUB_CLOUD, f"A config {c.name} roda na nuvem{onde}."
        duvidas = [c for c in ativas if c.hub_state == HUB_UNKNOWN]
        if duvidas:
            c = duvidas[0]
            motivo = (f"o hub de {c.name} é montado em tempo de execução" if c.found
                      else f"não achei a definição de {c.name}")
            return HUB_UNKNOWN, f"Não dá para provar que roda local: {motivo}."
        if len(ativas) > 1:
            return HUB_UNKNOWN, "O main tem mais de um init(...) ativo; não dá para saber qual roda."
        if any(c.conditional or c.indirect for c in ativas):
            return HUB_UNKNOWN, "O init(...) do main está dentro de if/try ou recebe uma variável."
        return HUB_LOCAL, None

    @property
    def hub_state(self) -> str:
        return self.hub()[0]

    def trust_components(self) -> dict[str, Any]:
        """O que o diálogo "Confiar neste projeto?" mostrou (D-O2)."""
        return {
            "root": str(Path(self.root).resolve()), "interpreter": self.interpreter, "entry": self.entry_file,
            "working_dir": str(self.working_dir), "env_names": sorted(self.env),
        }

    def to_dict(self) -> dict[str, Any]:
        ativa = self.active_config
        estado, motivo = self.hub()
        return {
            "project": public_project(self.project),
            "entry": {"file": self.entry_file, "function": self.entry_function, "found": self.entry_file is not None},
            "interpreter": {
                "path": self.interpreter, "source": self.interpreter_source,
                "exists": bool(self.interpreter and os.path.isfile(self.interpreter)
                               and os.access(self.interpreter, os.X_OK)),
                "candidates": [dict(c) for c in self.candidates],
            },
            "working_dir": str(self.working_dir),
            "run_configuration": dict(self.run_configuration) if self.run_configuration else None,
            "active_config": ativa.name if ativa else None,
            "hub_state": estado,
            "hub_reason": motivo,
            "configs": [c.to_dict() for c in self.configs],
            "suites": self.suites,
            "unused_suites": list(self.unused_suites),
            "problems": list(self.problems),
        }


def public_project(item: dict[str, Any]) -> dict[str, Any]:
    """O item do registro como o front o vê: sem a impressão da confiança."""
    return {k: v for k, v in item.items() if k != "trusted_with"}


def _sensitive(key: str) -> bool:
    base = key.rsplit(":", 1)[-1]
    if _is_sensitive_key(base) or _is_sensitive_key(key):
        return True
    lower = base.lower()
    return any(fragmento in lower for fragmento in _SENSITIVE_FRAGMENTS)


def _host_port(url: str) -> tuple[str | None, str | None, str | None, str | None]:
    """(`host:porta`, host, usuário, senha da URL). O que sai para o RPC nunca tem userinfo nem caminho."""
    try:
        partes = urllib.parse.urlsplit(url)
        host = partes.hostname
        porta = partes.port
    except ValueError:
        return None, None, None, None
    usuario = urllib.parse.unquote(partes.username) if partes.username else None
    senha = urllib.parse.unquote(partes.password) if partes.password else None
    if not host:
        return None, None, usuario, senha
    if porta is None:
        porta = 443 if partes.scheme == "https" else 80
    mostrado = f"[{host}]" if ":" in host else host
    return f"{mostrado}:{porta}", host, usuario, senha


def secret_forms(segredo: str) -> set[str]:
    """O segredo e as formas em que ele costuma aparecer num log: URL-encoded e com a
    barra invertida dobrada de um `repr`."""
    formas = {segredo, urllib.parse.quote(segredo, safe=""), urllib.parse.quote_plus(segredo),
              segredo.replace("\\", "\\\\")}
    return {f for f in formas if len(f) >= MIN_MASK}


def basic_auth_forms(usuario: str, segredo: str) -> set[str]:
    """O `Authorization: Basic` de um par usuário/segredo, com e sem padding."""
    valor = base64.b64encode(f"{usuario}:{segredo}".encode()).decode("ascii")
    return {valor, valor.rstrip("=")}


class _Analyzer:
    """Uma análise: conta os arquivos lidos e junta os problemas."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.read_count = 0
        self.problems: list[dict[str, Any]] = []
        self._cache: dict[str, str | None] = {}
        self._trees: dict[str, ast.Module | None] = {}

    def problem(self, message: str, file: str | None = None, line: int | None = None) -> None:
        item = {"file": file, "line": line, "message": message}
        if item not in self.problems:
            self.problems.append(item)

    def read(self, relative: str, *, quiet_missing: bool = False) -> str | None:
        if relative in self._cache:
            return self._cache[relative]
        if self.read_count >= MAX_FILES_READ:
            self.problem(f"Parei de ler o projeto depois de {MAX_FILES_READ} arquivos.")
            self._cache[relative] = None
            return None
        self.read_count += 1
        try:
            texto = read_project_text(self.root, relative)
        except ProjectFileError as exc:
            if not (quiet_missing and "não encontrado" in str(exc)):
                self.problem(str(exc), relative)
            texto = None
        self._cache[relative] = texto
        return texto

    def tree(self, relative: str) -> ast.Module | None:
        if relative in self._trees:
            return self._trees[relative]
        texto = self.read(relative)
        arvore = None
        if texto is not None:
            try:
                arvore = ast.parse(texto, filename=relative)
            except SyntaxError as exc:
                self.problem(f"Erro de sintaxe: {exc.msg}", relative, exc.lineno)
            except (RecursionError, MemoryError, ValueError):
                self.problem("Arquivo complexo demais para ler sem executar.", relative)
        self._trees[relative] = arvore
        return arvore


# ---- entrada e main


def _defines_main(texto: str) -> bool:
    try:
        arvore = ast.parse(texto)
    except (SyntaxError, RecursionError, MemoryError, ValueError):
        return False
    for no in arvore.body:
        if isinstance(no, ast.FunctionDef) and no.name == MAIN_FUNCTION:
            return True
        if _is_main_guard(no):
            return True
    return False


def _is_main_guard(no: ast.stmt) -> bool:
    if not isinstance(no, ast.If) or not isinstance(no.test, ast.Compare):
        return False
    teste = no.test
    lados = [teste.left, *teste.comparators]
    nomes = {n.id for n in lados if isinstance(n, ast.Name)}
    textos = {n.value for n in lados if isinstance(n, ast.Constant)}
    return "__name__" in nomes and "__main__" in textos


def detect_entry(root: Path) -> str | None:
    """Arquivo de entrada: `main.py`, `run.py` ou `__main__.py`, ou o `.py` da raiz com o main."""
    for nome in ENTRY_CANDIDATES:
        caminho = root / nome
        if _exists_plain(root, nome) and caminho.is_file():
            return nome
    try:
        candidatos = sorted(p.name for p in root.iterdir() if p.suffix == ".py" and not p.is_symlink())
    except OSError:
        return None
    for nome in candidatos[:MAX_ROOT_SCAN]:
        try:
            texto = read_project_text(root, nome)
        except ProjectFileError:
            continue
        if _defines_main(texto):
            return nome
    return None


def _call_name(no: ast.AST) -> str | None:
    if isinstance(no, ast.Call):
        if isinstance(no.func, ast.Name):
            return no.func.id
        if isinstance(no.func, ast.Attribute):
            return no.func.attr
    return None


def _calls_in_order(nos: Iterable[ast.stmt]) -> list[ast.Call]:
    """Chamadas em ordem de código, descendo em try/with/if/for, sem entrar em def."""
    resultado: list[ast.Call] = []
    # Pilha explícita, e não recursão: uma expressão longa e legítima (milhares
    # de termos) estourava a pilha do Python e derrubava a análise (CR-09).
    pilha: list[ast.AST] = list(reversed(list(nos)))
    while pilha:
        no = pilha.pop()
        if isinstance(no, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)):
            continue
        if isinstance(no, ast.Call):
            resultado.append(no)
        pilha.extend(reversed(list(ast.iter_child_nodes(no))))
    return resultado


_CONDITIONAL_NODES = (ast.If, ast.Try, ast.For, ast.AsyncFor, ast.While, ast.IfExp, ast.BoolOp, ast.Match)
if hasattr(ast, "TryStar"):
    _CONDITIONAL_NODES = (*_CONDITIONAL_NODES, ast.TryStar)


def _init_calls(corpo: ast.FunctionDef) -> list[tuple[ast.Call, bool]]:
    """Cada `init(...)` do main, em ordem, com "está dentro de if/try/laço?"."""
    achados: list[tuple[ast.Call, bool]] = []
    pilha: list[tuple[ast.AST, bool]] = [(n, False) for n in reversed(corpo.body)]
    while pilha:
        no, condicional = pilha.pop()
        if isinstance(no, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)):
            continue
        if isinstance(no, ast.Call) and _call_name(no) == "init" and isinstance(no.func, ast.Name):
            achados.append((no, condicional))
        filhos_condicionais = condicional or isinstance(no, _CONDITIONAL_NODES)
        pilha.extend((f, filhos_condicionais) for f in reversed(list(ast.iter_child_nodes(no))))
    return achados


def _local_aliases(corpo: ast.FunctionDef) -> dict[str, str]:
    """`cfg = config_x` dentro do main: `{"cfg": "config_x"}`."""
    apelidos: dict[str, str] = {}
    for no in ast.walk(corpo):
        if isinstance(no, ast.Assign) and isinstance(no.value, ast.Name):
            for alvo in no.targets:
                if isinstance(alvo, ast.Name):
                    apelidos[alvo.id] = no.value.id
    return apelidos


def _main_function(arvore: ast.Module) -> str | None:
    funcoes = {n.name for n in arvore.body if isinstance(n, ast.FunctionDef)}
    for no in arvore.body:
        if _is_main_guard(no):
            for chamada in _calls_in_order(no.body):
                nome = _call_name(chamada)
                if nome in funcoes:
                    return nome
    return MAIN_FUNCTION if MAIN_FUNCTION in funcoes else None


def _commented_inits(texto: str, inicio: int, fim: int) -> list[tuple[str, int]]:
    """`# init(config_x)` comentados entre as linhas `inicio` e `fim`."""
    achados: list[tuple[str, int]] = []
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(texto).readline))
    except (tokenize.TokenError, SyntaxError, IndentationError):
        return achados
    for token in tokens:
        if token.type != tokenize.COMMENT or not (inicio <= token.start[0] <= fim):
            continue
        corpo = token.string.lstrip("#").strip()
        try:
            expressao = ast.parse(corpo, mode="eval").body
        except (SyntaxError, ValueError, RecursionError):
            continue
        if _call_name(expressao) == "init" and expressao.args and isinstance(expressao.args[0], ast.Name):
            achados.append((expressao.args[0].id, token.start[0]))
    return achados


# ---- configs


def _module_files(modulo: str, nivel: int, entry_dir: str) -> list[str]:
    partes = [p for p in modulo.split(".") if p] if modulo else []
    base = Path(entry_dir) if nivel else Path()
    for _ in range(max(0, nivel - 1)):
        base = base.parent
    caminho = base.joinpath(*partes) if partes else base
    candidatos = [f"{caminho}.py", str(caminho / "__init__.py")] if partes else [str(caminho / "__init__.py")]
    if not nivel and entry_dir not in ("", "."):
        alternativa = Path(entry_dir).joinpath(*partes)
        candidatos += [f"{alternativa}.py", str(alternativa / "__init__.py")]
    return [c.removeprefix("./") for c in candidatos]


def _config_sources(arvore: ast.Module, entry_file: str) -> dict[str, list[str]]:
    """Nome da config -> arquivos onde procurá-la, a partir dos imports da entrada."""
    entry_dir = str(Path(entry_file).parent)
    fontes: dict[str, list[str]] = {}
    estrela: list[str] = []
    for no in arvore.body:
        if isinstance(no, ast.ImportFrom):
            arquivos = _module_files(no.module or "", no.level, entry_dir)
            for alias in no.names:
                if alias.name == "*":
                    estrela += arquivos
                else:
                    fontes.setdefault(alias.asname or alias.name, []).extend(arquivos)
        elif isinstance(no, ast.Import):
            for alias in no.names:
                fontes.setdefault("*" + (alias.asname or alias.name), []).extend(
                    _module_files(alias.name, 0, entry_dir))
    fontes["**"] = estrela
    return fontes


def _literal(no: ast.AST) -> str | None:
    if isinstance(no, ast.Constant) and isinstance(no.value, (str, int, float, bool)):
        return str(no.value)
    return None


def _dict_items(no: ast.AST, ambiente: dict[str, ast.AST], profundidade: int = 0) -> list[tuple[str, ast.AST]]:
    """Pares (chave, valor) de um `{...}` ou `dict(...)`, abrindo `**base` conhecido."""
    if profundidade > 4:
        return []
    itens: list[tuple[str, ast.AST]] = []
    if isinstance(no, ast.Dict):
        for chave, valor in zip(no.keys, no.values, strict=False):
            if chave is None:
                if isinstance(valor, ast.Name) and valor.id in ambiente:
                    itens += _dict_items(ambiente[valor.id], ambiente, profundidade + 1)
                continue
            if isinstance(chave, ast.Constant) and isinstance(chave.value, str):
                itens.append((chave.value, valor))
    elif isinstance(no, ast.Call) and _call_name(no) == "dict":
        for argumento in no.args:
            if isinstance(argumento, ast.Name) and argumento.id in ambiente:
                itens += _dict_items(ambiente[argumento.id], ambiente, profundidade + 1)
            elif isinstance(argumento, (ast.Dict, ast.Call)):
                itens += _dict_items(argumento, ambiente, profundidade + 1)
        for palavra in no.keywords:
            if palavra.arg is None:
                if isinstance(palavra.value, ast.Name) and palavra.value.id in ambiente:
                    itens += _dict_items(ambiente[palavra.value.id], ambiente, profundidade + 1)
            else:
                itens.append((palavra.arg, palavra.value))
    return itens


def _module_assignments(arvore: ast.Module) -> dict[str, ast.stmt]:
    atribuicoes: dict[str, ast.stmt] = {}
    for no in arvore.body:
        if isinstance(no, ast.Assign):
            for alvo in no.targets:
                if isinstance(alvo, ast.Name):
                    atribuicoes[alvo.id] = no
        elif isinstance(no, ast.AnnAssign) and isinstance(no.target, ast.Name) and no.value is not None:
            atribuicoes[no.target.id] = no
    return atribuicoes


def _fill_config(info: ConfigInfo, valor: ast.AST, constantes: dict[str, ast.AST], prefixo: str = "") -> None:
    for chave, no in _dict_items(valor, constantes):
        nome = f"{prefixo}{chave}"
        if isinstance(no, (ast.Dict,)) or (isinstance(no, ast.Call) and _call_name(no) == "dict"):
            info.keys.append(nome)
            _fill_config(info, no, constantes, prefixo=f"{nome}.")
            continue
        if isinstance(no, ast.Name) and no.id in constantes:
            no = constantes[no.id]
        literal = _literal(no)
        base = chave.rsplit(":", 1)[-1]
        e_chave_de_hub = base.lower() in HUB_KEYS
        info.keys.append(nome)
        if literal is not None and "://" in literal:
            hub, host, usuario, senha = _host_port(literal)
            if host:
                info.url_hosts.append(host)
            for parte in (usuario, senha):
                if parte:
                    info.secrets |= secret_forms(parte)
            if usuario and senha:
                info.secrets |= basic_auth_forms(usuario, senha)
            # A URL de uma chave de hub manda; URL de outra chave (proxy do
            # chromedriver, por exemplo) só vira hub se não houver outra (CR-08).
            if e_chave_de_hub or info.hub is None:
                info.hub, info.hub_host = hub, host
            continue
        if literal is None and e_chave_de_hub:
            info.hub_dynamic = True
            if info.hub is None:
                info.hub = DYNAMIC
            continue
        canonico = _VALUE_KEYS_LOWER.get(base.lower())
        if canonico and not prefixo:
            info.values[canonico] = literal if literal is not None else DYNAMIC
        elif _sensitive(chave) and literal is not None and len(literal) >= MIN_MASK:
            info.secrets |= secret_forms(literal)
            if "user" in base.lower():
                info.users.add(literal)
    # Basic dos pares usuário/segredo da própria config (kobiton:username + accessKey).
    for usuario in list(info.users):
        for segredo in list(info.secrets):
            if segredo != usuario and len(info.secrets) < 200:
                info.secrets |= basic_auth_forms(usuario, segredo)


# ---- interpretador


def _expand(valor: str, root: Path) -> str:
    return (valor.replace("$PROJECT_DIR$", str(root))
            .replace("$USER_HOME$", str(Path.home())))


def _python_configs(raiz_xml, arquivo: str) -> list[dict[str, Any]]:
    resultado = []
    for conf in raiz_xml.iter("configuration"):
        if conf.get("type") != "PythonConfigurationType" or conf.get("default") == "true":
            continue
        opcoes = {o.get("name"): o.get("value") or "" for o in conf.findall("option")}
        envs: dict[str, str] = {}
        for env in conf.iter("env"):
            nome = env.get("name")
            if nome:
                envs[nome] = env.get("value") or ""
        resultado.append({"name": conf.get("name") or "", "file": arquivo, "options": opcoes, "envs": envs})
    return resultado


def _read_run_configurations(analise: _Analyzer, root: Path) -> list[dict[str, Any]]:
    encontradas: list[dict[str, Any]] = []
    pasta = root / IDEA_DIR / "runConfigurations"
    if _exists_plain(root, f"{IDEA_DIR}/runConfigurations") and pasta.is_dir():
        try:
            arquivos = sorted(p.name for p in pasta.iterdir() if p.suffix == ".xml")[:MAX_ROOT_SCAN]
        except OSError:
            arquivos = []
        for nome in arquivos:
            rel = f"{IDEA_DIR}/runConfigurations/{nome}"
            texto = analise.read(rel)
            raiz_xml = _safe_xml(texto) if texto else None
            if raiz_xml is not None:
                encontradas += _python_configs(raiz_xml, rel)
    rel = f"{IDEA_DIR}/workspace.xml"
    if _exists_plain(root, rel) and (root / rel).is_file():
        texto = analise.read(rel)
        raiz_xml = _safe_xml(texto) if texto else None
        if raiz_xml is not None:
            for componente in raiz_xml.iter("component"):
                if componente.get("name") == "RunManager":
                    encontradas += _python_configs(componente, rel)
    return encontradas


def _pick_run_configuration(configs: list[dict[str, Any]], root: Path, entry: str | None) -> dict[str, Any] | None:
    if not configs:
        return None
    if entry:
        alvo = str(root / entry)
        for conf in configs:
            script = _expand(conf["options"].get("SCRIPT_NAME", ""), root)
            if script in (alvo, entry):
                return conf
    return configs[0]


def _venv_python(root: Path) -> str | None:
    for nome in (".venv", "venv"):
        if _exists_plain(root, f"{nome}/pyvenv.cfg") and (root / nome / "pyvenv.cfg").is_file():
            for binario in ("python", "python3"):
                caminho = root / nome / "bin" / binario
                if caminho.exists():
                    return str(caminho)
    return None


def _misc_sdk_name(analise: _Analyzer, root: Path) -> str | None:
    """`project-jdk-name` de `.idea/misc.xml`: o NOME do SDK, sem caminho."""
    rel = f"{IDEA_DIR}/misc.xml"
    if not (_exists_plain(root, rel) and (root / rel).is_file()):
        return None
    texto = analise.read(rel)
    raiz_xml = _safe_xml(texto) if texto else None
    if raiz_xml is None:
        return None
    for componente in raiz_xml.iter("component"):
        nome = componente.get("project-jdk-name")
        if componente.get("name") == "ProjectRootManager" and nome:
            return nome
    return None


def _version_key(pasta: Path) -> tuple:
    numeros = re.findall(r"\d+", pasta.parent.name)
    return tuple(int(n) for n in numeros)


def pycharm_sdk_home(nome: str, base: Path) -> str | None:
    """Caminho do SDK `nome` no `jdk.table.xml` do PyCharm mais recente que o tiver.

    Lê `<base>/PyCharm*/options/jdk.table.xml` (Professional e Community), da
    versão mais nova para a mais velha, com o parser de XML seguro do motor.
    """
    try:
        tabelas = [p for p in base.glob("PyCharm*/options/jdk.table.xml") if p.is_file()]
    except OSError:
        return None
    for tabela in sorted(tabelas, key=lambda t: _version_key(t.parent), reverse=True):
        try:
            if tabela.stat().st_size > JDK_TABLE_MAX_BYTES:
                continue
            texto = tabela.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        raiz_xml = _safe_xml(texto)
        if raiz_xml is None:
            continue
        for jdk in raiz_xml.iter("jdk"):
            nome_no = jdk.find("name")
            casa = jdk.find("homePath")
            if nome_no is None or casa is None or nome_no.get("value") != nome:
                continue
            caminho = (casa.get("value") or "").replace("$USER_HOME$", str(Path.home())).strip()
            if caminho:
                return caminho
    return None


_candidate_cache: dict[str, Any] = {"at": 0.0, "items": None}
_candidate_lock = threading.Lock()


def _probe_python(caminho: str) -> dict[str, Any] | None:
    """Versão e behave de um Python da máquina: `-E -c` numa pasta vazia, prazo curto."""
    try:
        with tempfile.TemporaryDirectory(prefix="mobaile-python-") as vazia:
            proc = subprocess.run(
                [caminho, "-E", "-c", _CANDIDATE_CODE], capture_output=True, text=True, cwd=vazia,
                stdin=subprocess.DEVNULL, timeout=CANDIDATE_TIMEOUT_S, check=False,
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    try:
        dados = json.loads(proc.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return None
    return {"path": caminho, "version": str(dados.get("version") or "") or None,
            "behave": _str_or_none(dados.get("behave"))}


def find_candidate_pythons(paths: Iterable[str] = CANDIDATE_PYTHONS) -> list[dict[str, Any]]:
    """Pythons que existem nesta máquina, com versão e behave. Cache curto; nunca roda o projeto."""
    with _candidate_lock:
        if _candidate_cache["items"] is not None and time.monotonic() - _candidate_cache["at"] < CANDIDATE_CACHE_S:
            return [dict(c) for c in _candidate_cache["items"]]
    existentes: list[str] = []
    vistos: set[str] = set()
    for bruto in paths:
        caminho = os.path.expanduser(bruto)
        if not (os.path.isfile(caminho) and os.access(caminho, os.X_OK)):
            continue
        real = os.path.realpath(caminho)
        if real in vistos:
            continue
        vistos.add(real)
        existentes.append(caminho)
    if existentes:
        with ThreadPoolExecutor(max_workers=len(existentes)) as pool:
            achados = [c for c in pool.map(_probe_python, existentes) if c]
    else:
        achados = []
    with _candidate_lock:
        _candidate_cache.update(at=time.monotonic(), items=achados)
    return [dict(c) for c in achados]


def validate_interpreter_path(raw: object) -> str:
    """Caminho absoluto de um executável que existe. Guarda o caminho como veio, sem resolver
    o link: `.venv/bin/python` resolvido viraria o Python do sistema e perderia o venv."""
    if not isinstance(raw, str):
        raise InvalidInputError("interpreter precisa ser texto ou null.")
    caminho = os.path.expanduser(raw.strip())
    if not os.path.isabs(caminho):
        raise InvalidInputError(f"O interpretador precisa de caminho absoluto: {raw}")
    if ".." in Path(caminho).parts:
        raise InvalidInputError(f"Caminho de interpretador com '..' não é aceito: {raw}")
    validate_input_file(caminho, label="interpretador", max_bytes=_INTERPRETER_MAX_BYTES)
    if not os.access(caminho, os.X_OK):
        raise InvalidInputError(f"O interpretador não é executável: {caminho}")
    return os.path.normpath(caminho)


def validate_entry_path(root: Path, raw: object) -> str:
    """`.py` relativo dentro da raiz, sem link simbólico, que o Mo baile consegue ler."""
    if not isinstance(raw, str) or not raw.strip():
        raise InvalidInputError("entry precisa ser texto ou null.")
    rel = raw.strip()
    if not rel.endswith(".py"):
        raise InvalidInputError(f"A entrada precisa ser um arquivo .py: {rel}")
    try:
        read_project_text(root, rel)
    except ProjectFileError as exc:
        raise InvalidInputError(f"Entrada inválida: {exc}") from exc
    return Path(rel).as_posix()


# ------------------------------------------------------------------ serviço


class ProjectService:
    """Casos de uso de `project.*`: abrir, listar, esquecer, inspecionar."""

    def __init__(self, store: ProjectStore, *, pycharm_options: Path | None = None,
                 candidates: Callable[[], list[dict[str, Any]]] = find_candidate_pythons) -> None:
        self.store = store
        self.pycharm_options = pycharm_options or PYCHARM_OPTIONS_BASE
        self._candidates = candidates

    # registro

    def open(self, raw_path: object) -> dict[str, Any]:
        raiz = validate_input_dir(raw_path, label="projeto")
        return public_project(self.store.upsert(raiz, detect_entry(raiz)))

    def list(self) -> list[dict[str, Any]]:
        return [public_project(p) for p in self.store.list()]

    def get(self, pid: object) -> dict[str, Any]:
        if not isinstance(pid, str) or not pid:
            raise InvalidInputError("Informe project_id.")
        projeto = self.store.get(pid)
        if projeto is None:
            raise InvalidInputError(f"Projeto desconhecido: {pid}. Abra a pasta de novo.")
        return projeto

    def forget(self, pid: object) -> bool:
        if not isinstance(pid, str) or not pid:
            raise InvalidInputError("Informe project_id.")
        return self.store.remove(pid)

    def trust(self, pid: object, plan: ProjectPlan | None = None) -> dict[str, Any]:
        """Marca o projeto como confiável com a impressão do que roda agora (D-O2)."""
        plano = plan or self.analyze(pid)
        pid = plano.project["id"]
        item = self.store.update(pid, trusted=True, trusted_with=plano.trust_components()) or self.get(pid)
        plano.project.update(trusted=True, trusted_with=item.get("trusted_with"))
        return public_project(item)

    # análise

    def inspect(self, pid: object) -> dict[str, Any]:
        plano = self.analyze(pid)
        if plano.interpreter is None:
            plano.candidates = self._candidates()
        return plano.to_dict()

    _UNSET = object()

    def configure(self, pid: object, interpreter: object = _UNSET, entry: object = _UNSET) -> dict[str, Any]:
        """Override de interpretador e entrada. `None` remove; ausente fica como está."""
        projeto = self.get(pid)
        campos: dict[str, Any] = {}
        if interpreter is not self._UNSET:
            campos["interpreter_override"] = None if interpreter is None else validate_interpreter_path(interpreter)
        if entry is not self._UNSET:
            campos["entry_override"] = None if entry is None else validate_entry_path(Path(projeto["root"]), entry)
        if campos:
            self.store.update(projeto["id"], **campos)
        return self.inspect(projeto["id"])

    def analyze(self, pid: object) -> ProjectPlan:
        projeto = self.get(pid)
        raiz = Path(projeto["root"])
        if not raiz.is_dir():
            raise InvalidInputError(f"A pasta do projeto não existe mais: {raiz}")
        analise = _Analyzer(raiz)
        entrada = projeto.get("entry_override") or projeto.get("entry") or detect_entry(raiz)
        if entrada is None:
            analise.problem("Não achei o arquivo de entrada (main.py, run.py, __main__.py ou um .py com "
                            f"{MAIN_FUNCTION} ou if __name__ == \"__main__\").")

        funcao = None
        configs: list[ConfigInfo] = []
        suites: list[dict[str, Any]] = []
        nao_usadas: list[str] = []
        arvore = analise.tree(entrada) if entrada else None
        if arvore is not None and entrada is not None:
            try:
                funcao = _main_function(arvore)
                if funcao is None:
                    analise.problem(f"Não achei a função principal em {entrada}.", entrada)
                configs, suites, nao_usadas = self._read_main(analise, arvore, entrada, funcao)
            except (RecursionError, MemoryError):
                # Rede de segurança: o percurso é iterativo, mas `ast.unparse`
                # e os dicts aninhados ainda descem por recursão.
                configs, suites, nao_usadas = [], [], []
                analise.problem("Arquivo complexo demais para ler sem executar.", entrada)

        execucoes = _read_run_configurations(analise, raiz)
        escolhida = _pick_run_configuration(execucoes, raiz, entrada)
        interpretador, origem = None, None
        pasta_trabalho = raiz
        env: dict[str, str] = {}
        resumo_rc = None
        if escolhida is not None:
            opcoes = escolhida["options"]
            sdk = _expand(opcoes.get("SDK_HOME", ""), raiz).strip()
            if sdk:
                interpretador, origem = sdk, "run_configuration"
            elif opcoes.get("SDK_NAME"):
                # Run configuration que aponta um SDK pelo nome: o caminho
                # mora nas configurações do PyCharm, como no misc.xml.
                caminho = pycharm_sdk_home(opcoes["SDK_NAME"], self.pycharm_options)
                if caminho:
                    interpretador, origem = caminho, "pycharm_sdk"
            trabalho = _expand(opcoes.get("WORKING_DIRECTORY", ""), raiz).strip()
            if trabalho:
                if Path(trabalho).is_dir():
                    pasta_trabalho = Path(trabalho)
                else:
                    analise.problem(f"A pasta de trabalho da run configuration não existe: {trabalho}",
                                    escolhida["file"])
            # Como o PyCharm, `$PROJECT_DIR$` e `$USER_HOME$` valem nos valores (D-O6).
            env = {nome: _expand(valor, raiz) for nome, valor in escolhida["envs"].items()}
            resumo_rc = {"name": escolhida["name"], "file": escolhida["file"], "env_names": list(env)}
        if interpretador is None:
            nome_sdk = _misc_sdk_name(analise, raiz)
            if nome_sdk:
                caminho = pycharm_sdk_home(nome_sdk, self.pycharm_options)
                if caminho:
                    interpretador, origem = caminho, "pycharm_sdk"
                else:
                    analise.problem(f"O PyCharm guarda o SDK \"{nome_sdk}\" só pelo nome, e não achei o caminho dele "
                                    "nas configurações do PyCharm.", f"{IDEA_DIR}/misc.xml")
        if interpretador is None:
            venv = _venv_python(raiz)
            if venv:
                interpretador, origem = venv, "venv"
        if projeto.get("interpreter_override"):
            # O dono escolheu: vale mais que qualquer detecção.
            interpretador, origem = projeto["interpreter_override"], "manual"

        mascaras: set[str] = set()
        for config in configs:
            mascaras |= config.secrets
        for nome, valor in env.items():
            if len(valor) >= MIN_ENV_MASK or (_sensitive(nome) and len(valor) >= MIN_MASK):
                mascaras |= secret_forms(valor)

        plano = ProjectPlan(
            project=projeto, root=raiz, entry_file=entrada, entry_function=funcao,
            interpreter=interpretador, interpreter_source=origem, working_dir=pasta_trabalho,
            run_configuration=resumo_rc, configs=configs, suites=suites, unused_suites=nao_usadas,
            problems=analise.problems, env=env,
            masks=sorted(mascaras, key=len, reverse=True),
        )
        self._check_trust(plano)
        return plano

    def _check_trust(self, plano: ProjectPlan) -> None:
        """Confiança presa ao que o diálogo mostrou (D-O2): mudou, zera."""
        projeto = plano.project
        if not projeto.get("trusted"):
            return
        atual = plano.trust_components()
        antes = projeto.get("trusted_with")
        if antes == atual:
            return
        mudou = [chave for chave in atual if not isinstance(antes, dict) or antes.get(chave) != atual[chave]]
        self.store.update(projeto["id"], trusted=False, trusted_with=None)
        projeto["trusted"], projeto["trusted_with"] = False, None
        rotulos = {"root": "a pasta", "interpreter": "o interpretador", "entry": "a entrada",
                   "working_dir": "a pasta de trabalho", "env_names": "as variáveis de ambiente"}
        plano.problems.append({
            "file": None, "line": None,
            "message": "A confiança no projeto foi retirada porque mudou " + ", ".join(rotulos[c] for c in mudou)
                       + " desde que você confiou. Confirme de novo antes de rodar.",
        })

    def _read_main(self, analise: _Analyzer, arvore: ast.Module, entrada: str,
                   funcao: str | None) -> tuple[list[ConfigInfo], list[dict[str, Any]], list[str]]:
        funcoes = {n.name: n for n in arvore.body if isinstance(n, ast.FunctionDef)}
        corpo = funcoes.get(funcao) if funcao else None
        configs: list[ConfigInfo] = []
        suites: list[dict[str, Any]] = []
        chamadas_nomes: list[str] = []
        if corpo is not None:
            apelidos = _local_aliases(corpo)
            for chamada, condicional in _init_calls(corpo):
                argumento = chamada.args[0] if chamada.args else None
                if isinstance(argumento, ast.Name):
                    nome, indireto = argumento.id, argumento.id in apelidos
                    nome = apelidos.get(nome, nome)
                elif argumento is not None:
                    nome, indireto = ast.unparse(argumento)[:80], True
                else:
                    continue
                if any(c.name == nome for c in configs):
                    continue
                configs.append(ConfigInfo(nome, active=True, line=chamada.lineno, conditional=condicional,
                                          indirect=indireto))
            ativas = [c for c in configs if c.active]
            if len(ativas) > 1:
                analise.problem(f"O main tem {len(ativas)} init(...) ativos: "
                                + ", ".join(c.name for c in ativas) + ".", entrada, ativas[1].line)
            elif ativas and (ativas[0].conditional or ativas[0].indirect):
                analise.problem("O init(...) do main está dentro de if/try ou recebe uma variável; não dá para "
                                "saber qual config roda sem executar.", entrada, ativas[0].line)
            for chamada in _calls_in_order(corpo.body):
                nome = _call_name(chamada)
                if (nome and nome not in ("init", "finish", "print") and isinstance(chamada.func, ast.Name)
                        and (nome in funcoes or nome.startswith("test_suite"))):
                    chamadas_nomes.append(nome)
            texto = analise.read(entrada) or ""
            fim = getattr(corpo, "end_lineno", None) or corpo.lineno
            for nome, linha in _commented_inits(texto, corpo.lineno, fim):
                if all(c.name != nome for c in configs):
                    configs.append(ConfigInfo(nome, active=False, line=linha))
            if not any(c.active for c in configs):
                analise.problem(f"Não achei um init(config_...) ativo em {funcao}.", entrada, corpo.lineno)

        for nome in chamadas_nomes:
            definicao = funcoes.get(nome)
            suite: dict[str, Any] = {"name": nome, "defined": definicao is not None,
                                     "line": definicao.lineno if definicao else None, "runs": []}
            if definicao is None:
                analise.problem(f"A suíte {nome} é chamada mas não está definida em {entrada}.", entrada)
            else:
                suite["runs"] = [self._read_run(analise, chamada)
                                 for chamada in _calls_in_order(definicao.body) if _call_name(chamada) == "executar"]
            suites.append(suite)

        chamadas = set(chamadas_nomes)
        nao_usadas = [nome for nome, definicao in funcoes.items()
                      if nome not in chamadas and nome != funcao
                      and any(_call_name(c) == "executar" for c in _calls_in_order(definicao.body))]

        self._resolve_configs(analise, arvore, entrada, configs)
        return configs, suites, nao_usadas

    @staticmethod
    def _read_run(analise: _Analyzer, chamada: ast.Call) -> dict[str, Any]:
        argumentos: dict[str, ast.AST] = {}
        for indice, nome in enumerate(("squad", "feature")):
            if len(chamada.args) > indice:
                argumentos[nome] = chamada.args[indice]
        for palavra in chamada.keywords:
            if palavra.arg in ("squad", "feature"):
                argumentos[palavra.arg] = palavra.value
        squad = _literal(argumentos["squad"]) if "squad" in argumentos else None
        feature = _literal(argumentos["feature"]) if "feature" in argumentos else None
        resultado: dict[str, Any] = {
            "squad": squad if squad is not None or "squad" not in argumentos else DYNAMIC,
            "feature": feature if feature is not None or "feature" not in argumentos else DYNAMIC,
            "line": chamada.lineno, "found": False, "path": None, "title": None, "scenarios": [],
        }
        if feature is None:
            return resultado
        candidatos = ["features/" + feature]
        if squad:
            candidatos += [f"{squad}/{feature}", f"{squad}/features/{feature}"]
        candidatos.append(feature)
        for candidato in candidatos:
            caminho = Path(candidato)
            if caminho.is_absolute() or ".." in caminho.parts or caminho.suffix != ".feature":
                continue
            if _exists_plain(analise.root, candidato) and (analise.root / candidato).is_file():
                texto = analise.read(candidato)
                if texto is None:
                    break
                titulo, cenarios = parse_feature_text(texto)
                resultado.update(found=True, path=candidato, title=titulo, scenarios=cenarios)
                return resultado
        analise.problem(f"Não achei a feature {feature} (squad {squad or '?'}).", None, chamada.lineno)
        return resultado

    @staticmethod
    def _resolve_configs(analise: _Analyzer, arvore: ast.Module, entrada: str, configs: list[ConfigInfo]) -> None:
        fontes = _config_sources(arvore, entrada)
        for config in configs:
            arquivos = [entrada, *fontes.get(config.name, []), *fontes.get("**", [])]
            for arquivo in dict.fromkeys(arquivos):
                if not _exists_plain(analise.root, arquivo) or not (analise.root / arquivo).is_file():
                    if arquivo in fontes.get(config.name, []) and (analise.root / arquivo).is_symlink():
                        analise.read(arquivo)
                    continue
                modulo = analise.tree(arquivo)
                if modulo is None:
                    continue
                atribuicoes = _module_assignments(modulo)
                no = atribuicoes.get(config.name)
                if no is None:
                    continue
                constantes = {nome: n.value for nome, n in atribuicoes.items() if n.value is not None}
                config.found, config.file, config.line = True, arquivo, no.lineno
                if no.value is not None:
                    _fill_config(config, no.value, constantes)
                # Constante de módulo com nome sensível no mesmo arquivo
                # (`KOBITON_API_KEY = "…"` usada pelo runner): entra na máscara.
                for nome_constante, valor in constantes.items():
                    literal = _literal(valor)
                    if literal and len(literal) >= MIN_MASK and _sensitive(nome_constante) and "://" not in literal:
                        config.secrets |= secret_forms(literal)
                break
            if not config.found:
                analise.problem(f"Não achei a definição de {config.name} no projeto.", entrada, config.line)
