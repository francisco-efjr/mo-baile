# Changelog

Todas as mudanças relevantes do Mo baile ficam aqui, da mais nova para a mais
antiga. O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e a numeração segue o [Versionamento Semântico](https://semver.org/lang/pt-BR/).
A regra de quando e como subir a versão está em [docs/VERSIONAMENTO.md](docs/VERSIONAMENTO.md).

## [2.1.1] - 2026-10-06

### Corrigido

- Execução de fluxo: o texto digitado não aparece mais no `flow.log`, nas
  notificações nem no stdout do motor; o log registra só o tamanho e o campo.
  Passo de digitação sem texto falha com motivo, em vez de digitar os textos
  inventados "Texto de Exemplo" ou "Texto de Teste".
- Proxy: redação de credenciais em corpo, URL, Location/Referer e erros;
  encaminhamento em blocos com teto de captura; recusas tipadas (400/413/501/502)
  sem chamar a origem; `Proxy-Authorization` não chega à origem.
- `flow.stop` cooperativo entre passos; falha de ADB reprova o passo.
- Front Swift preserva passos, edições e evidências quando o RPC falha e
  descarta respostas antigas de hierarquia pela geração.
- Gate de QA exige resumo válido, usa ferramentas falsas e portas efêmeras;
  testes Tkinter distinguem skip de erro.

### Acessibilidade

- Rótulos, estados e papéis para VoiceOver na toolbar, controles segmentados,
  abas, tabelas HTTP e de analytics, editores, espelho e estado vazio, com
  testes que leem a árvore de acessibilidade real do macOS.

### Documentação

- Revisão de QA de 05/10 (`docs/QA_2026-10-05.md`), relatório de pontos de
  melhoria (`docs/research/pontos-de-melhoria-2026-10-05.md`) e pendências da
  rodada de melhorias, com análise item a item e o trabalho parcial preservado
  (`docs/RODADA_2026-10-05_PENDENCIAS.md`).

## [2.1.0] - 2026-10-01

### Adicionado

- Tagueamento iOS no simulador: a aba Analytics lê o log do Firebase
  (`-FIRDebugEnabled`) pelo `log stream` do simulador, remontando a mensagem de
  várias linhas e mostrando um evento só por disparo, mesmo com o SDK logando
  cada evento em mais de um estágio.
- Tagueamento iOS em iPhone físico por cabo, via `pymobiledevice3` (dependência
  opcional `engine[ios-device]`). Seletor de origem na aba Analytics
  (Automático, Simulador ou o iPhone) e método `analytics.ios_devices`.
- Protocolo JSON-RPC v2 (etapa 1, "motor que não trava"): `engine.hello` com
  aperto de mão versionado, seis filas de despacho declaradas em
  `rpc/contract.py`, `$/cancelRequest` e `$/progress`.
- Cliente Swift com prazo por método vindo do motor, quadros sem acúmulo e
  reinício automático do motor quando ele cai.
- Estudo de mercado e plano de evolução em `docs/research/estudo-mercado/`.
- Versionamento: arquivo `VERSION`, este CHANGELOG, `tools/version.py`, hook de
  `pre-push` e verificação no CI.

### Corrigido

- Parar e reiniciar a escuta de analytics duplicava cada evento na interface.
- Estado da sessão protegido por lock e época; o desmonte do motor sobrevive a
  SIGTERM.

### Desempenho

- Import do motor de ~250 ms para ~60 ms, com dependências pesadas carregadas
  só quando usadas.

## [2.0.0] - 2026-09-08

Linha de base: primeira versão declarada, antes do versionamento formal. Motor
headless em Python com fronteira JSON-RPC, interface Tkinter e front nativo
SwiftUI em construção.
