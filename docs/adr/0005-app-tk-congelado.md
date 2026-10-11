# ADR 0005 — App Tk congelado; o app nativo é o produto

Data: 2026-10-11
Status: aceito

## Contexto

O Mo baile tem duas interfaces sobre o mesmo motor Python
([ADR 0001](0001-motor-python-front-swift.md)):

- `apps/tk-legacy/`, a interface Tkinter original, instalada como
  `Mo baile.app` por `tools/install_tk_app.sh`;
- `apps/MoBaile/`, o front SwiftUI, instalado como `Mo baile (nativo).app` por
  `tools/package_macos_app.sh`.

Desde a 3.0 (redesenho Liquid Glass, [ADR 0002](0002-redesenho-liquid-glass.md))
todo recurso novo entrou só no app nativo: aba Relatório
([ADR 0003](0003-relatorio-tagueamento.md)), HTTPS sem proxy
([ADR 0004](0004-https-sem-proxy-android.md)), busca em tudo, inspector
contextual. O app Tk ficou atrás em recursos e continua com dívidas conhecidas
(métodos que chamam o motor por fora do contrato, partes de fachada).

Com a abertura do código, quem chega precisa saber qual app usar e onde
contribuir. Manter as duas interfaces em paridade dobraria o custo de cada
recurso e contrariaria a regra de que lógica vive no motor, não no widget.

## Decisão

1. O **app nativo (SwiftUI) é o produto**. É o que vai para o GitHub Releases,
   o que o README apresenta e onde entram recursos novos.
2. O **app Tk fica congelado**: sem recurso novo. Aceita só correção de
   defeito grave (perda de dados, falha de segurança, quebra ao abrir) enquanto
   continuar no repositório.
3. As suítes do Tk continuam no portão (`make check`) enquanto o código existir,
   para que mudanças no motor não o quebrem sem aviso.
4. O motor não ganha código específico para o Tk. Se uma mudança no contrato
   quebrar o Tk, o Tk se adapta ou o recurso afetado fica indisponível nele.

## Consequências

- Issues e PRs de recurso para o Tk são fechados com link para este ADR.
- O README e o CONTRIBUTING passam a dizer que o Tk está congelado.
- `SECURITY.md` lista o Tk com suporte limitado (só falha grave, sem prazo).
- Remover o Tk do repositório é uma decisão futura, em ADR próprio, quando o
  app nativo cobrir os fluxos que ainda dependem dele. Até lá, `make install-app`
  continua funcionando.
