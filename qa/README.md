# Harness de QA

Roda os quatro fluxos principais do Mo baile sem precisar de aparelho, de Xcode
nem de Android SDK.

```bash
python3 qa/run_all.py
```

## Como funciona

`fakebin/` contém um `adb`, um `xcrun`, um `emulator` e um `open` falsos que
respondem como os de verdade nos caminhos que a aplicação usa: listagem de
dispositivos, `screencap` devolvendo PNG real, `uiautomator dump` devolvendo XML
de hierarquia, `wm size`, `getevent -p`, `reverse` e `settings put global
http_proxy`. Cada chamada é registrada em `calls.log`, então dá para afirmar não
só que a aplicação respondeu, mas **o que exatamente ela mandou para o
aparelho**.

`fake_wda.py` é um WebDriverAgent mínimo, com `/status`, `/session`, `/source` e
`/session/<id>/wda/tap`.

`engine_client.py` sobe o motor de verdade como subprocesso
(`python -m mobaile.rpc`) e fala o mesmo JSON-RPC sobre stdio que o front
SwiftUI fala. É isso que dá valor ao harness: não é mock do motor, é o motor.

O fluxo 4 sobe um servidor HTTPS real com certificado próprio e atravessa o
proxy com CONNECT e handshake TLS de verdade.

## Cobertura

| Fluxo | Verificações |
|---|---|
| 1 · sem dispositivo | 19 |
| 2 · só iOS | 31 |
| 3 · só Android | 35 |
| 4 · HTTPS | 34 |

## Requisitos

Python 3.10+, `Pillow`, `requests` e `openssl` no PATH (para gerar o certificado
do fluxo 4). Nenhum aparelho, nenhum simulador.
