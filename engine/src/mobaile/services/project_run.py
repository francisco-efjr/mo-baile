"""Execução do `main` do projeto do dono (B1-3).

O motor roda `[interpretador, entrada]` como subprocesso, do jeito que a run
configuration "Python" do PyCharm faria, e acrescenta o que o PyCharm não dá:
console ao vivo pelo RPC, vídeo da tela gravado junto e um resultado lido do
resumo do behave.

Decisões que valem para o módulo:

- **O código de saída não decide.** O `main` do dono engole exceção com
  `print(e)` e sai com 0 mesmo quando um cenário falha; o behave nem lança
  exceção por falha de step. O resultado vem das linhas de resumo que o
  behave imprime no fim de cada chamada (`N features passed, M failed...`),
  somadas quando o `main` chama o behave mais de uma vez. Sem resumo nenhum,
  o resultado é `indeterminate`, com a última linha de erro do console.
- **Grupo de processos próprio** (`start_new_session=True`): parar manda
  SIGINT, depois SIGTERM, depois SIGKILL para o grupo inteiro, e os netos (um
  Appium que o `init` subiu, um `sleep` de um step) morrem junto.
- **Máscara antes de tudo.** Cada linha passa pela máscara (valores literais
  sensíveis das configs e das `envs` da run configuration) antes de ir para o
  RPC, para o `console.log` ou para o log do motor.
- **Vídeo junto, sem disputar o UiAutomation**: no Android, `scrcpy
  --no-playback --no-window --no-audio --record`; sem scrcpy, `adb shell
  screenrecord` (que para em 180 s) com aviso. Simulador iOS, `simctl io
  recordVideo --codec h264`. iPhone físico: sem vídeo, com aviso. O vídeo
  para com SIGINT, para o MP4 fechar o índice.
- **Pasta da execução**: `~/Documents/Mo baile/Execuções/<projeto>/<AAAAMMDD-
  HHMMSS>/` com `console.log`, `video.mp4` e `resumo.json` (`MOBAILE_RUNS_DIR`
  troca a raiz, como os testes fazem).
"""

from __future__ import annotations

import json
import logging
import os
import re
import signal
import subprocess
import threading
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

from mobaile.adapters.scrcpy import ScrcpyRecording
from mobaile.domain.errors import EngineError
from mobaile.domain.models import Platform
from mobaile.security import safe_file_stem
from mobaile.security.paths import write_file_atomic

logger = logging.getLogger(__name__)

RUNS_DIR_ENV = "MOBAILE_RUNS_DIR"
CONSOLE_FILE = "console.log"
VIDEO_FILE = "video.mp4"
SUMMARY_FILE = "resumo.json"
MASK = "***"

PASSED, FAILED, INDETERMINATE, CANCELLED = "passed", "failed", "indeterminate", "cancelled"

# Linha longa demais vira "…" no RPC; o console.log guarda até o teto em bytes.
MAX_LINE_CHARS = 4000
MAX_CONSOLE_BYTES = 50 * 1024 * 1024
# Prazos de cada degrau da parada: SIGINT (o behave fecha o cenário), SIGTERM,
# SIGKILL.
STOP_STEPS: tuple[tuple[signal.Signals, float], ...] = (
    (signal.SIGINT, 3.0), (signal.SIGTERM, 3.0), (signal.SIGKILL, 2.0),
)
# Depois que o processo principal sai, quanto o leitor espera o resto da
# saída. Se um neto segurar o pipe além disso, o grupo é encerrado.
DRAIN_AFTER_EXIT_S = 3.0
# O vídeo tem este tempo para fechar o MP4 depois do SIGINT.
VIDEO_CLOSE_S = 15.0

_ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
_SUMMARY_HEAD = re.compile(r"^\s*(\d+)\s+(feature|scenario|step)s?\s+passed\b", re.IGNORECASE)
_SUMMARY_PART = re.compile(r"(\d+)\s+([a-z]+)", re.IGNORECASE)
_COUNT_KEYS = ("passed", "failed", "skipped", "undefined", "errors", "untested")
# Palavras do resumo que contam como erro (behave 1.3 escreve `error`; outras
# versões, `errored`). Qualquer outra palavra desconhecida: `indeterminate`.
_ERROR_WORDS = {"error": "errors", "errors": "errors", "errored": "errors"}
# Linhas em que o behave avisa que falhou fora de um step: o resumo ainda diz
# "passed", mas o behave sai com falha (CR-01, D-O4).
_HARD_ERROR = re.compile(r"^\s*(HOOK-ERROR in |CLEANUP-ERROR in )")
_ABORTED = re.compile(r"^\s*ABORTED:")
_ERROR_HINT = re.compile(r"(Error|Exception|Traceback|Erro|falh|failed)", re.IGNORECASE)


def runs_dir() -> Path:
    """Raiz das pastas de execução. `MOBAILE_RUNS_DIR` troca (testes, fixtures)."""
    override = os.environ.get(RUNS_DIR_ENV)
    if override:
        return Path(override).expanduser()
    return Path.home() / "Documents" / "Mo baile" / "Execuções"


def new_run_folder(base: Path, project_name: str, now: float) -> Path:
    """`<base>/<projeto>/<AAAAMMDD-HHMMSS>/`, criada vazia; nunca reaproveita uma pasta."""
    pasta_projeto = base / safe_file_stem(project_name, fallback="projeto")
    pasta_projeto.mkdir(parents=True, exist_ok=True, mode=0o700)
    carimbo = time.strftime("%Y%m%d-%H%M%S", time.localtime(now))
    for n in range(1, 1000):
        pasta = pasta_projeto / (carimbo if n == 1 else f"{carimbo}-{n}")
        try:
            pasta.mkdir(mode=0o700)
            return pasta
        except FileExistsError:
            continue
    raise EngineError(f"Pastas de execução demais em {pasta_projeto} no mesmo segundo.")


def mask_line(line: str, masks: list[str]) -> str:
    for segredo in masks:
        if segredo:
            line = line.replace(segredo, MASK)
    return line


# ------------------------------------------------------------------ resumo


class BehaveSummary:
    """Soma as linhas de resumo do behave e decide o resultado.

    Lê a linha crua, antes da máscara: um segredo que fosse só dígitos
    apagaria o número de falhas da linha de resumo.
    """

    def __init__(self) -> None:
        self._counts: dict[str, dict[str, int]] = {
            tipo: dict.fromkeys(_COUNT_KEYS, 0) for tipo in ("features", "scenarios", "steps")
        }
        # Uma chamada do behave imprime uma linha de cada tipo: o número de
        # chamadas é o maior número de linhas de um mesmo tipo.
        self._lines: dict[str, int] = dict.fromkeys(self._counts, 0)
        self.hard_errors: list[str] = []
        self.aborted = False
        self.unknown_words: list[str] = []

    @property
    def summaries(self) -> int:
        return max(self._lines.values())

    def feed(self, line: str) -> bool:
        """Devolve se a linha mudou o resultado (resumo, HOOK-ERROR, ABORTED)."""
        if _HARD_ERROR.match(line):
            self.hard_errors.append(line.strip())
            return True
        if _ABORTED.match(line):
            self.aborted = True
            return True
        cabeca = _SUMMARY_HEAD.match(line)
        if not cabeca:
            return False
        tipo = cabeca.group(2).lower() + "s"
        self._lines[tipo] += 1
        # "2 scenarios passed, 0 failed, 1 error, 0 skipped": o número de
        # passados vem antes do tipo; os outros, antes do próprio nome.
        self._counts[tipo]["passed"] += int(cabeca.group(1))
        for numero, palavra in _SUMMARY_PART.findall(line[cabeca.end():]):
            chave = palavra.lower()
            chave = _ERROR_WORDS.get(chave, chave)
            if chave in self._counts[tipo]:
                self._counts[tipo][chave] += int(numero)
            elif chave not in self.unknown_words:
                self.unknown_words.append(chave)
        return True

    @property
    def found(self) -> bool:
        return self.summaries > 0

    def counts(self) -> dict[str, Any] | None:
        if not self.found:
            return None
        return {**{tipo: dict(valores) for tipo, valores in self._counts.items()}, "summaries": self.summaries}

    def status(self) -> str:
        """`failed` com falha, erro, step indefinido ou HOOK-ERROR/CLEANUP-ERROR; `passed` só
        com cenário passado e nada estranho; o resto (palavra desconhecida no resumo,
        ABORTED, nenhum cenário) é `indeterminate`."""
        ruins = ("failed", "errors", "undefined")
        if self.hard_errors or any(self._counts[t][c] for t in self._counts for c in ruins):
            return FAILED
        if not self.found or self.unknown_words or self.aborted:
            return INDETERMINATE
        if self._counts["scenarios"]["passed"] > 0:
            return PASSED
        return INDETERMINATE


# ------------------------------------------------------------------ vídeo


class NoVideo:
    mode = None

    started_at = None

    def __init__(self, warning: str | None) -> None:
        self.warning = warning

    def start(self) -> None:
        return None

    def stop(self) -> Path | None:
        return None


class ScrcpyVideo:
    """Vídeo da execução pelo scrcpy. O processo é do adapter (`ScrcpyRecording`)."""

    mode = "scrcpy"

    def __init__(self, scrcpy_path: str, serial: str, target: Path) -> None:
        self.target = target
        self._gravacao = ScrcpyRecording(scrcpy_path, serial, target)

    @property
    def warning(self) -> str | None:
        return self._gravacao.warning

    @property
    def started_at(self) -> float | None:
        return self._gravacao.started_at

    def command(self) -> list[str]:
        return self._gravacao.command()

    def start(self) -> None:
        self._gravacao.start()

    def stop(self) -> Path | None:
        return self._gravacao.stop()


class RecorderVideo:
    """`ScreenRecorder` do motor (screenrecord ou simctl) numa pasta da execução."""

    def __init__(self, recorder, platform: Platform, device_id: str, target: Path, mode: str,
                 warning: str | None = None) -> None:
        self.recorder = recorder
        self.platform = platform
        self.device_id = device_id
        self.target = target
        self.mode = mode
        self.warning = warning
        self.started_at: float | None = None

    def start(self) -> None:
        self.recorder.start(self.platform, self.device_id)
        # O `ScreenRecorder` só volta depois de conferir que o processo subiu.
        self.started_at = time.time()

    def stop(self) -> Path | None:
        try:
            resultado = self.recorder.stop()
        except EngineError as exc:
            self.warning = f"O vídeo não foi gravado: {exc.message}"
            return None
        origem = Path(resultado.get("path") or "")
        if origem.is_file():
            origem.replace(self.target)
            return self.target
        return None


def make_video(*, platform: Platform | None, device_id: str | None, folder: Path, scrcpy_path: str | None,
               recorder_factory: Callable[[Path], Any], booted_simulators: Callable[[], list[tuple[str, str]]]):
    """Escolhe o gravador do alvo. Nunca levanta: sem como gravar vira `NoVideo` com aviso."""
    alvo = folder / VIDEO_FILE
    if not device_id:
        return NoVideo("Sem aparelho alvo: a execução segue sem vídeo.")
    if platform is Platform.IOS:
        if device_id in dict(booted_simulators()):
            return RecorderVideo(recorder_factory(folder), Platform.IOS, device_id, alvo, "simctl")
        return NoVideo("iPhone físico: esta versão não grava o vídeo da tela dele.")
    if scrcpy_path:
        return ScrcpyVideo(scrcpy_path, device_id, alvo)
    return RecorderVideo(
        recorder_factory(folder), Platform.ANDROID, device_id, alvo, "screenrecord",
        warning="scrcpy não encontrado: gravando com adb screenrecord, que para sozinho em 180 s.",
    )


# ------------------------------------------------------------------ execução


class ProjectRun:
    """Uma execução do `main`. `start()` sobe o processo; o resto roda em threads."""

    def __init__(self, *, run_id: str, project: dict[str, Any], command: list[str], cwd: Path,
                 env: dict[str, str], folder: Path, masks: list[str], video,
                 on_line: Callable[[str, str], None],
                 on_finished: Callable[[dict[str, Any]], None],
                 expected_runs: int = 0, device_id: str | None = None, platform: str | None = None,
                 config_name: str | None = None, clock: Callable[[], float] = time.time) -> None:
        self.run_id = run_id
        self.project = project
        self.command = command
        self.cwd = cwd
        self._env = env
        self.folder = folder
        self._masks = sorted({m for m in masks if m}, key=len, reverse=True)
        self.video = video
        self._on_line = on_line
        self._on_finished = on_finished
        self.expected_runs = expected_runs
        self.device_id = device_id
        self.platform = platform
        self.config_name = config_name
        self._clock = clock
        self.started_at = 0.0
        self.lines = 0
        self.summary = BehaveSummary()
        self._last_error: str | None = None
        self._last_line: str | None = None
        self._process: subprocess.Popen | None = None
        self._console = None
        self._console_bytes = 0
        self._console_full = False
        self._cancelled = threading.Event()
        self._finished = threading.Event()
        self._stop_lock = threading.Lock()
        # O `_emit` roda na leitora e no `stop()`: uma linha por vez no arquivo.
        self._emit_lock = threading.Lock()
        self._console_warned = False
        # `run.stop` com o processo principal ainda vivo: só isso vira
        # `cancelled` (CR-07). Depois do `_finish` começar, parar não vale.
        self._cancel_live = False
        self._finishing = False
        self._thread: threading.Thread | None = None
        self._starting = False
        self.result: dict[str, Any] | None = None

    @property
    def project_name(self) -> str:
        return str(self.project.get("name") or "")

    @property
    def active(self) -> bool:
        """Do começo do `start()` (o vídeo sobe antes do processo) até o fim."""
        return (self._starting or self._process is not None) and not self._finished.is_set()

    @property
    def cancelled(self) -> bool:
        return self._cancel_live

    def wait(self, timeout: float | None = None) -> bool:
        return self._finished.wait(timeout)

    # ---------------------------------------------------------------- início

    def start(self) -> None:
        fd = os.open(self.folder / CONSOLE_FILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        self._console = os.fdopen(fd, "w", encoding="utf-8", errors="replace")
        self.started_at = self._clock()
        self._starting = True
        try:
            self._start()
        finally:
            self._starting = False

    def _start(self) -> None:
        if self.video is not None:
            try:
                self.video.start()
            except EngineError as exc:
                aviso = f"O vídeo não começou: {exc.message}"
                logger.warning(aviso)
                self.video = NoVideo(aviso)
        try:
            self._process = subprocess.Popen(
                self.command, cwd=str(self.cwd), env=self._env, stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
            )
        except OSError as exc:
            if self.video is not None:
                self.video.stop()
            self._console.close()
            raise EngineError(f"Não consegui iniciar o projeto: {exc.strerror or exc}") from exc
        if self._cancelled.is_set():
            # `run.stop` chegou enquanto o vídeo subia: o processo nem segue.
            self._cancel_live = True
            self._kill_group()
        self._emit(f"[Mo baile] Rodando {self.command[0]} {Path(self.command[-1]).name} em {self.cwd}")
        if self.video is not None and getattr(self.video, "warning", None):
            self._emit(f"[Mo baile] {self.video.warning}")
        self._thread = threading.Thread(target=self._run, daemon=True, name=f"mobaile-run-{self.run_id}")
        self._thread.start()

    # ---------------------------------------------------------------- saída

    def _emit(self, line: str) -> None:
        crua = _ANSI.sub("", line).rstrip("\r\n").replace("\r", "")
        # O resultado sai da linha crua; tudo que sai do motor, da mascarada.
        decisiva = self.summary.feed(crua)
        line = mask_line(crua, self._masks)
        with self._emit_lock:
            self.lines += 1
            self._last_line = line if line.strip() else self._last_line
            if line.strip() and not line.startswith("[Mo baile]") and (decisiva or _ERROR_HINT.search(line)):
                self._last_error = line.strip()
            self._write_console(line)
        mostrada = line if len(line) <= MAX_LINE_CHARS else line[:MAX_LINE_CHARS] + "…"
        try:
            self._on_line(self.run_id, mostrada)
        except Exception:
            logger.exception("Falha ao repassar linha da execução.")

    def _write_console(self, line: str) -> None:
        """Grava no console.log. Disco cheio ou erro de E/S não param a execução (CR-04)."""
        if self._console is None or self._console_full:
            return
        dados = line + "\n"
        self._console_bytes += len(dados.encode("utf-8", errors="replace"))
        if self._console_bytes > MAX_CONSOLE_BYTES:
            self._console_full = True
            dados = "[Mo baile] console.log passou de 50 MB; o resto só foi para a tela.\n"
        try:
            self._console.write(dados)
            self._console.flush()
        except (OSError, ValueError) as exc:
            self._console_full = True
            if not self._console_warned:
                self._console_warned = True
                aviso = f"[Mo baile] Não consegui gravar o console.log ({exc}); o console segue só na tela."
                logger.warning(aviso)
                try:
                    self._on_line(self.run_id, aviso)
                except Exception:
                    logger.exception("Falha ao repassar linha da execução.")

    def _read(self) -> None:
        processo = self._process
        assert processo is not None and processo.stdout is not None
        # Com buffer (CR-10): `readline` volta assim que chega o `\n`, sem ler
        # byte a byte. Uma linha que falhe não para a drenagem do pipe.
        for bruta in iter(processo.stdout.readline, b""):
            try:
                self._emit(bruta.decode("utf-8", errors="replace"))
            except Exception:
                logger.exception("Falha ao tratar uma linha da execução.")

    def _run(self) -> None:
        processo = self._process
        assert processo is not None
        codigo: int | None = None
        try:
            leitor = threading.Thread(target=self._read, daemon=True, name=f"mobaile-run-leitor-{self.run_id}")
            leitor.start()
            codigo = processo.wait()
            leitor.join(DRAIN_AFTER_EXIT_S)
            if leitor.is_alive():
                # Um neto herdou o stdout e continua de pé: o pipe nunca fecharia.
                self._emit("[Mo baile] O processo principal terminou, mas processos filhos seguravam a saída; "
                           "encerrando o grupo.")
                self._kill_group()
                leitor.join(DRAIN_AFTER_EXIT_S)
            if processo.stdout is not None:
                processo.stdout.close()
        except Exception:
            logger.exception("Falha na execução do projeto.")
        finally:
            # O fim sempre sai: sem ele, a trava do aparelho ficava presa.
            self._finish(codigo if codigo is not None else processo.poll())

    # ---------------------------------------------------------------- parada

    def _group_alive(self) -> bool:
        if self._process is None:
            return False
        self._process.poll()
        try:
            os.killpg(self._process.pid, 0)
        except ProcessLookupError:
            return False
        except PermissionError:
            return True
        return True

    def _kill_group(self) -> bool:
        """SIGINT, SIGTERM e SIGKILL no grupo, com prazos curtos. Devolve se o grupo acabou."""
        processo = self._process
        if processo is None:
            return True
        for sinal, prazo in STOP_STEPS:
            if not self._group_alive():
                return True
            try:
                os.killpg(processo.pid, sinal)
            except ProcessLookupError:
                return True
            except PermissionError as exc:
                logger.warning("Sem permissão para sinalizar o grupo %s: %s", processo.pid, exc)
                return False
            limite = time.monotonic() + prazo
            while time.monotonic() < limite:
                if not self._group_alive():
                    return True
                time.sleep(0.05)
        return not self._group_alive()

    def stop(self) -> bool:
        """Para a execução e os netos. Idempotente.

        Devolve `True` só quando o processo principal ainda rodava: aí o
        resultado é `cancelled`. Depois que ele saiu (drenagem, vídeo
        fechando), o grupo ainda é encerrado, mas o resultado continua o do
        resumo (CR-07).
        """
        with self._stop_lock:
            if not self.active or self._finishing:
                return False
            self._cancelled.set()
            processo = self._process
            vivo = processo is None or processo.poll() is None
            if vivo:
                self._cancel_live = True
        # Primeiro mata, depois escreve: com o disco cheio, escrever antes
        # deixava o processo de pé (CR-04).
        self._kill_group()
        try:
            self._emit("[Mo baile] Parada pedida: SIGINT no grupo, depois SIGTERM e SIGKILL.")
        except Exception:
            logger.exception("Falha ao registrar a parada.")
        return vivo

    # ---------------------------------------------------------------- fim

    def _message(self, status: str, codigo: int | None) -> str:
        cenarios = (self.summary.counts() or {}).get("scenarios", {})
        if status == CANCELLED:
            return "Execução parada pelo dono."
        if status == PASSED:
            return f"Passou: {cenarios.get('passed', 0)} cenários."
        if status == FAILED:
            if self.summary.hard_errors:
                return f"Falhou fora dos cenários: {mask_line(self.summary.hard_errors[0], self._masks)}"
            total = sum(cenarios.get(k, 0) for k in ("passed", "failed", "skipped", "errors", "untested"))
            return f"Falhou: {cenarios.get('failed', 0) + cenarios.get('errors', 0)} de {total} cenários."
        if self.summary.unknown_words:
            return ("O resumo do behave tem contagem que o Mo baile não conhece ("
                    + ", ".join(self.summary.unknown_words) + "); confira o console.")
        if self.summary.aborted:
            return "O behave abortou a execução (ABORTED); confira o console."
        if not self.summary.found:
            detalhe = self._last_error or self._last_line
            base = f"O behave não imprimiu resumo (código de saída {codigo})."
            return f"{base} Última linha de erro: {detalhe}" if detalhe else base
        if self.expected_runs and self.summary.summaries < self.expected_runs:
            return (f"O main chama o behave {self.expected_runs} vezes e só {self.summary.summaries} "
                    "resumo(s) apareceram: alguma suíte não rodou.")
        return "O behave não rodou nenhum cenário."

    def _finish(self, codigo: int | None) -> None:
        with self._stop_lock:
            self._finishing = True
        status = CANCELLED if self.cancelled else self.summary.status()
        if (status == PASSED and self.expected_runs
                and self.summary.summaries < self.expected_runs):
            status = INDETERMINATE
        video_path, aviso_video = None, None
        if self.video is not None:
            try:
                video_path = self.video.stop()
            except Exception:
                logger.exception("Falha ao encerrar o vídeo da execução.")
            aviso_video = getattr(self.video, "warning", None)
        terminou = self._clock()
        self.result = {
            "run_id": self.run_id,
            "status": status,
            "counts": self.summary.counts(),
            "exit_code": codigo,
            "folder": str(self.folder),
            "video": str(video_path) if video_path else None,
            "video_warning": aviso_video,
            "message": mask_line(self._message(status, codigo), self._masks),
            "duration_s": round(max(0.0, terminou - self.started_at), 1),
        }
        resumo = {
            **self.result,
            "project": {"id": self.project.get("id"), "name": self.project_name, "root": self.project.get("root")},
            "command": {"interpreter": self.command[0], "entry": self.command[-1], "working_dir": str(self.cwd)},
            "config": self.config_name,
            "device_id": self.device_id,
            "platform": self.platform,
            "started_at": self.started_at,
            # Epoch em que o vídeo começou de fato; a B4 alinha os steps por ele.
            "video_started_at": getattr(self.video, "started_at", None) if video_path else None,
            "finished_at": terminou,
            "lines": self.lines,
        }
        try:
            write_file_atomic(self.folder / SUMMARY_FILE,
                              (json.dumps(resumo, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        except OSError as exc:
            logger.warning("Não consegui gravar o resumo da execução: %s", exc)
        if self._console is not None:
            self._console.close()
            self._console = None
        self._finished.set()
        try:
            self._on_finished(self.result)
        except Exception:
            logger.exception("Falha ao avisar o fim da execução.")

    # ---------------------------------------------------------------- estado

    def snapshot(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "project_id": self.project.get("id"),
            "project_name": self.project_name,
            "device_id": self.device_id,
            "platform": self.platform,
            "folder": str(self.folder),
            "started_at": self.started_at,
            "elapsed_s": round(max(0.0, self._clock() - self.started_at), 1),
            "lines": self.lines,
            "video": getattr(self.video, "mode", None),
            "stopping": self.cancelled,
        }
