# Revisão independente do diff (mobile-apps:mobile-pr-reviewer)

- **Data:** 2026-10-26.
- **Revisor:** subagente com o corpo do `mobile-pr-reviewer` do brain-of-agent,
  somente leitura (Read).
- **O que revisou:** o diff de `apps/MoBaile`, contra o ADR 0006.
- **Veredito:** aprovar com ressalvas. Este arquivo resume os achados e diz o
  que foi feito com cada um. O relatório original ficou na conversa da
  sessão.

| ID | Gravidade | Achado | Destino |
| --- | --- | --- | --- |
| D1 | Alta (dúvida) | O `.glassProminent`/`.borderedProminent` ignorariam o `foregroundStyle(onAccent)` | **Confirmado** na captura do recuo: na Costes, o rótulo saía branco sobre o dourado. **Corrigido:** o Rodar usa `ProminentGlassButtonStyle` (vidro tingido no 26, cápsula preenchida antes), com rótulo `onAccent`. Prova: cena 11e e `GlassTests.testRotuloDoRodar…` |
| D8 | Média (dúvida) | O vidro do Rodar dentro da cápsula compartilhada da toolbar | **Corrigido:** item do Rodar com `sharedBackgroundVisibility(.hidden)` no macOS 26 |
| A1 | Média | `MOBAILE_SEM_VIDRO` não prova o visual do 14 e 15 | ADR e CHECKLIST reescritos: "aproxima o recuo". A captura num 14 ou 15 real ficou como pendência |
| A2 | Média | Hover da cápsula: mais escuro no 14 e ausente com Reduzir transparência no 26 | **Corrigido:** `mbGlass(…, highlighted:)`. No `.fill`, `fillPrimary` no hover (igual a antes); no vidro e no sólido, um véu `fillSecondary`. Saiu `GlassSupport` da tela |
| A3 | Baixa | O trilho do splash passou de 5 para 6 pt | **Corrigido:** voltou para 5 |
| A4 | Média | O splash sem `ThemeManager` não tinha teste na suíte padrão | **Corrigido:** `GlassTests.testSplashSemTemaNoAmbienteNaoCai` |
| A5 | Baixa | Guarda de fonte com termos frouxos | **Corrigido:** regex em código sem comentários (`#available … macOS 26`, `.glass*`, `Glass`, `*Material`, `safeAreaBar`, `sharedBackgroundVisibility`, `ToolbarSpacer`, `scrollEdgeEffect*`, `backgroundExtensionEffect`) |
| A6 | Baixa | Guarda de vidro sobre vidro pulava arquivos em silêncio e cobria só 2 | **Corrigido:** agora falha quando o arquivo some e cobre a barra lateral, dois popovers e três sheets, também para `mbProminentGlassButton` |
| A7 | Baixa | Sem borda com Aumentar contraste no preenchimento do recuo | **Corrigido:** `.fill` ganha borda `controlBorder` com Aumentar contraste. O splash continua com a Praia clara de recuo, sem ler o contraste (aceito: o splash é fixo no tema claro) |
| A8 | Baixa | O marinho sobre `#D9567F` dá 4,58:1, e não 5,0:1 | **Corrigido** no comentário, no ADR e em `tokens/colors.css` |
| A9 | Baixa | `ProcessInfo.environment` lido a cada `body` | **Corrigido:** `getenv` |
| D2 | Dúvida | `onAccent` marinho sobre `accentHover` ou `accentPressed` | Não procede: o `grep` mostra `onAccent` só sobre `accent` e `selection`. O estilo próprio usa opacidade no clique, não `accentPressed` |
| D3 | Dúvida | O `materialize` dispara dentro do `.transition(.opacity)` do pai? | Não verificado: precisa gravar a tela com ⇧⌘P no app instalado |
| D4 | Dúvida | `Glass.interactive()` reage ao hover? | Coberto: o véu `highlighted` vale também sobre o vidro |
| D5 | Dúvida | Divisória dupla com `safeAreaBar` | Conferido na captura 03b: uma divisória só. `ToolbarLayoutTests` passou no macOS 26.3 |
| D6 | Dúvida | `_accessibilityReduceTransparency` é chave privada | Aceito: só no alvo de teste, e compila no SDK 26.2 |
| D7 | Dúvida | Laço infinito se não achar o `Package.swift` | **Corrigido:** para na raiz com `XCTSkip` |
| D-8 | Fora do escopo | Os `.borderedProminent` de conteúdo (Início, Ambiente) seguem com rótulo branco na Costes | Próximo passo: aplicar o recuo do `ProminentGlassButtonStyle` (sem vidro) a esses botões |
