# Cético: sincronizar a automação com o tempo do aparelho

Papel: `architecture-design:skeptic-architect` (brain-of-agent), somente leitura, 28/10/2026.
Proposta desafiada: rascunho S1–S14 do orquestrador (consolidado em `PROPOSTA.html`).

## Perguntas (B = bloqueante)
1. **B.** O que tem dentro da árvore de 11887 bytes? Se essa tela não tiver ProgressBar nem id de loading (skeleton de Views simples, WebView), o indicador de carregamento não pega nada. Capturar o XML antes de desenhar.
2. **B.** Quais leituras do log são do FlowRunner? O inspetor também lê pela mesma sessão (`server.py:962-969`) e há o prefetch depois do toque no espelho (`server.py:1884,1894-1908`). O toque do flow sai por `adb input tap` (`flow_devices.py:83-84`) e não aparece no log do Appium. "Depois de um toque" é Inferido.
3. **B.** Na gravação que falhou, qual passo agiu sobre a tela intermediária, e ele era coordenada ou id/texto?
4. Qual foi o sintoma: toque no lugar errado, elemento não encontrado em 17 s ou digitação perdida?
5. O app tem ProgressBar ou Lottie permanente (player, pull-to-refresh)?

## Contraprova C1–C9
- **C1 Confirmado.** `maestro_flow.py:886-891`: duas leituras iguais com 200 ms mais a latência. Uma tela estável por 0,6–2 s passa.
- **C2 Ajustado.** O atalho só vale com `backend=="adb"` (`flow_devices.py:59-63`, `maestro_flow.py:880-882`). A evidência vem do `/source` do Appium, onde o atalho fica desligado. É risco só do caminho do dump.
- **C3 Confirmado.** `maestro_flow.py:897-899`. Toque por ponto também nunca repete: com `antes is None`, o laço sai na primeira volta (`:919`).
- **C4 Ajustado.** O cache não causa chegada falsa: se a árvore guardada não casa, ele relê (`:858-861`), e qualquer ação o descarta (`:740-742`). O risco real é o seletor casar também na tela intermediária. "enabled" e "caixa parada" não são conferidos: Confirmado.
- **C5 Ajustado.** O flag fica desligado (`:1224`), mas ligado ele não resolveria a evidência: a tela intermediária muda a árvore, então `depois != antes`.
- **C6 Confirmado.** `:924-929`.
- **C7 Confirmado.** `:887-894` devolve `anterior` sem log.
- **C8 Confirmado** (`server.py:1934-1935`, `flows.py:384,414`), irrelevante para o moto g55.
- **C9 Confirmado** (`:1236`), relevância baixa. O `export_steps` já põe `launchApp` (`:1167-1168`).
- **Causa que faltava (Verificado).** Passo com id/texto já espera chegar: o `_alvo` do próximo passo procura por até 17 s (`:900-903`, `:831-867`). O buraco está concentrado em coordenada (C3) e em seletor que também casa na tela intermediária (C4).

## S1–S14
- **S1 Ajustar.** Só indicador visível (área > 0, centro na tela); limite de 5 s e seguir com log; desenhar depois de ver o XML de 11887. Risco: ProgressBar permanente.
- **S2 Descartar.** Uma janela de 600 ms não vence uma tela estável por 2 s (houve 7 leituras de 11887 seguidas).
- **S3 Descartar agora.** `screencap` custa centenas de ms e tem o mesmo defeito do S2.
- **S4 Ajustar.** Âncora de 1 elemento como campo aditivo, não Jaccard.
- **S5 Vale.** Uma leitura a mais; em `enabled=false`, esperar pouco e tocar com log.
- **S6 Descartar como padrão.** Toque repetido em app lento duplica envio ("Pagar", "Enviar"). Opt-in.
- **S7 Ajustar.** Esperar o foco vale; comparar o texto só como aviso (senha, máscara, autocorreção).
- **S8 Descartar.** Fator estático não resolve espera por evento.
- **S9 Fora do escopo.** No g55 a sessão já é obrigatória (`server.py:955-960`).
- **S10 Adiar.** Mexe no aparelho, sem restauração se o motor cair; não explica tela parada por 2 s.
- **S11 Só diagnóstico.**
- **S12 Adiar.** Outra plataforma, sem evidência.
- **S13 Ajustar.** `launchApp` opcional vale; conferir âncora do primeiro passo depende do S4.
- **S14 Vale e vem primeiro**, com o XML real. O fake de roteiro já existe (`tests/unit/test_maestro_flow.py:388-394`).

## Novo: S15, conferência de ponto sem mudar formato
Antes de tocar uma coordenada, achar o nó mais fundo que contém o ponto e exigir `class == passo.class_name`, que já é gravado (`codegen.py:377-389`). Se não houver ou for indicador, esperar com o prazo de busca e depois tocar com log.

## Âncora ou localizador do próximo passo
- Próximo passo com id/texto: o localizador dele já é a condição de chegada; basta conferir caixa parada e habilitada.
- Passo só com coordenada: o mínimo é o S15.
- Estrutural: gravar **um** id ou texto estável da tela (título da toolbar) como campo aditivo; YAML `extendedWaitUntil: visible: {id: …}`.

## Custo e aceite (Suposição: sem medição de base)
- Até +300 ms por passo na mediana e até +15% no flow em telas sem carregamento; com carregamento, a espera do indicador limitada a 5 s.
- Aceite: (a) replay com o XML real vermelho antes, verde depois, zero ações sobre 6693 e 11887; (b) a gravação que falha no g55 passa 10/10 (medir a base antes); (c) "seguiu sem prontidão" 0 vezes em 10 execuções no emulador; (d) "tocando de novo" 0 vezes; (e) mediana por passo antes e depois.

## O que não construir (Inferido)
Jaccard, perfil por serial, fator manual, lista de indicadores nos Ajustes antes do primeiro falso positivo, screencap, repetição de toque por padrão.

## Pré-mortem de 12 meses (Inferido)
| Causa | Sinal precoce | Custo de reverter |
|---|---|---|
| Indicador permanente faz todo passo esperar até o limite | "seguiu sem prontidão" frequente | Barato (limite e flag) |
| Toque repetido duplica uma ação e o "Copiar Bug" gera bug falso | "tocando de novo" no log | Barato no código, caro na confiança |
| Âncora com conteúdo dinâmico: espera de 17 s no passo 1 só nas gravações novas | Falha só nas gravações novas | Médio a alto (formato já exportado) |

## Decisões pendentes (dono: Francisco)
- D3 repetir toque por padrão: **não**, opt-in por passo.
- D5 formato: só o campo aditivo de 1 âncora, na Fase 2.
- D1 e D2: adiar.
- Antes de tudo: responder as perguntas 1–3 com uma captura do XML durante o flow.
