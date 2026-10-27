# Documentação do Mo baile

Os documentos estão em dois grupos. **Vivos** descrevem como o projeto é e
devem acompanhar o código: se um deles contradiz o código, o documento está
errado e precisa de correção no mesmo PR. **Registros históricos** contam o que
aconteceu numa data; não são atualizados e podem citar código que já mudou.

Para começar: [README do repositório](../README.md) e
[CONTRIBUTING](../CONTRIBUTING.md).

## Documentos vivos

| Documento | Conteúdo |
|---|---|
| [ARQUITETURA.md](ARQUITETURA.md) | Camadas, dependências e a regra de que a lógica mora no motor |
| [PROTOCOLO_RPC.md](PROTOCOLO_RPC.md) | Contrato JSON-RPC entre motor e front. Mudou? `make fixtures` |
| [adr/](adr/) | Decisões de arquitetura, uma por arquivo (lista abaixo) |
| [SEGURANCA.md](SEGURANCA.md) | Auditoria de segurança, correções e pendências. Política de reporte: [SECURITY.md](../SECURITY.md) |
| [INSTALACAO.md](INSTALACAO.md) | O que instalar numa máquina zerada (Mac e Windows), por recurso, e a tela Início |
| [VERSIONAMENTO.md](VERSIONAMENTO.md) | SemVer obrigatório a cada push, hook e CI |
| [RELEASE.md](RELEASE.md) | Empacotamento, workflow de release, assinatura e notarização |
| [QA.md](QA.md) | Estado da suíte e roteiro de verificação manual |
| [../qa/README.md](../qa/README.md) | Harness de ponta a ponta com aparelhos falsos |
| [design/design-system/](design/design-system/) | Design system 3.0 (Liquid Glass): tokens, componentes, protótipo |
| [design/paletas/](design/paletas/) | Paletas alternativas; `palettes.css` é referência dos testes |
| [design/telas/](design/telas/) | Catálogo de capturas da interface, claro e escuro |
| [design/relatorio.md](design/relatorio.md) | Especificação da aba Relatório |

### Decisões (ADR)

| ADR | Decisão |
|---|---|
| [0001](adr/0001-motor-python-front-swift.md) | Motor Python headless e front SwiftUI |
| [0002](adr/0002-redesenho-liquid-glass.md) | Redesenho 3.0 com o design system Liquid Glass |
| [0003](adr/0003-relatorio-tagueamento.md) | Relatório de tagueamento com o `tag_audit` como núcleo |
| [0004](adr/0004-https-sem-proxy-android.md) | HTTPS sem proxy no Android pelo log do OkHttp |
| [0005](adr/0005-app-tk-congelado.md) | App Tk congelado; o app nativo é o produto |

## Planejamento em aberto

Documentos de trabalho que ainda orientam o que fazer a seguir. Ficam na raiz
de `docs/` porque o [AGENTS.md](../AGENTS.md) e o histórico apontam para eles.

| Documento | Conteúdo |
|---|---|
| [RODADA_2026-10-05_PENDENCIAS.md](RODADA_2026-10-05_PENDENCIAS.md) | Pendências da rodada de 05–06/10; conferir antes de começar uma melhoria |
| [MELHORIAS_2026-10-09.md](MELHORIAS_2026-10-09.md) | Revisão de produto de 09/10 e os itens P0/P1 |

## Pesquisa

| Documento | Conteúdo |
|---|---|
| [research/estudo-mercado/](research/estudo-mercado/) | Estudo de mercado e plano de evolução em etapas |
| [research/estudo-http-toolkit.md](research/estudo-http-toolkit.md) | Estudo do HTTP Toolkit |
| [research/interceptador-rede.md](research/interceptador-rede.md) | Notas do interceptador de rede |
| [research/pontos-de-melhoria-2026-10-05.md](research/pontos-de-melhoria-2026-10-05.md) | Pontos de melhoria levantados em 05/10 |
| [design/handoff-desktop/](design/handoff-desktop/), [design/designer-prompt.md](design/designer-prompt.md), [design/designer-spec.json](design/designer-spec.json) | Especificação visual e handoff anteriores ao 3.0 |

## Registros históricos

Em [historico/](historico/). Não são atualizados.

| Documento | Data | Conteúdo |
|---|---|---|
| [historico/ESTADO_ATUAL.md](historico/ESTADO_ATUAL.md) | 07/09/2026 | O que funcionava, o que dependia de aparelho e o que era fachada |
| [historico/RELATORIO_QA.md](historico/RELATORIO_QA.md) | 09/2026 | Resultado dos quatro fluxos de QA e os defeitos encontrados |
| [historico/QA_2026-10-05.md](historico/QA_2026-10-05.md) | 05/10/2026 | Análise por risco, melhorias e validação |
| [historico/PROMPT_CLAUDE_CODE.md](historico/PROMPT_CLAUDE_CODE.md) | 09/2026 | Prompt interno usado para conduzir um agente de código |
| [historico/PROMPT_MELHORIAS_DEV_UX_QA.md](historico/PROMPT_MELHORIAS_DEV_UX_QA.md) | 10/2026 | Prompt interno da rodada de melhorias de 05/10 |

O [CHANGELOG](../CHANGELOG.md) é o registro oficial do que mudou em cada
versão; alguns trechos antigos dele citam estes arquivos no caminho anterior,
direto em `docs/`.
