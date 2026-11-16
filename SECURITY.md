# Política de segurança

## Como reportar uma vulnerabilidade

**Não abra issue pública** para falha de segurança.

Use o relato privado do GitHub (Private Vulnerability Reporting):

1. Abra a aba **Security** do repositório
   [francisco-efjr/mo-baile](https://github.com/francisco-efjr/mo-baile/security).
2. Clique em **Report a vulnerability**
   ([link direto](https://github.com/francisco-efjr/mo-baile/security/advisories/new)).
3. Descreva o problema, a versão afetada (`Mo baile` > *Sobre*, ou o arquivo
   `VERSION`), o macOS, e os passos ou a prova de conceito.

O relato fica visível só para você e para o mantenedor. Não inclua dados reais
de terceiros, tokens válidos ou capturas de tráfego de produção: use valores
sintéticos.

### O que esperar

| Etapa | Prazo-alvo |
|---|---|
| Confirmação de recebimento | 7 dias |
| Avaliação inicial (aceito, precisa de mais dados ou fora de escopo) | 14 dias |
| Correção ou plano de mitigação para falha confirmada | 90 dias |

O projeto é mantido por uma pessoa, em tempo parcial: os prazos são metas, não
garantia. Você recebe crédito no advisory e no `CHANGELOG.md`, se quiser.

## Versões suportadas

Só a versão mais recente recebe correção de segurança. O Mo baile não mantém
branches de versões antigas: a correção sai numa versão nova.

| Versão | Suporte |
|---|---|
| Última versão publicada (3.x mais recente) | Sim |
| Versões 3.x anteriores | Não; atualize |
| 2.x e anteriores | Não |
| App Tk legado (`apps/tk-legacy/`) | Só falha grave, sem prazo ([ADR 0005](docs/adr/0005-app-tk-congelado.md)) |

## Escopo

Dentro do escopo, entre outros:

- injeção de comando ou código a partir de entrada externa (serial do
  aparelho, XML de hierarquia, tráfego do proxy, texto digitado);
- vazamento de credencial ou dado pessoal capturado (falha na redação de
  `Authorization`, cookie, senha, CPF);
- proxy de inspeção acessível pela rede local sem o usuário ter pedido;
- escrita de arquivo fora dos diretórios esperados.

Fora do escopo:

- o app não ser notarizado pela Apple (limitação conhecida, documentada no
  [README](README.md#instalação));
- ataques que exigem acesso prévio de administrador à máquina do usuário;
- vulnerabilidades em Appium, WebDriverAgent, `adb` ou Xcode: reporte ao
  projeto de origem.

## Modelo de ameaça e histórico

A auditoria de segurança, as correções já feitas e as pendências estão em
[docs/SEGURANCA.md](docs/SEGURANCA.md). Cada item corrigido tem teste de
regressão em `engine/tests/`.
