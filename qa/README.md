# Harness de QA

Roda os cinco fluxos principais do Mo baile sem precisar de aparelho, de Xcode
nem de Android SDK.

```bash
make qa
make test-qa
```

`make qa` usa o mesmo ambiente virtual das suítes Python. Cada fluxo precisa
terminar com código zero e um resumo com verificações executadas e nenhuma
falha; resumo ausente, zero verificações e timeout reprovam o gate. Em falha,
stdout e stderr são exibidos para diagnóstico. O limite por fluxo é 120 s;
um timeout encerra também o motor filho e o próximo fluxo ainda é executado.

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

O cenário iOS usa uma porta efêmera para o WDA falso, e o cenário Android usa
uma porta efêmera para o proxy. O cliente força o ADB falso e endpoints locais,
substituindo a configuração herdada do shell. Configuração específica de um
cenário é passada explicitamente em `extra_env`.

`engine_client.py` sobe o motor de verdade como subprocesso
(`python -m mobaile.rpc`) e fala o mesmo JSON-RPC sobre stdio que o front
SwiftUI fala. É isso que dá valor ao harness: não é mock do motor, é o motor.

O fluxo 4 sobe um servidor HTTPS real com certificado próprio e atravessa o
proxy com CONNECT e handshake TLS de verdade.

O fluxo 5 é a aba Relatório: abre uma spec sintética, audita um log misto
Android + iOS, exporta board, HTML, Markdown e TSV e confere o conteúdo deles,
inclusive que um nome de projeto com `<script>` sai escapado no HTML. O motor
roda com `HOME` temporário, para nenhum caminho padrão escrever na pasta do
usuário.

## Cobertura

| Fluxo | Verificações |
|---|---|
| 1 · sem dispositivo | 19 |
| 2 · só iOS | 31 |
| 3 · só Android | 35 |
| 4 · HTTPS | 34 |
| 5 · relatório | 26 |

## Requisitos

Python 3.10+, `Pillow`, `requests` e `openssl` no PATH (para gerar o certificado
do fluxo 4). Nenhum aparelho, nenhum simulador.

O CI executa as regressões do gate e os quatro fluxos na matriz Python do
motor, incluindo o lint de `qa/`.
