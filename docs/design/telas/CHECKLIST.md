# Catálogo de telas · Mo baile (nativo) 3.3

Todas as telas e estados do app nativo depois do redesenho 3.0 (Liquid Glass)
da aba Relatório (3.2) e da rodada de melhorias de 09/10 (3.3), em tema claro e escuro. Substitui o catálogo da 2.x,
que foi para [`arquivo-2.x/`](arquivo-2.x/) (as telas de lá não existem mais).

- **29 telas/estados**, 56 PNGs (claro e escuro; as duas paletas alternativas
  impõem a aparência e saem uma vez só).
- **PDF:** [`catalogo-telas.pdf`](catalogo-telas.pdf), uma página por tela com
  as duas versões lado a lado.
- **Revisão rápida:** [`folha-de-contato.png`](folha-de-contato.png), todas as
  telas claras numa imagem só.
- Cenário de dados: iOS, iPhone 16 (393×852 pt), Page Object
  `onboarding_credito_objs`, seis passos gravados, seis requisições, três
  eventos; Relatório com as fixtures do motor (7 validações).

## Como regenerar

Com a tela do Mac desbloqueada (as janelas aparecem por um instante; com a
tela bloqueada, a captura sai preta):

```bash
cd apps/MoBaile
MOBAILE_SNAPSHOT_DIR="$(cd ../.. && pwd)/docs/design/telas" \
  swift test --filter WindowSnapshotTests/testCatalogoDeTelas
cd ../.. && python3 tools/catalogo_telas.py docs/design/telas
```

As cenas estão em `WindowSnapshotTests.swift` (`cenas`). Tela nova no app,
cena nova lá. As janelas são de verdade (`NSWindow` com toolbar, barra lateral e
inspector), por isso dá para revisar o Liquid Glass, a toolbar e o menu ».

Legenda: ✅ sem problema visual · ⚠️ defeito ou ponto a decidir (detalhe na
observação e na lista no fim).

## Telas e estados

| # | Tela / estado | Claro | Escuro | O que conferir | Status | Observação |
|---|---|---|---|---|---|---|
| 01 | Splash de abertura | [claro](01-splash-claro.png) | [escuro](01-splash-escuro.png) | Mascote, título, barra de progresso no destaque, texto de boot | ✅ | Corrigido na 3.3: fica até o app estar pronto, com a fase escrita ("Procurando aparelhos e simuladores…"), mínimo de 2,5 s e teto de 12 s. Não segue o tema, de propósito. |
| 02 | Sem dispositivo, procurando | [claro](02-sem-dispositivo-procurando-claro.png) | [escuro](02-sem-dispositivo-procurando-escuro.png) | Estado vazio enquanto o motor não respondeu | ⚠️ | O inspector mostra "Conecte um aparelho para ver a hierarquia" ao lado do estado vazio que diz a mesma coisa: ocupa 260 pt sem função. |
| 02b | Sem dispositivo, diagnóstico medido | [claro](02b-sem-dispositivo-diagnostico-claro.png) | [escuro](02b-sem-dispositivo-diagnostico-escuro.png) | Cartões iOS e Android, ações, último scan | ✅ | Ícone, cor e texto em cada checagem. Mesmo ponto do inspector vazio. |
| 03 | Page Objects sem passos | [claro](03-page-objects-inicial-claro.png) | [escuro](03-page-objects-inicial-escuro.png) | Espelho, editores vazios, inspector, toolbar | ⚠️ | O botão Rodar desabilitado fica quase invisível no claro (play branco sobre cápsula clara). O menu » aparece mesmo com a janela larga. |
| 03b | Page Objects, passo selecionado | [claro](03b-page-objects-passo-selecionado-claro.png) | [escuro](03b-page-objects-passo-selecionado-escuro.png) | Passo na barra lateral, código destacado, "Passo N de M" | ⚠️ | Corrigido na 3.3: o passo por coordenada é "toque em 1095, 210". Falta: os passos de digitação truncam o nome antes da máscara, e "ADB server" aparece numa sessão iOS (melhoria D4). |
| 03c | Editores lado a lado | [claro](03c-page-objects-lado-a-lado-claro.png) | [escuro](03c-page-objects-lado-a-lado-escuro.png) | Ações e locators, numeração, realce | ✅ | |
| 03d | Modo Zen | [claro](03d-modo-zen-claro.png) | [escuro](03d-modo-zen-escuro.png) | Só espelho e workspace | ✅ | Única janela que respeita os 1280 pt pedidos (ver achado da largura mínima). |
| 04 | Rede sem tráfego | [claro](04-rede-vazia-claro.png) | [escuro](04-rede-vazia-escuro.png) | Barra acessória, estado vazio com ação | ✅ | |
| 04b | Rede, POST 201 | [claro](04b-rede-detalhe-post-claro.png) | [escuro](04b-rede-detalhe-post-escuro.png) | Cores de método e status, Request e Response | ✅ | Corrigido na 3.3: o JSON mantém os números e a ordem do servidor (`28.4`, `487.32`). |
| 04c | Rede, túnel CONNECT | [claro](04c-rede-tunel-https-claro.png) | [escuro](04c-rede-tunel-https-escuro.png) | Estado de túnel no lugar do corpo | ✅ | |
| 04d | Rede, erro 422 | [claro](04d-rede-erro-422-claro.png) | [escuro](04d-rede-erro-422-escuro.png) | Cor 4xx igual na tabela e no detalhe | ✅ | |
| 05 | Analytics sem eventos | [claro](05-analytics-vazio-claro.png) | [escuro](05-analytics-vazio-escuro.png) | Origem no iOS, Iniciar Escuta | ✅ | |
| 05b | Analytics, evento selecionado | [claro](05b-analytics-evento-claro.png) | [escuro](05b-analytics-evento-escuro.png) | Tabela, Parâmetros, Log Bruto | ✅ | Corrigido na 3.3: a busca procura em parâmetros (chave e valor) e no log bruto. |
| 06 | Relatório sem spec | [claro](06-relatorio-vazio-claro.png) | [escuro](06-relatorio-vazio-escuro.png) | Sem aparelho, duas ações | ✅ | |
| 06b | Relatório, spec aberta | [claro](06b-relatorio-spec-aberta-claro.png) | [escuro](06b-relatorio-spec-aberta-escuro.png) | Cartão da spec, Auditar | ✅ | |
| 06c | Relatório, variação divergente | [claro](06c-relatorio-divergencia-claro.png) | [escuro](06c-relatorio-divergencia-escuro.png) | Conformidade, filtros, tabela, validação, bloco, card no inspector | ✅ | |
| 06d | Relatório, fora da spec | [claro](06d-relatorio-fora-da-spec-claro.png) | [escuro](06d-relatorio-fora-da-spec-escuro.png) | Eventos sem card e alertas | ✅ | |
| 06e | Revisão da importação (sheet) | [claro](06e-relatorio-revisao-importacao-claro.png) | [escuro](06e-relatorio-revisao-importacao-escuro.png) | Dúvidas por card, Usar Esta Spec | ✅ | |
| 07 | Janela mínima (980×640) | [claro](07-janela-minima-claro.png) | [escuro](07-janela-minima-escuro.png) | Nada cortado, excedente no » | ⚠️ | **A janela não encolhe abaixo de 1.885 pt** com barra lateral e inspector visíveis (achado 1). |
| 08 | Estrutura do fluxo (sheet) | [claro](08-estrutura-do-fluxo-claro.png) | [escuro](08-estrutura-do-fluxo-escuro.png) | Tabela ordenável, Copiar Resumo | ✅ | Corrigido na 3.3: "toque em x, y". |
| 08b | Executar fluxo, em andamento | [claro](08b-execucao-rodando-claro.png) | [escuro](08b-execucao-rodando-escuro.png) | Selo, progresso, passo ativo, terminal | ✅ | Corrigido na 3.3: "1 aprovado". |
| 08c | Executar fluxo, concluído | [claro](08c-execucao-sucesso-claro.png) | [escuro](08c-execucao-sucesso-escuro.png) | Todos OK, Concluir | ✅ | |
| 08d | Executar fluxo, falha | [claro](08d-execucao-falha-claro.png) | [escuro](08d-execucao-falha-escuro.png) | Passo que falhou, linha FAIL | ✅ | O passo que falhou agora aparece marcado (era defeito na 2.x). |
| 09 | Correlação (popover) | [claro](09-correlacao-claro.png) | [escuro](09-correlacao-escuro.png) | Último passo, contagens, gerar asserção | ✅ | Corrigido na 3.3: "Passo 6 · click toque em 1095, 210 · Coords" e o locator. |
| 10 | Ajustes › Geral | [claro](10-ajustes-geral-claro.png) | [escuro](10-ajustes-geral-escuro.png) | Formulário nativo | ✅ | |
| 10b | Ajustes › Conexões | [claro](10b-ajustes-conexoes-claro.png) | [escuro](10b-ajustes-conexoes-escuro.png) | Endereços só para leitura | ✅ | |
| 10c | Ajustes › Paletas | [claro](10c-ajustes-paletas-claro.png) | [escuro](10c-ajustes-paletas-escuro.png) | Galeria, prévias, contrastes | ✅ | |
| 11 | Paleta Terracota (escura) | [paleta](11-paleta-terracota.png) | — | Paleta impõe a aparência | ✅ | |
| 11b | Paleta Sálvia & Palha (clara) | [paleta](11b-paleta-salvia.png) | — | Mesma estrutura, outra identidade | ✅ | |

## Achados

1. **Largura mínima da janela.** Medido com `contentMinSize` na janela real
   (`MOBAILE_MEDIR=1` no `WindowSnapshotTests`): 1.885 pt em Page Objects,
   1.865 em Rede e 1.746 no Relatório com barra lateral e inspector; 1.325 só
   com a barra lateral, 1.141 só com o inspector, 581 sem os dois. O mínimo
   declarado é 980 pt. Num monitor de 2.560 pt passa despercebido; numa tela de
   MacBook (1.470 a 1.728 pt) a janela não cabe. A barra lateral soma 744 pt e o
   inspector 560 pt, bem mais que os 232 e 260 declarados. A barra de status
   impunha 690 pt sozinha (tudo em `fixedSize`) e já foi corrigida (passa a
   ceder espaço). Mover itens da toolbar de `.navigation` não mudou nada.
2. ~~Números do JSON reescritos na Rede (04b).~~ Corrigido na 3.3.
3. ~~Texto de depuração na Correlação (09).~~ Corrigido na 3.3.
4. **Rodar desabilitado quase invisível no claro** (03, 03b). Melhoria D2.
5. ~~Valores internos na interface: "click position", "position" (03b, 08).~~ Corrigido na 3.3.
6. **Inspector sem função sem aparelho** (02, 02b). Melhoria D3.
7. ~~Concordância: "1 aprovados" (08b).~~ Corrigido na 3.3.

As propostas que nascem destes achados estão em
[docs/MELHORIAS_2026-10-09.md](../../MELHORIAS_2026-10-09.md).

## O que não sai no catálogo

- Menus abertos, tooltips, alertas e painéis do sistema (NSOpenPanel).
- Hover no espelho, estados "Copiado" e a splash em movimento.
- Android: o cenário é iOS.
