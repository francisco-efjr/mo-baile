Feature: Login no ambiente HLG

  Scenario: Entrar com usuario de teste
    Given que o app de exemplo esta aberto
    When eu toco em "Entrar"
    Then o login responde conforme o ambiente
