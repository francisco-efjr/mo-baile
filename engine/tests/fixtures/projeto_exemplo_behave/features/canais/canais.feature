# language: pt
Funcionalidade: Canais

  Esquema do Cenário: Abrir o canal <canal>
    Dado que o app de exemplo esta aberto
    Quando eu toco em "<canal>"
    Então vejo a tela "<canal>"

    Exemplos:
      | canal    |
      | Pix      |
      | Cartoes  |
