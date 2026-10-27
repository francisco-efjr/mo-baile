# Instalação numa máquina zerada

O que uma pessoa precisa para usar o Mo baile num Mac ou num PC com Windows
sem nada instalado, separado por recurso, e como o app ajuda a chegar lá.
Levantamento de 23/10/2026, feito no código da 3.9.0 (referências `arquivo:linha`
da época).

Resumo:

- **Mac:** o app nativo, um Python 3.10+ com Pillow e requests, e as
  ferramentas da plataforma que você testa: `adb` para Android; Xcode e
  Appium com o driver XCUITest para iOS. O resto é opcional.
- **Windows:** não há app nativo (é SwiftUI). O caminho é a interface Tkinter
  (`apps/tk-legacy`), só com Android. O iOS precisa de um Mac. Ainda há
  defeitos conhecidos no Windows, listados na seção Windows.
- **Sem certificado.** O proxy não abre HTTPS (não há MITM, ADR 0004). Não há
  CA para gerar nem para instalar no aparelho.
- **Offline depois de instalado.** Só a instalação usa a internet. Motor,
  relatório (Motion embutido) e OCR (Vision local) rodam sem rede.

A tela **Início** do app mostra tudo isto medido na máquina, com "Instalar no
Terminal…" para cada item que um script resolve. O mesmo diagnóstico sai no
terminal com `python3 -m mobaile.services.setup`, com `PYTHONPATH=engine/src`
quando roda do código.

## O que cada recurso precisa (Mac)

**Obr.** = obrigatório; **Opc.** = opcional; **—** = não usa.

| Recurso | Python + Pillow + requests | `adb` | Xcode (simctl) | Appium + XCUITest | Outros |
|---|---|---|---|---|---|
| Abrir o app e o motor | **Obr.** | — | — | — | macOS 14+ |
| Espelho Android | **Obr.** | **Obr.** | — | — | scrcpy (**Opc.**, janela a 60 quadros) |
| Hierarquia, toque e Page Objects Android | **Obr.** | **Obr.** | — | **Opc.**: driver UiAutomator2, reserva quando o `uiautomator dump` vem vazio (Motorola, Android 14), e ele pede Java e `ANDROID_HOME` | — |
| Espelho iOS (simulador) | **Obr.** | — | **Obr.** | — | — |
| Hierarquia, toque e Page Objects iOS | **Obr.** | — | **Obr.** | **Obr.** (sobe o WebDriverAgent; a primeira compilação leva minutos) | Node.js para o Appium |
| Rede HTTP Android | **Obr.** | **Obr.** (`adb reverse` e proxy global) | — | — | HTTPS: app em debug com o `HttpLoggingInterceptor` do OkHttp |
| Rede HTTP iOS | **Obr.** | — | — | — | Só iPhone físico por cabo, app em debug com `CFNETWORK_DIAGNOSTICS=3`, e `pymobiledevice3` (**Opc.**). O proxy não configura iOS |
| Analytics Android | **Obr.** | **Obr.** (logcat) | — | — | — |
| Analytics iOS simulador | **Obr.** | — | **Obr.** (`simctl spawn … log stream`) | — | O app precisa rodar com `-FIRDebugEnabled` |
| Analytics iPhone físico | **Obr.** | — | — | — | `pymobiledevice3` (**Opc.**), iPhone confiando no Mac |
| Escuta passiva de toques | **Obr.** | Android: **Obr.** (`getevent`) | iOS: **Obr.** | — | iOS: `pyobjc-framework-Quartz` (**Opc.**); só simulador |
| Gravação de tela | **Obr.** | Android: **Obr.** | iOS: **Obr.** | — | Grava em `~/Movies/Mo baile` |
| Relatório (auditar log exportado) | **Obr.** | — | — | — | Nada além do app |
| Relatório (importar cards de prints) | **Obr.** | — | — | — | Swift das Command Line Tools (`swiftc`), compila o OCR do Vision uma vez |

## Cada dependência

### Python e pacotes do motor

- **Versão:** 3.10 ou mais nova (`engine/pyproject.toml`). O `/usr/bin/python3`
  do macOS é 3.9 e não serve.
- **Pacotes obrigatórios:** Pillow (importado na subida do motor) e requests
  (importado só quando o Appium ou o WDA é usado).
- **Opcionais:**
  - `pyobjc-framework-Quartz` (extra `macos`), para a escuta passiva no iOS.
  - `pymobiledevice3` (extra `ios-device`), para iPhone físico. Roda num
    processo filho e é procurado com `find_spec`, sem carregar o pacote.
- **Como o app acha o Python** (`EngineLocator.swift`), nesta ordem:
  1. `MOBAILE_PYTHON`
  2. `.venv` do repositório (só rodando do código)
  3. **o Python do Mo baile** em `~/Library/Application Support/Mo baile/python`
     (novo na 3.10)
  4. `/opt/homebrew/bin/python3`
  5. `/usr/local/bin/python3`
  6. `/usr/bin/python3`

  Cada candidato passa por uma sonda de versão e de pacotes.
- **Armadilha do Homebrew:** o Python do Homebrew recusa `pip install` fora de
  um ambiente virtual (PEP 668). A mensagem antiga do app mandava
  `brew install python` e depois `pip install`, um caminho que falha. Por isso
  o alvo `python` do script cria um ambiente só do Mo baile, e a mensagem
  agora aponta para ele.
- **O app não leva Python dentro.** O bundle carrega o código do motor
  (`Contents/Resources/engine/src`), não o interpretador nem os pacotes.

### Android: adb, emulador, scrcpy

- **`adb`** é procurado assim (`adapters/adb.py`):
  1. `ADB_PATH`
  2. `PATH`
  3. `/opt/homebrew/bin/adb`
  4. `/usr/local/bin/adb`
  5. `~/Library/Android/sdk/platform-tools/adb`

  Não lê `ANDROID_HOME` nem `ANDROID_SDK_ROOT`. Sem `adb`, nada funciona no
  Android. Instale com `brew install --cask android-platform-tools`.
- **Emulador:** vem do `PATH` ou de `~/Library/Android/sdk/emulator/emulator`,
  e é instalado com o Android Studio. É opcional para quem usa aparelho
  físico.
- **scrcpy:** vem do `PATH`, de `/opt/homebrew/bin` ou de `/usr/local/bin`.
  Instale com `brew install scrcpy`. Ele só abre o espelho em janela própria.
- **No aparelho:** ative as Opções do desenvolvedor e a Depuração USB, e
  aceite o aviso de chave RSA ao plugar o cabo.

### iOS: Xcode, simuladores, Appium, WebDriverAgent

- **Xcode:** vem da App Store. As Command Line Tools sozinhas têm o `xcrun`,
  mas não o `simctl` nem o simulador. O `setup.check` confere o
  `simctl` em `DEVELOPER_DIR` ou em `/Applications/Xcode.app`.
- **Simuladores:** os runtimes de iOS são baixados pelo Xcode (Settings ›
  Components). Só simulador entra na sessão (espelho, toque, hierarquia). O
  iPhone físico serve só para Analytics e Rede, por cabo.
- **Appium:** precisa do Node.js, `npm install -g appium` e
  `appium driver install xcuitest`. A documentação antiga não citava o
  driver. O motor procura o `appium` no `PATH`, em `/opt/homebrew/bin`, em
  `/usr/local/bin`, em `~/.npm-global/bin` e no `nvm`. O driver mora em
  `~/.appium/node_modules/appium-xcuitest-driver` (ou em `APPIUM_HOME`).
  Quando o motor sobe o Appium, ele escuta só em `127.0.0.1`, na porta da
  `APPIUM_URL` (padrão 4723), e o log vai para
  `~/Library/Logs/Mo baile/appium.log` (pasta 0700, arquivo 0600). Com a
  `APPIUM_URL` apontando para outra máquina ou para a porta 0, o motor não
  sobe servidor: usa o que já estiver no ar.
- **O PATH do Finder:** o app aberto pelo Finder herda o `PATH` mínimo do
  launchd. O `appium` é um script `#!/usr/bin/env node`, então, se o `node`
  não estiver nesse `PATH`, o Appium existe mas não sobe. O `setup.check`
  marca esse caso com aviso. O conserto definitivo, acrescentar
  `/opt/homebrew/bin` e `/usr/local/bin` ao `PATH` do motor, está em
  [Pendências](#pendências-encontradas).

### Rede: não há certificado

O proxy (`adapters/proxy.py`) repassa o `CONNECT` sem abrir o TLS. Não há CA
para gerar nem para instalar.

- **Android:** o motor liga `adb reverse tcp:8082`, o proxy global e
  `captive_portal_mode 0`, e devolve os valores originais ao parar.
- **iOS:** o proxy não configura o aparelho.
- **HTTPS por dentro** vem só do app em debug (ADR 0004): o log do OkHttp no
  Android e o `CFNETWORK_DIAGNOSTICS` no iPhone por cabo.

Ainda dizem "MITM" em lugar errado:

- o tooltip de Rede (`HTTPInspectorView.swift`);
- a interface Tkinter;
- o `docs/SEGURANCA.md`.

### Permissões do macOS

- **Gatekeeper:** o app é assinado ad-hoc, sem notarização. Na primeira vez,
  use "clique direito › Abrir" ou `xattr -dr com.apple.quarantine`
  (README).
- **Rede local:** o `Info.plist` declara `NSLocalNetworkUsageDescription`
  para o proxy.
- **Pasta Documentos:** o pedido repetido vinha de um `.pth` que apontava
  para o repositório. Está sendo resolvido em outra frente (`python3 -S`,
  `mobaile/_site.py`).
- **Acessibilidade, Monitoramento de Entrada e Gravação de Tela:** o app não
  pede nenhuma hoje.
  - A escuta passiva no simulador lê o estado do botão do mouse e o dono da
    janela, o que não costuma pedir permissão.
  - O caminho do scrcpy lê o nome da janela, que no macOS 10.15+ vem vazio
    sem Gravação de Tela. Não foi verificado.
- **"Confiar neste computador"** no iPhone, para o `pymobiledevice3`.

## Windows

O que isso implica:

- **Não há app nativo.** O front é SwiftUI e só compila no macOS. Portar
  seria escrever outro front. O motor é Python e quase todo portátil.
- **iOS não existe no Windows.** Simulador, `simctl`, `xcrun` e o
  WebDriverAgent só rodam num Mac. No Windows sobra Android.
- **A interface Tkinter está congelada** (ADR 0005): só recebe correção de
  defeito grave. Ela é, ainda assim, o único front que roda fora do Mac.

O caminho mais simples, nesta ordem:

1. Python 3.12 pelo `winget` (o do python.org traz o Tkinter), Android
   Platform Tools pelo `winget` (`Google.PlatformTools`), scrcpy opcional
   (`Genymobile.scrcpy`).
2. Um Python só do Mo baile em `%LOCALAPPDATA%\MoBaile\python`, com o motor e
   a interface instalados do código-fonte, e um `Mo baile.cmd` para abrir.
3. O driver USB do fabricante, ou o Google USB Driver, para o `adb` ver o
   aparelho por cabo. Emulador dispensa.

`tools/setup/instalar-windows.ps1` faz os passos 1 e 2 e lembra do 3. **Ele não
foi testado num Windows de verdade**: esta máquina é um Mac sem PowerShell.

Defeitos conhecidos que impedem chamar o Windows de suportado. Nenhum foi
corrigido aqui, por ser outra frente:

| Onde | O que quebra |
|---|---|
| `apps/tk-legacy/mobaile_tk/main_window.py`, atalhos `<Command-f>` | Provável `TclError` ao montar a janela fora do macOS. Não verificado |
| `engine/src/mobaile/security/paths.py`: `os.getuid()` e `os.O_NOFOLLOW` | A execução de fluxo falha com `AttributeError` |
| `adapters/screen_recorder.py`: `send_signal(SIGINT)` | No Windows levanta `ValueError`, que não é tratado |
| `adapters/adb.py` | Não procura `%LOCALAPPDATA%\Android\Sdk\platform-tools`; o `adb` precisa estar no `PATH` |
| Caminhos `~/Library/...` e `~/Movies` | Viram pastas estranhas na pasta do usuário. Não é fatal |

Funciona em tese, sem teste: proxy, analytics por logcat, log do OkHttp,
espelho e hierarquia Android, e o Relatório (auditar e exportar). O CI roda
só em Ubuntu e macOS.

## Instalação fácil (o que foi feito na 3.10)

- **`setup.check` no motor** (`services/setup.py`).
  - Lista o que está instalado por grupo: Motor, Android, iOS e Extras.
  - Marca cada item como obrigatório ou opcional.
  - Calcula o estado de cada área por plataforma e escolhe o próximo passo.
  - Só procura arquivos e lê `package.json`, sem subir Node nem Xcode, e
    responde em menos de 0,1 s.
  - Uma plataforma que você não começou a montar não conta como pendência
    enquanto a outra estiver em uso. Quem só testa Android não vê o Appium
    como "falta".
- **Tela Início no app nativo** (`Views/Home`).
  - Mostra um próximo passo em destaque, as quatro áreas com o estado por
    plataforma e o Ambiente item a item.
  - Cada item que falta tem um botão: "Instalar no Terminal…" quando um
    script resolve, ou "Abrir na App Store…" para o Xcode.
  - Confere de novo sozinha quando o app volta ao primeiro plano, que é
    quando a pessoa termina uma instalação no Terminal.
  - O app sempre abre no Início, com a hierarquia fechada (desde a
    3.14.0). O atalho é ⌘0.
- **Motor parado por falta de Python:** o Início ainda funciona. Ele diz o
  que falta e oferece "Instalar no Terminal…" e "Reiniciar Motor".
- **`tools/setup/instalar-mac.sh <alvo>`**, embutido no app em
  `Contents/Resources/setup`.
  - Alvos: `python`, `android`, `scrcpy`, `appium`, `appium-android`,
    `ios-device`, `escuta`, `tudo` e `verificar`.
  - Usa o Homebrew e oferece instalá-lo, com confirmação.
  - Cada comando aparece antes de rodar.
  - Pacotes Python vão para o Python que o app usa (`MOBAILE_PYTHON`). Se
    esse Python for gerenciado pelo Homebrew, vão para o Python do Mo baile.
- **Por que o Terminal, e não instalar por baixo:** a pessoa vê o que roda,
  digita a senha quando o Homebrew pede e pode parar com ⌃C. Abrir um
  `.command` não pede permissão de automação.
- **`tools/setup/instalar-windows.ps1`:** ver a seção Windows.

## Pendências encontradas

Ficaram fora desta entrega:

1. **`PATH` do motor aberto pelo Finder** (`EngineClient.swift`): acrescentar
   `/opt/homebrew/bin` e `/usr/local/bin`, para o Appium achar o `node`. Hoje
   o Início só avisa.
2. **O `.env` nunca é lido** (`config.py` só usa `os.getenv`), mas o README e
   o CONTRIBUTING mandam copiar o `.env.example`.
3. **"MITM" em textos de interface e em `docs/SEGURANCA.md`**, sem MITM no
   código.
4. **A sonda do Python** (`-I -S`) não olha o site do usuário, e o motor
   olha: um `pip install --user` pode reprovar na sonda e funcionar no motor.
5. **Windows:** os defeitos da tabela acima, um job de CI em `windows-latest`
   e a decisão de suportar ou não, que reabre o ADR 0005.
