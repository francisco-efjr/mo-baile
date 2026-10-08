"""Tabela declarativa do contrato JSON-RPC.

Uma fonte de verdade so para tres consumidores que antes podiam divergir:

- o despacho do servidor, que usa `lane` para decidir em qual fila serial cada
  metodo roda;
- o front, que recebe a tabela inteira em `engine.hello` e usa `timeout_s` em
  vez de manter uma lista propria de tempos;
- os testes de deriva, que conferem esta tabela contra `EngineServer.methods`,
  contra as notificacoes emitidas no codigo e contra `docs/PROTOCOLO_RPC.md`.

Nada aqui faz I/O nem importa adapter: o modulo e barato de carregar e pode ser
lido por ferramenta externa sem subir o motor.
"""

from __future__ import annotations

from typing import Any

# Sobe quando uma mudanca obriga o front a mudar junto. A 1 era o contrato sem
# aperto de mao; a 2 trouxe `engine.hello`, filas, cancelamento e progresso.
PROTOCOL_VERSION = 2

# O que o motor sabe fazer alem de responder metodo. O front liga recurso
# opcional pelo que esta aqui, e nao pela versao do motor.
CAPABILITIES: tuple[str, ...] = ("cancel", "progress", "lanes")

# `inline` roda na thread que le o stdin e por isso so aceita metodo que
# responde em milissegundos. As demais sao filas seriais, cada uma com a sua
# thread: uma chamada lenta numa fila nao atrasa as outras. A divisao segue o
# pior caso de cada metodo, para consulta curta nunca esperar atras de longa:
#
# - fast: interacao e estado; nada ali passa de uns 2 s.
# - capture: leitura de tela e arvore, e a escuta passiva, que pre-aquece a
#   arvore e nao pode ter o `stop` ultrapassando o `start`.
# - services: servicos de fundo que o motor liga e desliga (proxy, tagueamento,
#   fluxo, gravacao de tela).
# - query: consultas ao ambiente, que levam segundos mas nunca minutos.
# - environment: preparo de ambiente, que leva minutos.
LANE_INLINE = "inline"
LANE_FAST = "fast"
LANE_CAPTURE = "capture"
LANE_SERVICES = "services"
LANE_QUERY = "query"
LANE_ENVIRONMENT = "environment"
WORKER_LANES: tuple[str, ...] = (LANE_FAST, LANE_CAPTURE, LANE_SERVICES, LANE_QUERY, LANE_ENVIRONMENT)
LANES: tuple[str, ...] = (LANE_INLINE, *WORKER_LANES)

DEFAULT_TIMEOUT_S = 15

# Notificacoes que o cliente manda para o motor. Nao entram em `METHODS` porque
# nao tem resposta, nem fila, nem prazo: sao tratadas na propria leitura.
CANCEL_REQUEST = "$/cancelRequest"
CLIENT_NOTIFICATIONS: tuple[str, ...] = (CANCEL_REQUEST,)

PROGRESS = "$/progress"


def _spec(lane: str = LANE_FAST, timeout_s: float = DEFAULT_TIMEOUT_S, progress: bool = False) -> dict[str, Any]:
    return {"lane": lane, "timeout_s": timeout_s, "progress": progress}


# `timeout_s` e quanto o front espera antes de mandar `$/cancelRequest` e
# desistir, contando o tempo de fila. Os valores grandes nao sao folga: compilar
# o WDA na primeira vez leva minutos, e um AVD frio leva mais de um minuto.
#
# Pedido que estoura o prazo ainda na fila sai dela sem efeito, o que e o certo
# para uma consulta. Para um `stop` nao e: perder o pedido deixa a escuta, o
# proxy ou a gravacao ligados. Por isso cada `stop` espera o proprio tempo mais o
# pior caso de quem pode estar na frente dele na fila.
METHODS: dict[str, dict[str, Any]] = {
    # Sessao e diagnostico
    "engine.hello": _spec(LANE_INLINE, 5),
    "engine.info": _spec(),
    "engine.shutdown": _spec(LANE_INLINE, 5),
    "session.select_device": _spec(),
    "devices.list": _spec(LANE_QUERY),
    "devices.watch_start": _spec(),
    "devices.watch_stop": _spec(),
    # Ambiente e inicializacao
    "diagnostics.check": _spec(LANE_QUERY, 30, progress=True),
    "simulators.list": _spec(LANE_QUERY),
    "simulators.boot": _spec(LANE_ENVIRONMENT, 180, progress=True),
    "simulators.shutdown": _spec(LANE_ENVIRONMENT),
    "emulators.list": _spec(LANE_QUERY),
    "emulators.boot": _spec(LANE_ENVIRONMENT, 120, progress=True),
    "wda.start": _spec(LANE_ENVIRONMENT, 600, progress=True),
    "wda.status": _spec(LANE_QUERY),
    # Gravacao de tela. Fica em `services`, e nao em `environment`: um
    # `recording.stop` atras de um `wda.start` de minutos estouraria o prazo e
    # deixaria o `screenrecord` gravando.
    "recording.start": _spec(LANE_SERVICES),
    "recording.stop": _spec(LANE_SERVICES, 60),
    "recording.status": _spec(),
    # Tela e hierarquia. `hierarchy.dump` so emite progresso quando cai no
    # caminho do Appium, que e o que pode levar dezenas de segundos.
    "screen.capture": _spec(LANE_CAPTURE, 20),
    "screen.size": _spec(LANE_CAPTURE, 20),
    "hierarchy.dump": _spec(LANE_CAPTURE, 60, progress=True),
    "hierarchy.element_at": _spec(),
    # Interacao
    "input.tap": _spec(),
    "input.text": _spec(),
    # Espelho
    "stream.start": _spec(),
    "stream.stop": _spec(),
    "stream.stats": _spec(),
    "scrcpy.start": _spec(),
    "scrcpy.stop": _spec(),
    "scrcpy.status": _spec(),
    # Rede e tagueamento
    "proxy.start": _spec(LANE_SERVICES, 30),
    "proxy.stop": _spec(LANE_SERVICES, 60),
    "proxy.events": _spec(LANE_SERVICES),
    "proxy.clear": _spec(LANE_SERVICES),
    # Lista os iPhones (ate 15 s) e espera o log comecar (ate 20 s).
    "netlog.start": _spec(LANE_SERVICES, 45),
    "netlog.stop": _spec(LANE_SERVICES, 60),
    "analytics.start": _spec(LANE_SERVICES, 20),
    "analytics.stop": _spec(LANE_SERVICES, 60),
    "analytics.events": _spec(LANE_SERVICES),
    "analytics.clear": _spec(LANE_SERVICES),
    # Lista iPhones por cabo; abre lockdown em cada um, entao e consulta.
    "analytics.ios_devices": _spec(LANE_QUERY),
    # Geracao de codigo e execucao
    "codegen.record": _spec(),
    "codegen.steps": _spec(),
    "codegen.reset": _spec(),
    "codegen.save": _spec(),
    "flow.run": _spec(LANE_SERVICES, 30),
    "flow.stop": _spec(LANE_SERVICES, 60),
    "flow.status": _spec(LANE_SERVICES),
    # Escuta passiva. `start` e `stop` na mesma fila, para o `stop` nunca passar
    # na frente de um `start` ainda em andamento. `status` so le uma referencia
    # e fica na rapida: nao ha ordem a preservar, e esperar um dump de 60 s para
    # responder "ligada ou nao" nao faz sentido.
    "passive.start": _spec(LANE_CAPTURE, 60),
    "passive.stop": _spec(LANE_CAPTURE, 75),
    "passive.status": _spec(),
}

# Tudo que o motor empurra sem `id`. O teste de deriva confere esta lista contra
# cada chamada a `notify` do codigo, para o front nunca receber metodo que nao
# conhece.
NOTIFICATIONS: tuple[str, ...] = (
    "stream.frame",
    "stream.settled",
    "proxy.event",
    "analytics.event",
    "device.changed",
    "passive.step",
    "passive.skipped",
    "passive.text",
    "flow.log",
    "flow.finished",
    PROGRESS,
)


def lane_of(method: str) -> str:
    """Fila de um metodo. O que nao esta na tabela vai para a rapida."""
    return METHODS.get(method, {}).get("lane", LANE_FAST)


def hello_payload(engine_version: str) -> dict[str, Any]:
    """Resultado de `engine.hello`. Copia a tabela para ninguem altera-la por fora."""
    return {
        "protocol_version": PROTOCOL_VERSION,
        "engine_version": engine_version,
        "capabilities": list(CAPABILITIES),
        "methods": {name: dict(spec) for name, spec in METHODS.items()},
        "notifications": list(NOTIFICATIONS),
    }
