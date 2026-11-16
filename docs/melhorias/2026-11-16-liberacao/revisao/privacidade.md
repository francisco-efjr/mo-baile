# Revisão de privacidade (resumo público)

Revisor: `security-appsec:security-reviewer`, só leitura, sobre a árvore atual,
o histórico completo (221 commits, todas as refs) e os binários (imagens e PDF).

- **Segredos reais:** nenhum. Tokens, CPFs, e-mails e senhas dos testes são
  sintéticos.
- **Árvore atual:** sobravam dados de teste com cara de dado real (serial,
  UDID, ids de produto, nome do dono em teste e maquete), caminhos absolutos
  da máquina de desenvolvimento em relatórios antigos e capturas de tela com
  esse caminho. Tudo foi neutralizado em LIB-1.
- **Histórico:** versões antigas de arquivos, mensagens de commit, e-mails de
  autor e capturas ainda guardam o que a árvore já não tem. Reescrever
  histórico público é decisão do dono (D1 em `../MELHORIAS.md`, roteiro em
  `../pendentes/d1-historico-limpo.md`).

O relatório detalhado, com cada achado e local, não fica no repositório
público: descrever o dado seria publicá-lo de novo. O dono tem a cópia local.
