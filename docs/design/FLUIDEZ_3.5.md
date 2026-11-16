# Fluidez 3.5: especificação

Pedido do dono: "preciso que seja o mais fluido possível para o usuário fazer
qualquer ação dentro do sistema".

Brief: QA de apps móveis no Mac (superfície Operate). A tarefa principal é
conectar um aparelho, gravar passos, inspecionar rede e analytics e rodar o
fluxo, sem procurar onde fica cada coisa.

Base: 3.4.0 (`8fe6cdc`). Evidências: avaliação de UX (UX-1 a UX-5), revisão
de código (COD-3, COD-4) e contraprova (contraste recalculado com `#141543`).

## Problema

1. **Ação espalhada.** Cada comando mora num lugar diferente: menu,
   toolbar, barra acessória da área, botão do editor ou cartão do estado
   vazio. Quem não lembra onde está precisa varrer quatro regiões da janela.
   Nada busca ações por nome.
2. **Motor caído sem saída.** Quando o motor cai e a supervisão desiste,
   ou quando ele nem sobe (Python errado), a única pista é a barra de status.
   O texto ainda diz "Feche e abra o Mo baile". Não há botão de reinício.
3. **Python errado é aceito.** O `EngineLocator` pega o primeiro `python3`
   executável. O `/usr/bin/python3` 3.9 sem Pillow passa, o motor morre na
   importação e o app entra no laço de reinício (PB7).
4. **Estado sem aparelho sem um próximo passo claro.** Os dois cartões têm o
   mesmo peso. Os textos misturam jargão ("último scan", "AVD(s)") e um
   rótulo fora do tom ("Verificar de Novo").
5. **Texto terciário ilegível.** `labelTertiary` a 0,40 sobre branco dá
   2,53:1, abaixo dos 4,5:1 da WCAG 1.4.3.
6. **Barra de status em siglas.** WDA, FA listener, settle: o tooltip só
   repete a sigla. As métricas usam 10,5 pt.
7. **Defeitos pequenos que quebram o fluxo.** O cursor de redimensionar
   fica preso quando a divisória some (COD-3). Buscar na hierarquia sem
   aparelho altera `inspectorVisible` e deixa um pedido de foco pendente, que
   rouba o foco quando o aparelho conecta (COD-4).

## Decisões

| # | Decisão | Por quê |
|---|---|---|
| D1 | Registro único de ações (`AppCommand`, `CommandRegistry`). Um registro descreve cada ação: título, categoria, sinônimos, atalho, símbolo e disponibilidade no contexto. A execução fica num só lugar (`CommandPerformer`), que chama a `EngineSession` ou mexe no `AppState`, como os botões já faziam. | Menu, paleta e testes leem a mesma fonte, e o título e o motivo de indisponibilidade não divergem. Nenhuma regra de negócio nova: a disponibilidade repete as condições `.disabled` que já existiam nas views. |
| D2 | Atalho da paleta: **⇧⌘P** no menu Visualizar › Paleta de Comandos…. O **⌘K** continua com Atualizar Tela. | O pedido era ⌘K, mas o atalho já pertence a Atualizar Tela, e a regra era não quebrar atalhos. O ⇧⌘P é a alternativa prevista no pedido e é o atalho de paleta do VS Code e do Xcode. Para trocar, basta mudar `CommandID.palette` e `CommandID.captureNow` no registro. |
| D3 | A paleta é um painel flutuante sobre a janela (material de vidro, raio 12, 560 pt de largura), e não uma janela nova. Ela fecha com Esc, com clique fora ou depois de executar uma ação. | O vidro fica na camada de navegação (design system). Uma janela nova roubaria o foco do app. |
| D4 | Busca aproximada com acentos e caixa ignorados: cada termo digitado precisa casar com o título, a categoria ou os sinônimos. A pontuação, da maior para a menor, é palavra exata, prefixo de palavra, trecho e subsequência. Grupos de sinônimos: ligar = iniciar = começar = abrir; parar = desligar = encerrar = fechar; buscar = procurar = pesquisar = filtrar; ajustes = preferências = configurações; gravar = capturar = registrar. | O QA digita o verbo que lembra, não necessariamente o do menu. |
| D5 | Sem termo digitado, até 5 recentes aparecem no topo e o resto vem por categoria. Com termo, a ordem é pela pontuação, e no empate vence a mais recente. As recentes ficam no `UserDefaults` (`mobaile.paleta.recentes`). | Repetir uma ação custa ⇧⌘P e Enter. |
| D6 | Ação indisponível aparece esmaecida (42%), com o motivo na mesma linha ("Conecte um aparelho"). Enter não executa e só lê o motivo para o VoiceOver. | Esconder a ação faria a pessoa achar que ela não existe. Com o motivo, ela sabe o que destrava. |
| D7 | Faixa global "Motor parado" no topo da coluna central, com o estado vindo de `EngineSession.engineStatus`. Reiniciando, ela mostra progresso e não tem botão. Parado, mostra a mensagem e o botão **Reiniciar Motor** (`restartEngine()` = `disconnect()` + `connect()`, o ciclo de vida que já existe). O VoiceOver recebe o anúncio ao aparecer. | É a supervisão que já existe, com uma saída manual quando ela desiste. |
| D8 | O `EngineLocator` testa cada candidato com `python -c` (versão 3.10 ou mais nova, `import PIL, requests`). O teste tem prazo de 3 s e o resultado fica em cache por caminho. A ordem dos candidatos não muda. Se nenhum servir, o erro diz o que foi achado e o que instalar, e aparece na faixa da D7. | Corrige o PB7 do lado Swift. O `tools/verify_native_app.sh` recebe a mesma regra por outro agente. |
| D9 | Sem aparelho, um único botão em destaque. O cartão da plataforma ativa com ação pendente vence. Na falta dele, vence o outro cartão com ação. Sem ação nenhuma, nenhum botão fica em destaque. O cartão recomendado ganha a etiqueta "Próximo passo", e o outro fica com botão comum. | O motor já marca a ação de cada checagem (`action`). A interface só escolhe qual delas ganha ênfase. |
| D10 | `labelTertiary`: o alfa mínimo, em centésimos, que dá 4,5:1 sobre conteúdo, conteúdo alternativo, janela e sidebar da aparência. Praia clara: 0,62. Escura: 0,49. Nas paletas, o alfa é calculado pela mesma fórmula em Swift e em `paletas-data.js`, e o `palettes.css` é atualizado. | O terciário e o secundário ficam próximos no claro. A hierarquia continua pelo peso e pelo tamanho. Isso é o que o macOS faz em Aumentar contraste. |
| D11 | Barra de status: cada serviço ganha uma explicação em linguagem natural no tooltip e no VoiceOver. Exemplo: "WebDriverAgent: o serviço que deixa o Mo baile tocar e ler a tela do iPhone. Ligado." As métricas passam para 11 pt, e "settle" vira "estável em". | A sigla continua visível para quem já conhece, e quem não conhece tem a explicação a um passar de mouse. |

## Ações da paleta

Categoria · título · atalho · disponível quando (motivo exibido quando não está)

| Categoria | Ação | Atalho | Indisponível com o motivo |
|---|---|---|---|
| Áreas | Ir para Page Objects / Rede HTTP / Analytics / Relatório | ⌘1–⌘4 | sempre disponível |
| Visualizar | Mostrar/Ocultar Inspector | ⌥⌘I | sem aparelho: "O inspector volta ao conectar um aparelho" |
| Visualizar | Mostrar/Ocultar Espelho | ⌥1 | sempre disponível |
| Visualizar | Mostrar/Ocultar Workspace | ⌥2 | sempre disponível |
| Visualizar | Mostrar Todos os Painéis | ⌥⌘F | sempre disponível |
| Visualizar | Modo Zen / Sair do Modo Zen | ⌃⌘Z | sempre disponível |
| Visualizar | Usar Aparência Clara/Escura | — | paleta alternativa ativa: "A paleta escolhida define a aparência" |
| Visualizar | Buscar na Hierarquia | ⌘F | sem aparelho: "Conecte um aparelho" |
| Visualizar | Buscar nesta Área | ⌘F | só em Rede, Analytics e Relatório |
| Aparelho | Usar «nome do aparelho» (uma por aparelho listado) | — | já é o aparelho em uso |
| Aparelho | Procurar Aparelhos iOS/Android | — | sempre disponível |
| Aparelho | Atualizar Lista de Aparelhos | ⇧⌘R | motor parado |
| Aparelho | Atualizar Tela | ⌘K | sem aparelho |
| Aparelho | Iniciar/Parar Espelho | ⌘E | sem aparelho |
| Aparelho | Clique Repassa Toque / Clique Grava Passo | — | sem aparelho |
| Aparelho | Abrir Simulador | — | sem simulador instalado |
| Aparelho | Abrir Emulador Android | — | sem emulador (AVD) criado |
| Aparelho | Espelho 60 FPS (scrcpy) | — | só no Android com aparelho e scrcpy |
| Serviços | Iniciar WebDriverAgent | — | fora do iOS, ou já ligado |
| Serviços | Iniciar/Parar Proxy | — | motor parado |
| Serviços | Ler Tráfego do App em Debug / Parar | — | Android sem aparelho |
| Serviços | Iniciar/Parar Escuta de Analytics | — | sem origem: "Conecte um aparelho" |
| Gravação | Gravar do Aparelho / Parar Captura | — | sem aparelho; iPhone físico: "No iPhone físico, use o clique no espelho" |
| Gravação | Gravar a Tela / Parar de Gravar a Tela | — | sem aparelho |
| Automação | Rodar Automação | ⌘R | sem passos: "Grave ao menos um passo"; sem aparelho; já rodando |
| Automação | Interromper Execução | — | nada rodando |
| Automação | Estrutura do Fluxo… | — | sem passos |
| Automação | Salvar Page Object | ⌘S | sem código gerado |
| Automação | Limpar Passos… | — | sem passos |
| Rede | Exportar HAR… | ⇧⌘E | sem tráfego capturado |
| Rede | Limpar Tráfego… | — | sem tráfego capturado |
| Analytics | Exportar JSON de Analytics… | — | sem eventos |
| Analytics | Limpar Eventos… | — | sem eventos |
| Relatório | Abrir Spec de Tagueamento… | ⌘O | operação em andamento |
| Relatório | Importar Prints do Figma… | — | operação em andamento |
| Relatório | Auditar | — | sem spec ou sem eventos |
| Relatório | Exportar Relatório… | — | sem relatório |
| App | Ajustes… | ⌘, | sempre disponível |
| App | Reiniciar Motor | — | já reiniciando |

Fica de fora: **Parar WebDriverAgent**. O contrato não tem `wda.stop`, e
a ação exigiria mudança no motor. Ações contextuais de linha (copiar
locator, copiar cURL) dependem de uma seleção e continuam no menu de contexto.

## Critérios de aceite

1. ⇧⌘P abre a paleta, com o foco no campo. Esc fecha e devolve o foco à
   janela. ↑ e ↓ movem a seleção, e Enter executa a ação selecionada. O
   VoiceOver lê "Paleta de comandos", o título, o atalho e o motivo de cada
   linha.
2. Os testes de modelo cobrem: "proxi" e "PROXY" acham o proxy; "ligar
   proxy" e "inspecao" acham as ações certas pelo sinônimo e sem acento; a
   recente vem primeiro com termo vazio; a lista de recentes não repete itens
   e tem no máximo 5; sem aparelho, "Rodar Automação" sai indisponível com
   motivo; o registro tem um título único por ação; todo atalho dos menus
   existe no registro e não há dois iguais.
3. Com o motor parado, a faixa aparece com a mensagem e "Reiniciar Motor".
   O botão chama `restartEngine()`, que reconecta. O teste de modelo cobre
   o `engineStatus` em conectado, reiniciando e parado, e cobre o reinício
   manual depois de a supervisão desistir.
4. O `EngineLocator` recusa Python abaixo de 3.10 e Python sem dependências,
   e mantém a ordem dos candidatos. O erro cita o que instalar. Os testes
   usam uma sonda falsa.
5. Sem aparelho, há exatamente um botão `.borderedProminent`, e nenhum texto
   diz "último scan", "AVD(s)" ou "Verificar de Novo".
6. Um teste calcula `labelTertiary` ≥ 4,5:1 sobre os fundos opacos em Praia
   clara e escura, nas 9 paletas e em Aumentar contraste.
7. Nenhuma métrica da barra de status fica abaixo de 11 pt. Cada serviço tem
   explicação em linguagem natural no tooltip e no rótulo de acessibilidade.
8. Ocultar o workspace com o cursor sobre a divisória devolve a seta: o
   `onDisappear` faz o pop do cursor só se houve push.
9. Com o inspector suprimido, Buscar na Hierarquia fica desabilitado e não
   altera `inspectorVisible` nem `hierarchySearchFocusRequest` (teste em
   ModelTests).
10. `swift build` e `swift test` passam.

## Não verificado nesta rodada

VoiceOver real, navegação por Tab na janela inteira e uso por pessoas. O que
o modelo avalia é opinião, e os três pontos mais importantes (paleta, faixa
do motor e estado sem aparelho) pedem teste com QA de verdade.
