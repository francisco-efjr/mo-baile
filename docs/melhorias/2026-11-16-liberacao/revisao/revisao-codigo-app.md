# Revisão de código: app (LIB-2, LIB-3, LIB-4)

Revisor: `code-quality-refactoring:code-reviewer`, só leitura, sobre
`git diff 4913365..HEAD -- apps/MoBaile .github tools`. Veredito: **aprovar com
ressalvas**, nenhum achado de severidade alta. Independência parcial: mesmo
modelo do autor.

| # | Sev. | Local | Problema | Correção aplicada |
|---|---|---|---|---|
| R1 | Média | `BugReport.swift` (validate/saveFolder) | Dois anexos com o mesmo nome em pastas diferentes (ou só com maiúsculas diferentes): a cópia pulava o segundo sem avisar | Nome repetido, sem diferenciar maiúsculas, é recusado como duplicado |
| R2 | Média | `HomeModel.swift`, `HomeFirstRun.swift` | A Início dizia "sem internet", e o aviso de versão consulta o GitHub ao abrir | Texto da Início cita a consulta diária de versão, desligável em Ajustes |
| R3 | Baixa | `BugReport.swift` (issueURL) | O corte contava caracteres, não bytes codificados. Acentos e emoji podiam passar do teto | Corte pelo tamanho codificado. No limite, vão só template, título e uma nota, com o relato inteiro copiado |
| R4 | Baixa | `UpdateChecker.swift` | Reabrir dentro de 24 h perdia a faixa, e o "Lembrar Amanhã" chegava a ~48 h | O último release fica guardado, e a decisão roda sem rede dentro das 24 h |
| R5 | Baixa | `BugReport.swift` (validate) | Tipo conferido só pela extensão: um executável renomeado para `.png` entrava por arrastar | Recusa arquivo executável e confere a assinatura de png, jpg, gif, pdf e zip |
| R6 | Baixa | `HelpWindow.swift` | "Ir para…" procurava a janela pelo título, que é o nome da seção | `openWindow(id: "main")` |
| — | Baixa | `UpdateBanner.swift` | Abria a URL do feed sem conferir o esquema | Só abre `https` |

Desvio de escopo registrado: o quarto toggle, "Últimas linhas do log do
motor", com redação e prévia editável (spec §4.4), ficou para a próxima rodada
(`MELHORIAS.md`, Próximos passos).
