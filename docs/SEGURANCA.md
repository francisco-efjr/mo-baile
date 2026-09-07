# Auditoria de segurança

Escopo: todo o código do repositório, com foco no que processa entrada externa.

"Entrada externa" aqui é mais ampla do que parece à primeira vista. Inclui o
serial do aparelho, que vem de `adb devices` e de `adb connect`; o XML de
hierarquia, gerado pelo app sob teste; o tráfego que atravessa o proxy; e o
texto que o usuário digita para ser enviado ao aparelho.

Cada item abaixo tem teste de regressão em `engine/tests/unit/test_security.py`
ou em `engine/tests/integration/test_proxy.py`. Se a falha voltar, a suite
reprova.

---

## 1. Injeção de código no gerador de fluxos

**Severidade: alta. Corrigido.**

`generate_hidden_runner_script` montava o script Python interpolando o serial
direto dentro de uma string literal:

```python
DEVICE_ID = "{device_id}"
```

Um serial contendo aspa dupla fecha a string e emenda código Python arbitrário,
que é executado quando o fluxo roda. O caminho de ataque é real: um alvo
conectado por TCP tem o endereço escolhido por quem faz o `adb connect`.

O detalhe que confirma o descuido é que `adb_path` e `wda_url`, no mesmo
trecho, já usavam `repr()`.

**Correção.** O serial passa por allowlist antes de qualquer uso, e entra no
script via `repr()`. Os passos gravados deixaram de ser interpolados como
literal Python e viram JSON desserializado em tempo de execução, o que também
elimina um segundo problema silencioso: `json.dumps` produz `true` e `null`,
que não são literais válidos em Python.

## 2. Injeção de comando no shell do aparelho

**Severidade: alta. Corrigido.**

`adb shell input text <texto>` não é seguro só por usar lista de argumentos. O
adb concatena tudo depois de `shell` e entrega a string ao `sh` do aparelho.
O escaping existente trocava espaço por `%s` e nada mais, então `;`, `&&`,
`$(...)` e crase eram interpretados no dispositivo.

**Correção.** `mobaile.security.shell.build_adb_input_text_args` monta o comando
remoto como argumento único entre aspas simples, que é o único quoting POSIX em
que nada no interior é interpretado. O mesmo tratamento foi aplicado dentro do
script de fluxo gerado.

## 3. XXE e expansão de entidade no parser de hierarquia

**Severidade: média. Corrigido.**

`ET.fromstring` aceita DOCTYPE e definição de entidade. O XML vem do
`uiautomator dump` e do `/source` do WebDriverAgent, ou seja, é gerado pelo app
sob teste. Isso abria espaço para expansão exponencial, que trava a interface,
e para leitura de arquivo local por entidade externa.

**Correção.** `mobaile.security.xml_safe` usa o expat com DOCTYPE e entidade
recusados explicitamente, mais teto de tamanho. Sem dependência nova. XML
malformado continua devolvendo lista vazia, porque hierarquia quebrada é rotina
e não merece exceção.

## 4. Script executável em caminho previsível

**Severidade: média. Corrigido.**

O script de fluxo era gravado na raiz do projeto como `.flow_runner.py` com
permissão `0755`. Código executável em caminho previsível e gravável, entre a
escrita e a execução, é uma janela de troca de conteúdo.

**Correção.** O arquivo vai para um diretório da sessão criado com `0700`, com
permissão `0600`, aberto com `O_NOFOLLOW`. A execução usa
`sys.executable <script>`, que dispensa bit de execução.

## 5. Credenciais do cliente guardadas em claro

**Severidade: média. Corrigido.**

O proxy fica no meio da sessão autenticada do app. Tokens, cookies e campos
como CPF e senha ficavam em memória, apareciam na tela e podiam ser exportados.
Uma captura de tela durante uma demonstração vazaria credencial de produção.

**Correção.** `mobaile.security.redaction` mascara `Authorization`, `Cookie`,
`X-Api-Key` e afins nos cabeçalhos, e `password`, `token`, `cpf`, `cvv` e
similares em corpo JSON. Fica ligado por padrão. `MOBAILE_REDACT=0` desliga,
como decisão consciente do operador.

## 6. Consumo de memória sem limite no proxy

**Severidade: média. Corrigido.**

`events_history` crescia para sempre e o corpo de resposta era guardado inteiro,
decodificado como UTF-8 mesmo quando binário. Um download atravessando o túnel
derrubava o processo, e um vídeo virava megabytes de caractere de substituição.

**Correção.** Histórico virou buffer circular com teto. Corpo tem limite de
captura com marcação de truncamento. Conteúdo não textual vira um resumo em vez
de lixo decodificado. `Content-Length` do cliente é validado antes de virar
tamanho de leitura, e há teto de conexões simultâneas.

## 7. Vazamento de detalhe interno na resposta de erro

**Severidade: baixa. Corrigido.**

Em falha de encaminhamento, o proxy devolvia `str(exception)` ao aplicativo,
o que expõe endereço e porta da rede interna do host.

**Correção.** O cliente recebe mensagem genérica. O detalhe continua no evento,
para quem está depurando.

## 8. Configuração sem validação

**Severidade: baixa. Corrigido.**

Os campos eram lidos com `float(os.getenv(...))` no corpo da dataclass. Um
valor não numérico no `.env` derrubava a aplicação no import, sem mensagem
útil, e `STREAM_FPS=0` virava divisão por zero longe da causa.

**Correção.** Cada campo tem faixa válida. Valor fora da faixa gera aviso no log
e cai no padrão.

## 9. Erros engolidos em silêncio

**Severidade: baixa. Em andamento.**

O código tinha cerca de quarenta ocorrências de `except Exception: pass`. Em
ferramenta de automação, falha silenciosa custa mais caro que ruído: o teste
passa, o passo não executou e ninguém fica sabendo.

**Situação.** Corrigido em todo o motor, com exceções tipadas e log. A interface
Tkinter ainda tem ocorrências, e é código em transição.

---

## O que não é falha, e por que

**O proxy é um MITM.** É a função dele. A mitigação é escutar apenas em
`127.0.0.1` e alcançar o aparelho por `adb reverse`, em vez de expor a porta na
rede local. Configurar `PROXY_HOST` fora do loopback transforma a máquina em
proxy aberto para quem estiver no mesmo Wi-Fi, e por isso o motor registra
aviso quando isso acontece.

**O motor executa binários externos.** adb, scrcpy e xcrun são o propósito da
ferramenta. Os caminhos são resolvidos em lista fixa, os argumentos vão em
lista e nunca via shell do host, e toda entrada externa passa por validação.

## Ferramentas e resultado atual

```
bandit -r engine/src -ll      →  nenhum achado de severidade média ou alta
ruff check engine apps tools  →  limpo
pytest (engine)               →  91 testes, todos passando
```

Os achados restantes do bandit são todos de severidade baixa e correspondem ao
uso legítimo de `subprocess`, que é inerente a uma ferramenta que dirige adb.

## Pendências conhecidas

1. **Certificate pinning.** O proxy não decifra HTTPS: o método CONNECT abre
   túnel e conta bytes. Inspecionar corpo de HTTPS exige CA própria instalada no
   aparelho, com todo o cuidado que isso implica. O estudo em
   `docs/research/estudo-http-toolkit.md` descreve o caminho.
2. **Assinatura do aplicativo.** O empacotamento usa assinatura ad-hoc, que
   serve para a própria máquina. Distribuir para o time sem aviso do Gatekeeper
   exige Developer ID e notarização.
3. **`apps/tk-legacy`.** Recebeu as correções de caminho e de import, mas não
   passou pela mesma revisão linha a linha do motor. É código com data para
   sair.
