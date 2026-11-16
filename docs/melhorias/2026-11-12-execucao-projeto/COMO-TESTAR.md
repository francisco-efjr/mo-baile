# Como testar: área Execução, fase B1 (3.23.0)

Branch `melhoria/2026-11-12-execucao-projeto`. Só macOS. Python do `.venv` do
checkout principal, Android SDK em `~/Library/Android/sdk`, scrcpy 5.0.1 e Swift 6.
O projeto a rodar precisa de um Python com behave (nesta máquina,
`/usr/local/bin/python3` tem behave 1.2.6).

## Suítes

```bash
make check
```

Resultado esperado: motor com 1080 aprovados (963 subtests), UI Tk 20, gate de QA 11,
os 5 fluxos de QA e as fixtures em dia.

```bash
make test-swift
```

Resultado esperado: 536 testes, 29 pulados, 0 falhas.

## No app (com o projeto de exemplo)

Copie o exemplo para fora do repositório, para não tocar na fixture:

```bash
cp -R engine/tests/fixtures/projeto_exemplo_behave ~/Desktop/projeto_exemplo_behave
```

1. Abra o `Mo baile (nativo)` e aperte **⌘6** (Execução). O Ambiente continua em ⌘5.
2. **Abrir Projeto…** → escolha `~/Desktop/projeto_exemplo_behave`.
   **Esperado:** entrada `main.py → main_sem_args()`; config ativa
   `config_android_local_HLG` com selo **Local**; três alternativas comentadas, duas
   com **Nuvem (bloqueada)**; suítes `test_suite_time_01..03` com as features e os
   cenários; `test_suite_canais` como suíte não chamada; chaves sensíveis só pelo nome.
3. Interpretador: o exemplo aponta para um `.venv` que não existe. Em
   **Pythons desta máquina**, clique **Usar** em `/usr/local/bin/python3` (behave 1.2.6).
4. Doctor: as checagens que rodam o Python do projeto aparecem **puladas** até você
   clicar **Confiar no Projeto e Verificar…** e confirmar.
5. Com o emulador ligado (`emulator-5554`), deixe **Gravar vídeo** marcado e clique
   **Rodar**. **Esperado:** console ao vivo; banner **Passou**, 5 cenários e 15 steps;
   **Abrir Pasta da Execução** mostra `console.log`, `video.mp4` e `resumo.json` em
   `~/Documents/Mo baile/Execuções/projeto_exemplo_behave/<data-hora>/`.
6. Falha: no `.idea/runConfigurations/main.xml` da cópia, acrescente dentro de `<envs>`
   a linha `<env name="EXEMPLO_CENARIO_FALHA" value="1" />` (as variáveis do exemplo
   estão no topo de `core/runner.py`) e clique **Rodar** de novo. **Esperado:** como
   as envs mudaram, o Mo baile pede a confiança outra vez; depois, banner **Falhou**
   com as contagens. Com `EXEMPLO_FALHAR_INIT=1` o resultado é **Indeterminado**; com
   `EXEMPLO_DORMIR=3`, dá tempo de testar o **Parar** do passo 8.
7. Nuvem: troque o `init(...)` ativo do `main.py` da cópia para
   `config_kobiton_android_HLG`. **Esperado:** Rodar bloqueado com a explicação; o doctor
   falha em "Nuvem".
8. Parar: rode e clique **Parar** no meio. **Esperado:** **Cancelado**, sem processo
   `python` do projeto sobrando (`pgrep -fl projeto_exemplo_behave`).
9. Trava: durante uma execução, tente ler a hierarquia ou rodar um flow no mesmo
   aparelho. **Esperado:** mensagem "o aparelho está rodando o projeto…".

## Com o projeto real do dono

Repita os passos 2–5 com a pasta real. Pontos para olhar:
- o interpretador detectado (run configuration ou SDK do PyCharm) é o mesmo do PyCharm;
- a config ativa e as features batem com o `main`;
- o aparelho do `udid` da config é o escolhido (se diferente, o motor recusa e explica);
- se o selo for **Não confirmado** (hub montado em tempo de execução), o Mo baile pergunta
  "Rodar mesmo assim?".

## O que foi executado nesta rodada (Verificado)

- Motor real, em processo, com o exemplo e behave 1.2.6 no `emulator-5554`: `passed`,
  5 cenários e 15 steps, `video.mp4` H.264 1080×2424 gravado e hash da pasta do projeto
  igual antes e depois. Com a tela mudando, o scrcpy gravou 8,2 s para cerca de 8,6 s
  reais. Com a tela parada, o vídeo fica curto: o scrcpy não grava quadro repetido.
- `failed` com cenário que falha e com `after_all` que lança; `indeterminate` com
  `init` que lança; `run.stop` encerrando os netos (testes de contrato).
- Capturas da área (claro, escuro, 980×600 e 1280×720) pelo `WindowSnapshotTests`.

## O que não foi verificado

- O projeto real do dono (a rodada usou só o exemplo, por escolha dele).
- O vídeo no moto g55 e no simulador iOS, e a gravação pelo `screenrecord`.
- O ⌘F do console e o anúncio do VoiceOver no app real.
- Run configurations e `jdk.table.xml` reais do PyCharm: os testes usam arquivos montados.

## Como desfazer

```bash
git switch melhoria/2026-11-03-pycharm-desempenho
```
O app volta à 3.22.0 com `make update-native` a partir dessa branch.
