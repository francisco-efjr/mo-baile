"""Doctor do projeto do dono (B1): pré-requisitos antes de rodar o `main`.

Uma linha por checagem, com id estável, estado (`ok`, `warn`, `fail`,
`skip`), mensagem e dica. O doctor **só olha**: nada instala, apaga ou
reinicia. O Python do projeto roda apenas `-c` com `importlib.metadata` e
`-m pip check` (que não muda o ambiente), sempre com `-E` e numa pasta
vazia, para um `json.py` do projeto nunca ser importado no lugar do da
biblioteca padrão. No aparelho, só leitura (`adb devices`, `getprop`,
`pm list packages`, `dumpsys`).

Config ativa na nuvem (Kobiton) não é rodada na B1: a checagem `cloud` falha
e as que tocariam porta ou aparelho são puladas, porque o alvo nem é local.
"""

from __future__ import annotations

import json
import logging
import os
import re
import socket
import subprocess
import tempfile
from collections.abc import Callable
from pathlib import Path
from typing import Any

from mobaile.domain.errors import InvalidInputError
from mobaile.services.project_run import mask_line
from mobaile.services.projects import (
    DYNAMIC,
    HUB_CLOUD,
    HUB_UNKNOWN,
    ConfigInfo,
    ProjectFileError,
    ProjectPlan,
    read_project_text,
)

logger = logging.getLogger(__name__)

OK, WARN, FAIL, SKIP = "ok", "warn", "fail", "skip"

CHECK_IDS: tuple[str, ...] = (
    "interpreter", "packages", "requirements", "pip_check", "appium", "appium_port", "device", "app",
    "uiautomation", "cloud", "features",
)
LABELS = {
    "interpreter": "Interpretador do projeto",
    "packages": "Pacotes de teste",
    "requirements": "requirements.txt",
    "pip_check": "Dependências (pip check)",
    "appium": "Appium e driver",
    "appium_port": "Porta do Appium",
    "device": "Aparelho da config",
    "app": "App no aparelho",
    "uiautomation": "UiAutomation livre",
    "cloud": "Config local",
    "features": "Features do main",
}

PACKAGES = ("behave", "pytest-bdd", "Appium-Python-Client", "selenium", "allure-behave")
_LOOPBACK = frozenset({"127.0.0.1", "localhost", "::1"})
DEFAULT_HUB = "127.0.0.1:4723"
PIP_CHECK_TIMEOUT = 60
PYTHON_TIMEOUT = 20
_REQ_LINE = re.compile(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\[[^\]]*\])?\s*(==|>=|<=|~=|!=|>|<)?\s*([^\s;#,]*)")

_VERSIONS_CODE = (
    "import importlib.metadata as m, json\n"
    "NOMES = {nomes}\n"
    "def v(n):\n"
    "    try:\n"
    "        return m.version(n)\n"
    "    except m.PackageNotFoundError:\n"
    "        return None\n"
    "print(json.dumps({{n: v(n) for n in NOMES}}))\n"
)

Runner = Callable[..., tuple[int, str, str]]


def _canon(nome: str) -> str:
    return re.sub(r"[-_.]+", "-", nome).lower()


def run_python(args: list[str], timeout: float, env: dict[str, str] | None = None) -> tuple[int, str, str]:
    """Roda o Python do projeto numa pasta vazia, sem stdin, e devolve (código, saída, erro)."""
    with tempfile.TemporaryDirectory(prefix="mobaile-doctor-") as vazia:
        proc = subprocess.run(
            args, capture_output=True, text=True, timeout=timeout, cwd=vazia, stdin=subprocess.DEVNULL,
            env=env, check=False, encoding="utf-8", errors="replace",
        )
    return proc.returncode, proc.stdout or "", proc.stderr or ""


def port_open(host: str, port: int) -> bool:
    """Alguém ouve em host:porta? Só loopback: o doctor nunca abre conexão para fora."""
    if host not in _LOOPBACK:
        return False
    alvo = "::1" if host == "::1" else "127.0.0.1"
    try:
        with socket.create_connection((alvo, port), timeout=0.5):
            return True
    except OSError:
        return False


def _check(cid: str, state: str, message: str, hint: str | None = None, needs_trust: bool = False) -> dict[str, Any]:
    return {"id": cid, "label": LABELS[cid], "state": state, "message": message, "hint": hint,
            "needs_trust": needs_trust}


TRUST_HINT = "Use \"Confiar neste projeto\" para o Mo baile rodar o Python dele e completar estas checagens."
PYTHON_CHECKS = ("interpreter", "packages", "requirements", "pip_check")


class ProjectDoctor:
    """Roda as checagens de `CHECK_IDS` sobre o plano de `ProjectService.analyze`."""

    def __init__(self, *, adb, appium, ios=None, run: Runner = run_python,
                 port_open: Callable[[str, int], bool] = port_open,
                 appium_home: Path | str | None = None) -> None:
        self.adb = adb
        self.appium = appium
        self.ios = ios
        self._run = run
        self._port_open = port_open
        self._appium_home_dir = Path(appium_home) if appium_home else None

    # ------------------------------------------------------------- execução

    def run(self, plan: ProjectPlan, device_id: str | None = None,
            progress: Callable[..., None] | None = None,
            check_cancelled: Callable[[], None] | None = None) -> dict[str, Any]:
        estado = _Estado(plan, device_id)
        etapas: list[tuple[str, Callable[[_Estado], dict[str, Any]]]] = [
            ("interpreter", self._interpreter), ("packages", self._packages), ("requirements", self._requirements),
            ("pip_check", self._pip_check), ("appium", self._appium), ("appium_port", self._appium_port),
            ("device", self._device), ("app", self._app), ("uiautomation", self._uiautomation),
            ("cloud", self._cloud), ("features", self._features),
        ]
        checks = []
        for indice, (cid, funcao) in enumerate(etapas):
            if check_cancelled is not None:
                check_cancelled()
            if progress is not None:
                progress(f"Conferindo: {LABELS[cid]}", 100.0 * indice / len(etapas))
            try:
                checks.append(funcao(estado))
            except InvalidInputError as exc:
                checks.append(_check(cid, WARN, f"Não deu para conferir: {exc.message}"))
            except (OSError, subprocess.SubprocessError, ValueError) as exc:
                logger.info("Checagem %s do doctor falhou: %s", cid, exc)
                checks.append(_check(cid, WARN, f"Não deu para conferir: {exc}"))
        # A saída do Python do projeto (stderr, pip check) passa pela máscara do
        # plano antes de ir ao RPC (SEC-B1-10).
        for checagem in checks:
            checagem["message"] = mask_line(checagem["message"], plan.masks)
            if checagem["hint"]:
                checagem["hint"] = mask_line(checagem["hint"], plan.masks)
        resumo = {s: sum(1 for c in checks if c["state"] == s) for s in (OK, WARN, FAIL, SKIP)}
        return {"project_id": plan.project["id"], "checks": checks, "summary": resumo, "ready": resumo[FAIL] == 0,
                "trusted": bool(plan.project.get("trusted"))}

    # ------------------------------------------------------------ python

    def _env(self, plan: ProjectPlan) -> dict[str, str]:
        # Sem as `envs` da run configuration (CR-02): elas são do projeto e
        # podem trazer DYLD_*; para ler versões, o ambiente do motor basta.
        return {**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}

    def _python(self, estado: _Estado, args: list[str], timeout: float = PYTHON_TIMEOUT) -> tuple[int, str, str]:
        python = estado.python or estado.plan.interpreter
        if not python:
            raise ValueError("o interpretador do projeto não está disponível")
        if not estado.plan.project.get("trusted"):
            # Defesa em profundidade: as checagens já pulam sem confiança (D-O1).
            raise ValueError("o projeto ainda não é confiável")
        return self._run([python, "-E", *args], timeout, env=self._env(estado.plan))

    def _versions(self, estado: _Estado, nomes: list[str]) -> dict[str, str | None]:
        faltando = [n for n in nomes if n not in estado.versions]
        if faltando:
            codigo = _VERSIONS_CODE.format(nomes=json.dumps(faltando))
            ret, saida, erro = self._python(estado, ["-c", codigo])
            if ret != 0:
                raise ValueError((erro or saida).strip().splitlines()[-1:] or "o Python do projeto não respondeu")
            dados = json.loads(saida.strip().splitlines()[-1])
            estado.versions.update({n: dados.get(n) for n in faltando})
        return {n: estado.versions.get(n) for n in nomes}

    def _interpreter(self, estado: _Estado) -> dict[str, Any]:
        plan = estado.plan
        if not plan.interpreter:
            return _check("interpreter", FAIL, "Não achei o interpretador do projeto.",
                          "Escolha o interpretador na aba Execução, ou no PyCharm marque a run configuration "
                          "como \"Store as project file\" (.idea/runConfigurations).")
        if not (os.path.isfile(plan.interpreter) and os.access(plan.interpreter, os.X_OK)):
            return _check("interpreter", FAIL, f"O interpretador {plan.interpreter} não existe nesta máquina.",
                          "Confira o SDK da run configuration no PyCharm ou recrie o .venv do projeto.")
        if not plan.project.get("trusted"):
            # O interpretador vem do projeto (.venv, SDK_HOME): rodá-lo já é
            # executar código do projeto, então só depois da confiança (D-O1).
            estado.needs_trust = True
            return _check("interpreter", SKIP, f"{plan.interpreter} existe; o Mo baile só roda o Python do "
                                               "projeto depois que você confiar nele.", TRUST_HINT, needs_trust=True)
        try:
            ret, saida, erro = self._python(estado, ["-c", "import sys; print(sys.version.split()[0])"])
        except subprocess.TimeoutExpired:
            return _check("interpreter", FAIL, f"{plan.interpreter} não respondeu em {PYTHON_TIMEOUT} s.")
        except OSError as exc:
            return _check("interpreter", FAIL, f"Não consegui rodar {plan.interpreter}: {exc}")
        if ret != 0:
            return _check("interpreter", FAIL, f"{plan.interpreter} falhou: {(erro or saida).strip()[-200:]}")
        estado.python = plan.interpreter
        origem = {"run_configuration": "run configuration do PyCharm", "venv": ".venv do projeto"}.get(
            plan.interpreter_source or "", "")
        return _check("interpreter", OK, f"Python {saida.strip()} · {plan.interpreter}" + (f" ({origem})" if origem else ""))

    def _sem_python(self, cid: str, estado: _Estado | None = None) -> dict[str, Any]:
        if estado is not None and estado.needs_trust:
            return _check(cid, SKIP, "Pulada até você confiar no projeto.", TRUST_HINT, needs_trust=True)
        if estado is not None and not estado.plan.project.get("trusted"):
            # Sem interpretador e sem confiança: faltam as duas coisas.
            return _check(cid, SKIP, "Pulada: o interpretador do projeto não está disponível, e o projeto ainda "
                                     "não é confiável.", TRUST_HINT, needs_trust=True)
        return _check(cid, SKIP, "Pulada: o interpretador do projeto não está disponível.")

    def _packages(self, estado: _Estado) -> dict[str, Any]:
        if estado.python is None:
            return self._sem_python("packages", estado)
        versoes = self._versions(estado, list(PACKAGES))
        presentes = [f"{n} {v}" for n, v in versoes.items() if v]
        texto = " · ".join(presentes) or "nenhum"
        if not versoes.get("behave") and not versoes.get("pytest-bdd"):
            return _check("packages", FAIL, f"Nem behave nem pytest-bdd no Python do projeto ({texto}).",
                          "Instale as dependências do projeto no interpretador dele; o Mo baile não instala nada.")
        if not versoes.get("Appium-Python-Client"):
            return _check("packages", WARN, f"Sem o Appium-Python-Client ({texto}).",
                          "Sem ele o init do projeto não abre sessão no Appium.")
        return _check("packages", OK, texto)

    def _requirements(self, estado: _Estado) -> dict[str, Any]:
        if estado.python is None:
            return self._sem_python("requirements", estado)
        try:
            texto = read_project_text(estado.plan.root, "requirements.txt")
        except ProjectFileError:
            return _check("requirements", SKIP, "O projeto não tem requirements.txt na raiz.")
        pedidos: list[tuple[str, str | None, str | None]] = []
        for linha in texto.splitlines():
            linha = linha.split("#", 1)[0].strip()
            if not linha or linha.startswith(("-", "git+", "http")) or "://" in linha:
                continue
            achado = _REQ_LINE.match(linha)
            if achado:
                pedidos.append((achado.group(1), achado.group(2), achado.group(3) or None))
        if not pedidos:
            return _check("requirements", SKIP, "requirements.txt sem pacotes que dê para conferir.")
        versoes = self._versions(estado, [nome for nome, _, _ in pedidos])
        faltam = [nome for nome, _, _ in pedidos if not versoes.get(nome)]
        diferentes = [f"{nome} {versoes[nome]} (pede {versao})" for nome, op, versao in pedidos
                      if op == "==" and versao and versoes.get(nome) and versoes[nome] != versao]
        if faltam or diferentes:
            partes = []
            if faltam:
                partes.append("faltam " + ", ".join(faltam))
            if diferentes:
                partes.append("versão diferente: " + ", ".join(diferentes))
            return _check("requirements", WARN, "; ".join(partes) + ".",
                          "Rode o pip install -r requirements.txt no interpretador do projeto; "
                          "o Mo baile não instala nada.")
        return _check("requirements", OK, f"{len(pedidos)} pacotes do requirements.txt instalados.")

    def _pip_check(self, estado: _Estado) -> dict[str, Any]:
        if estado.python is None:
            return self._sem_python("pip_check", estado)
        try:
            ret, saida, erro = self._python(estado, ["-m", "pip", "check"], timeout=PIP_CHECK_TIMEOUT)
        except subprocess.TimeoutExpired:
            return _check("pip_check", WARN, f"pip check não terminou em {PIP_CHECK_TIMEOUT} s.")
        if "No module named pip" in erro:
            return _check("pip_check", SKIP, "O Python do projeto não tem pip.")
        if ret == 0:
            return _check("pip_check", OK, "Nenhuma dependência quebrada.")
        linhas = [linha for linha in (saida or erro).strip().splitlines() if linha.strip()]
        return _check("pip_check", WARN, " · ".join(linhas[:3]) or "pip check apontou problema.",
                      "pip check só lê; quem corrige é o pip do projeto.")

    # ------------------------------------------------------------ appium

    def _appium_home(self) -> Path:
        if self._appium_home_dir:
            return self._appium_home_dir
        return Path(os.environ.get("APPIUM_HOME") or Path.home() / ".appium")

    @staticmethod
    def _package_json_version(caminho: Path) -> str | None:
        try:
            return str(json.loads(caminho.read_text(encoding="utf-8")).get("version") or "") or None
        except (OSError, ValueError, AttributeError):
            return None

    def _appium(self, estado: _Estado) -> dict[str, Any]:
        ativa = estado.config
        if ativa is not None and ativa.cloud:
            return _check("appium", SKIP, "Pulada: a config ativa roda na nuvem.")
        binario = self.appium.locate_appium()
        if not binario:
            return _check("appium", FAIL, "Appium não encontrado nesta máquina.",
                          "Instale pela tela Ambiente (alvo appium).")
        versao = None
        for pasta in list(Path(os.path.realpath(binario)).parents)[:3]:
            versao = self._package_json_version(pasta / "package.json")
            if versao:
                break
        rotulo = f"Appium {versao}" if versao else "Appium"
        modulos = self._appium_home() / "node_modules"
        drivers = {
            "uiautomator2": self._package_json_version(modulos / "appium-uiautomator2-driver" / "package.json"),
            "xcuitest": self._package_json_version(modulos / "appium-xcuitest-driver" / "package.json"),
        }
        presentes = [f"{nome} {v}" for nome, v in drivers.items() if v]
        texto = f"{rotulo} · " + (", ".join(presentes) if presentes else "sem drivers")
        plataforma = ativa.platform if ativa else None
        precisa = {"android": "uiautomator2", "ios": "xcuitest"}.get(plataforma or "")
        if precisa and not drivers[precisa]:
            return _check("appium", WARN, f"{texto}. Falta o driver {precisa}.",
                          f"appium driver install {precisa}")
        return _check("appium", OK, texto)

    def _appium_port(self, estado: _Estado) -> dict[str, Any]:
        ativa = estado.config
        if ativa is None:
            return _check("appium_port", SKIP, "Pulada: não há config ativa.")
        if ativa.cloud:
            return _check("appium_port", SKIP, "Pulada: a config ativa roda na nuvem.")
        if ativa.hub == DYNAMIC:
            return _check("appium_port", SKIP, "A URL do hub é montada em tempo de execução; não deu para conferir.")
        hub = ativa.hub or DEFAULT_HUB
        host, _, porta_texto = hub.rpartition(":")
        host = host.strip("[]") or "127.0.0.1"
        try:
            porta = int(porta_texto)
        except ValueError:
            return _check("appium_port", SKIP, f"Hub sem porta legível: {hub}.")
        if host not in _LOOPBACK:
            return _check("appium_port", SKIP, f"O hub {hub} não é desta máquina; o Mo baile não abre conexão para fora.")
        padrao = "" if ativa.hub else " (a config não diz o hub; usei o padrão do Appium)"
        if not self._port_open(host, porta):
            return _check("appium_port", WARN, f"Ninguém ouve em {hub}{padrao}.",
                          "Se o init do projeto não sobe o Appium, suba antes de rodar "
                          f"(appium --address 127.0.0.1 --port {porta}).")
        if self.appium.owns_server_on(porta):
            return _check("appium_port", OK, f"Appium do Mo baile em {hub}{padrao}. A sessão do Mo baile é "
                                             "fechada antes de rodar; o servidor continua de pé.")
        return _check("appium_port", OK, f"Appium já ouvindo em {hub}{padrao}.")

    # ------------------------------------------------------------ aparelho

    def _device(self, estado: _Estado) -> dict[str, Any]:
        ativa = estado.config
        if ativa is None or ativa.cloud:
            return _check("device", SKIP, "Pulada: " + ("não há config ativa." if ativa is None
                                                         else "a config ativa roda na nuvem."))
        udid = ativa.values.get("udid")
        udid = None if udid == DYNAMIC else udid
        escolhido = estado.device_id
        plataforma = ativa.platform
        if plataforma == "ios":
            return self._device_ios(estado, udid, escolhido)
        conectados = dict(self.adb.list_devices())
        alvo = udid or escolhido
        if alvo is None:
            return _check("device", WARN, "A config não fixa o udid e nenhum aparelho foi escolhido.",
                          "Escolha o aparelho alvo na barra Rodar.")
        if alvo not in conectados:
            return _check("device", FAIL, f"O aparelho {alvo} da config não está conectado.",
                          "Ligue o emulador ou conecte o aparelho e rode o doctor de novo.")
        if conectados[alvo] != "device":
            return _check("device", FAIL, f"O aparelho {alvo} está {conectados[alvo]}.",
                          "Autorize a depuração USB no aparelho.")
        estado.device_ok = alvo
        avisos = []
        if udid and escolhido and escolhido != udid:
            avisos.append(f"A config aponta para {udid}, e você escolheu {escolhido}: o teste usa o da config")
        esperado = ativa.values.get("platformVersion")
        if esperado and esperado != DYNAMIC:
            real = self.adb.get_prop(alvo, "ro.build.version.release")
            if real and real.split(".")[0] != esperado.split(".")[0]:
                avisos.append(f"a config pede Android {esperado} e o aparelho tem {real}")
        if avisos:
            return _check("device", WARN, "; ".join(avisos) + ".")
        return _check("device", OK, f"{alvo} conectado.")

    def _device_ios(self, estado: _Estado, udid: str | None, escolhido: str | None) -> dict[str, Any]:
        alvo = udid or escolhido
        if alvo is None:
            return _check("device", WARN, "A config não fixa o udid e nenhum aparelho foi escolhido.")
        ligados = dict(self.ios.list_booted_simulators()) if self.ios is not None else {}
        if alvo in ligados:
            estado.device_ok = alvo
            return _check("device", OK, f"Simulador {ligados[alvo]} ({alvo}) ligado.")
        return _check("device", WARN, f"{alvo} não é um simulador ligado. Se for um iPhone físico, o Mo baile "
                                      "não confere nem grava vídeo dele nesta versão.")

    def _app(self, estado: _Estado) -> dict[str, Any]:
        ativa = estado.config
        if ativa is None or ativa.cloud:
            return _check("app", SKIP, "Pulada: a config ativa não é local.")
        app = ativa.values.get("app")
        if app and app != DYNAMIC and "://" not in app and not re.match(r"^[A-Za-z][\w-]*:", app):
            caminho = Path(app).expanduser()
            if not caminho.is_absolute():
                caminho = estado.plan.working_dir / caminho
            if caminho.exists():
                return _check("app", OK, f"{app} existe.")
            return _check("app", FAIL, f"O app {app} não existe em {caminho.parent}.",
                          "Gere o build do app ou corrija o caminho de app na config.")
        pacote = ativa.values.get("appPackage")
        if ativa.platform == "android" and pacote and pacote != DYNAMIC:
            if not estado.device_ok:
                return _check("app", SKIP, "Pulada: o aparelho da config não está disponível.")
            instalado = self.adb.package_installed(estado.device_ok, pacote)
            if instalado is None:
                return _check("app", WARN, f"Não deu para conferir se {pacote} está instalado.")
            if instalado:
                return _check("app", OK, f"{pacote} instalado em {estado.device_ok}.")
            return _check("app", FAIL, f"{pacote} não está instalado em {estado.device_ok}.",
                          "Instale o app de HLG no aparelho antes de rodar.")
        return _check("app", SKIP, "A config não diz um app que dê para conferir sem executar.")

    def _uiautomation(self, estado: _Estado) -> dict[str, Any]:
        ativa = estado.config
        if ativa is None or ativa.platform != "android" or ativa.cloud:
            return _check("uiautomation", SKIP, "Só vale para Android local.")
        if not estado.device_ok:
            return _check("uiautomation", SKIP, "Pulada: o aparelho da config não está disponível.")
        dono = self.adb.uiautomation_holder(estado.device_ok)
        if dono:
            app = dono.removesuffix(".test")
            return _check("uiautomation", WARN, f"A instrumentação {dono} ocupa o UiAutomation; o Appium do "
                                                "projeto não vai conseguir abrir sessão.",
                          f"Encerre a ferramenta que a abriu ou rode: adb -s {estado.device_ok} shell am force-stop {app}")
        return _check("uiautomation", OK, "Nenhuma outra instrumentação ativa.")

    # ------------------------------------------------------------ projeto

    def _cloud(self, estado: _Estado) -> dict[str, Any]:
        """`fail` para nuvem, `warn` para hub que a análise não prova local (D-O3)."""
        ativa = estado.config
        if ativa is None:
            return _check("cloud", FAIL, "Não achei um init(config_...) ativo no main.")
        situacao, motivo = estado.plan.hub()
        if situacao == HUB_CLOUD:
            return _check("cloud", FAIL, f"{motivo} Esta versão só roda local.",
                          "Ative uma config local no main (descomente o init local) para rodar pelo Mo baile.")
        if situacao == HUB_UNKNOWN:
            return _check("cloud", WARN, motivo or "Não dá para provar que a execução é local.",
                          "Deixe um init(config_local) só, fora de if/try, com a URL do hub escrita na config; "
                          "ou confirme ao rodar que a execução é local.")
        return _check("cloud", OK, f"{ativa.name} é local.")

    def _features(self, estado: _Estado) -> dict[str, Any]:
        execucoes = [r for s in estado.plan.suites for r in s["runs"]]
        if not execucoes:
            return _check("features", WARN, "O main não chama nenhum executar(squad, feature) que eu consiga ler.")
        faltam = [str(r["feature"]) for r in execucoes if not r["found"]]
        if faltam:
            return _check("features", FAIL, "Não achei: " + ", ".join(dict.fromkeys(faltam)) + ".",
                          "Confira o caminho da feature em executar(...).")
        return _check("features", OK, f"{len(execucoes)} execuções, todas com a feature encontrada.")


class _Estado:
    def __init__(self, plan: ProjectPlan, device_id: str | None) -> None:
        self.plan = plan
        self.device_id = device_id
        self.config: ConfigInfo | None = plan.active_config
        self.python: str | None = None
        self.versions: dict[str, str | None] = {}
        self.device_ok: str | None = None
        self.needs_trust = False
