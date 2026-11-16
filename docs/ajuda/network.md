---
area: network
titulo: Rede HTTP
resumo: Veja o tráfego HTTP do aparelho, filtre e exporte em HAR.
precisa: aparelho conectado; proxy ou app em debug
---

## O que é

Rede HTTP lista as requisições que o app faz, com request e response lado a lado. Você pode ler o tráfego por um proxy ou direto do app em debug.

## Quando usar

- Para entender por que uma chamada falha.
- Para conferir o corpo enviado e a resposta recebida.
- Para levar o tráfego a outra ferramenta, em HAR.

## Passo a passo

1. Abra **Rede HTTP** (⌘2) com o aparelho conectado.
2. Clique em **Configurar Proxy** ou, se o app estiver em debug, em **Ler Tráfego do App em Debug**.
3. Use o escopo (Todos, API, Mídia, Erros, Lentas) e a busca da barra, como `status:4xx`.
4. Clique numa linha para ver request e response.
5. Clique em **Exportar HAR…** (⇧⌘E) para salvar.

## Exemplo prático

No DemoApp, o login retorna erro. Ligue o proxy ou use **Ler Tráfego do App em Debug**, faça o login no aparelho e busque `status:4xx`. Abra a requisição que falhou e confira a resposta. Clique com o botão direito e escolha **Copiar como cURL** para repetir a chamada no terminal. Para mandar ao time, use **Exportar HAR…**.

## Recursos

- **Configurar Proxy** / **Parar Proxy**: liga e desliga o proxy; o aparelho precisa apontar para ele.
- **Ler Tráfego do App em Debug**: lê o tráfego do app sem proxy nem certificado.
- **Escopo**: filtra por Todos, API, Mídia, Erros ou Lentas (acima de 1 s).
- **Busca**: aceita `status:4xx`, `metodo:POST` e `tipo:json`.
- **Copiar como cURL**: copia a requisição para repetir no terminal.
- **Exportar HAR…**: salva o tráfego em HAR para outras ferramentas.
- **Limpar Tráfego**: esvazia a tabela para começar uma captura limpa.
- **Por que não vejo tráfego?**: abre um diagnóstico com as causas mais comuns.

## Problemas comuns

- **A tabela está vazia.** Clique em **Por que não vejo tráfego?** e siga o diagnóstico.
- **O app usa certificate pinning.** O proxy não enxerga a chamada. Use **Ler Tráfego do App em Debug**.
- **O proxy não inicia.** A porta pode estar em uso. Troque a porta em Ajustes › Conexões.
