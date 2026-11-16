# Liberação pública: rodada de 16/11/2026 (3.24.0)

Rodada do orquestrador brain-of-agent, modo melhoria (§3.1), a partir do pedido
de 16/11: ver o que está pendente, deixar o sistema pronto para qualquer pessoa
baixar e atualizar, remover dado pessoal e de empresa, ajuda por módulo, aviso
de produto em desenvolvimento com relato de bugs, e execução fora do macOS.

## Resumo

- **Onde estávamos:** `STATUS.md`. A `main` está na 3.17.3, o trabalho local
  vai até a 3.23.0, e o release "Latest" (3.21.0) saiu de uma branch que não é
  a `main`. O repositório já é público.
- **Download e atualização:** dá para baixar e usar num Mac com Apple Silicon,
  passando pelo aviso do Gatekeeper e pela instalação do Python, que o próprio
  app faz. Antes não havia aviso de versão nova; agora há (LIB-4).
- **Privacidade:** a árvore foi neutralizada (LIB-1). O histórico público
  ainda guarda o que a árvore não tem mais: decisão D1.
- **Ajuda:** guia curto por área, dentro do app e no GitHub (LIB-2).
- **Beta e bugs:** selo Beta, aviso de primeira abertura e Relatar um Problema,
  que vira issue no GitHub (LIB-3). Relato sem conta no GitHub: decisão D3.
- **Fora do macOS:** Relatório e logcat salvo no navegador com
  `python -m mobaile.web` (LIB-5).

## Especialistas e validação

| Papel | Plugin:agente | Saída | Validado por |
|---|---|---|---|
| Privacidade (árvore, histórico, binários) | `security-appsec:security-reviewer` | `revisao/privacidade.md` (resumo público; o detalhado fica em `.privado/`, fora do git) | busca final de termos depois da LIB-1 |
| Distribuição e atualização | `cli-desktop-tooling:release-readiness-auditor` | `revisao/distribuicao.md` | orquestrador (proposta P, risco baixo) |
| Multiplataforma | `architecture-design:architecture-reviewer` | `revisao/multiplataforma.md` | `architecture-design:skeptic-architect`: `revisao/contraprova-multiplataforma.md` (aprovado com 7 mudanças) |
| Ajuda, beta e relato | `ux-ui-design:ui-designer` | `revisao/ux-ajuda-beta-bugs.md` | testes Swift dos critérios de aceite |
| Textos de ajuda | `technical-writing-docs:technical-writer` | `docs/ajuda/` | teste de formato e de atalhos |
| Código do app | orquestrador | LIB-2, LIB-3, LIB-4 | `code-quality-refactoring:code-reviewer`: `revisao/revisao-codigo-app.md` |
| Web local | implementador `backend-api` | LIB-5 | testes de segurança e paridade, mais a revisão |

## Linha de base × depois

| Verificação | Antes (3.23.0) | Depois (3.24.0) |
|---|---|---|
| `make check`: versão, ruff, bandit | ok | ok |
| Motor (pytest) | 1080 aprovados, 963 subtestes | 1124 aprovados, 993 subtestes (+44 e +30 da web) |
| Tkinter / harness de QA | 20 / 11 | 20 / 11 |
| Fluxos sem device / iOS / Android / HTTPS / relatório | 19 / 31 / 35 / 34 / 28 | 19 / 31 / 35 / 34 / 28 |
| `swift test` | 536 testes, 29 pulados, 0 falhas | 566 testes, 29 pulados, 0 falhas |
| Termos reais de pessoa ou empresa na árvore | vários (ver resumo de privacidade) | 0 |
| Servidor web no ar (`curl`) | — | 401 sem chave, 421 Host forjado, 403 Origin forjado, -32601 fora da lista, sem CORS, só 127.0.0.1 |

Validação funcional com Playwright (§3.2): não executada. O app é desktop
nativo, sem superfície web. A página web nova foi verificada pelos testes de
integração com o servidor real, por `curl` e por captura no navegador
embutido.

## Melhorias

| ID | Especialista | Problema | Mudança | Antes → depois | Como foi provado | Commits |
|---|---|---|---|---|---|---|
| LIB-1 | security-appsec | Serial, UDID e ids de produto com cara de reais, nome do dono em testes e maquetes, caminhos da máquina em relatórios, capturas com nome e pasta, termos do domínio antigo | Dados sintéticos, textos neutros, catálogo sem nome nem pasta (ganchos só de teste), capturas afetadas removidas | termos reais na árvore: vários → **0** | varredura com a lista de termos reais (`.privado/`) e com padrões pessoais; suíte completa | `f6c338a`, `6ed6711`, `1ceae7e`, `8148e85` |
| LIB-2 | ux-ui-design + technical-writer | Nenhuma ajuda dentro do app | `docs/ajuda/` (9 guias) e janela Ajuda (⌘?, botão ?, menu Ajuda), empacotada e conferida pelo verify | 0 → 9 guias, um por área | `HelpAndBugReportTests` (formato, atalhos, parser, empacotamento) | `b3cf0ec`, `5691e72` |
| LIB-3 | ux-ui-design | Nada dizia que é beta; não havia canal de relato | Selo Beta, aviso por versão maior, Sobre com crédito, Relatar um Problema (⇧⌘B) → issue no GitHub (`bug-app.yml`) | — → relato em 1 janela, sem token no app | `HelpAndBugReportTests` (validação, URL com os ids do formulário, corte, anexos, pasta, aviso) | `5691e72`, `a941b92` |
| LIB-4 | cli-desktop-tooling | Quem instalava nunca sabia de versão nova (DIST-08) | Consulta diária ao GitHub Releases, faixa com Baixar/Ver Novidades/Lembrar/Ignorar, menu e ajuste | sem aviso → aviso em até 1 dia | `UpdateCheckerTests` (13) | `83cfe03`, `a941b92` |
| LIB-5 | architecture-design + backend-api | Sem macOS, nada rodava | `python -m mobaile.web`: Relatório e logcat salvo no navegador, só em loopback (ADR 0007) | só macOS → Windows/Linux com Python | 44 testes + 30 subtestes (segurança e paridade); `curl` no servidor no ar (401/421/403/-32601, sem CORS, só 127.0.0.1) | `67db3f5` |
| LIB-6 | cli-desktop-tooling + technical-writer | README e notas com instrução de abertura desatualizada; nada sobre beta, Intel, atualização, Windows | README, notas do release, SEGURANCA, RELEASE, CONTRIBUTING, template de PR | — | revisão | `0dccfc6` |

Revisão de código independente do app: nenhum achado alto; R1–R6 corrigidos
(`revisao/revisao-codigo-app.md`).

Teto do protocolo (6 melhorias, ~600 linhas): o número de melhorias foi
respeitado, mas o diff de produção passou (≈2.750 linhas, contando a página web
estática, o formulário do GitHub e as janelas novas do app). Foi uma escolha:
o pedido listava as seis frentes como requisitos da liberação.

## Propostas descartadas na contraprova

- Tk legado para Windows: exigiria refazer o Relatório em Tk e reverter o ADR 0005.
- Port da auditoria para JS: duplicaria cerca de 2.000 linhas de regra de negócio.
- Método RPC novo `analytics.import_text`: mudaria o contrato do app Swift sem ganho para ele.
- Atualização no lugar (baixar e trocar o bundle) e Sparkle: só valem com Developer ID.

## Decisões do dono (16/11)

- **D1 (histórico limpo): sim.** Repositório atual vira `mo-baile-historico`,
  privado; `mo-baile` é recriado com um commit só (roteiro em
  `pendentes/d1-historico-limpo.md`).
- **D2 (publicação): sim.** Publica a 3.24.0 no repositório novo.
- **D3 (relato sem conta no GitHub):** explicar melhor antes de decidir
  (`pendentes/d3-relato-sem-conta.md`).
- **Campo "Cooperativa":** fica como está.
- **Tema "Praia":** não é dado sensível; fica.
- **Developer ID da Apple:** explicar (custo anual, tira o aviso do Gatekeeper
  e mantém as permissões entre versões).

## Próximos passos

- Relato: quarto toggle "Últimas linhas do log do motor", com redação e prévia
  editável (spec §4.4); serviço intermediário se a D3 for sim.
- Recapturar as telas removidas do catálogo com conta e pasta neutras
  (`docs/design/telas/CHECKLIST.md`).
- Web, fase 2: escuta Android ao vivo, editor de spec, job `windows-latest` no
  CI e teste num Windows de verdade.
- Build universal (Intel) ou manter só Apple Silicon; Developer ID e
  notarização se o dono aprovar o custo.
- Pendências de produto anteriores: `STATUS.md`.
