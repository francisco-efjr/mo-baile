# Liquid Glass de verdade no macOS 26: APIs, regras e armadilhas

Pesquisa de 26/10/2026 para trocar a imitação com materiais pelo Liquid Glass
do sistema no app nativo (`apps/MoBaile`, alvo macOS 14, SwiftPM 5.10).

**Fonte de verdade:** `MacOSX26.2.sdk` do Xcode instalado (Swift 6.2.3), numa
máquina com macOS 26.3.1. As APIs `glassEffect`, `Glass`, `GlassEffectContainer`
e `ConcentricRectangle` estão em **SwiftUICore**, e não em SwiftUI:
`SwiftUICore.framework/.../arm64e-apple-macos.swiftinterface`. Quem procurar só
no `SwiftUI.swiftinterface` conclui, por engano, que elas não existem. As de
toolbar, botão e scroll estão em `SwiftUI.swiftinterface`.

Rótulos: **[SDK]** = conferido no `.swiftinterface` ou nos headers do SDK local.
**[Doc]** = página da Apple lida nesta pesquisa. **[Exp]** = experimento rodado
nesta máquina. **[Inferido]** = conclusão minha, sem fonte direta. **[Não
verificado]** = nem testei nem achei fonte.

---

## 1. APIs SwiftUI (macOS 26)

Salvo indicação, tudo traz `@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)`
e `@available(visionOS, unavailable)`. Abaixo, "26" quer dizer macOS 26.0.

| API | Declaração no SDK (resumida) | Disp. | Status |
|---|---|---|---|
| `glassEffect(_:in:)` | `func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View` | 26 | [SDK] |
| `glassEffect(..., isEnabled:)` | não existe. Para desligar, use `Glass.identity` | n/a | **Não encontrado no SDK** |
| `DefaultGlassEffectShape` | `struct DefaultGlassEffectShape: Shape` (é uma cápsula, segundo a doc) | 26 | [SDK] |
| `Glass` | `struct Glass: Equatable, Sendable { static var regular, clear, identity; func tint(_ color: Color?) -> Glass; func interactive(_ isEnabled: Bool = true) -> Glass }` | 26 | [SDK] |
| `GlassEffectContainer` | `struct GlassEffectContainer<Content: View>: View { init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) }` | 26 | [SDK] |
| `glassEffectID(_:in:)` | `func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View` | 26 | [SDK] |
| `glassEffectUnion(id:namespace:)` | `func glassEffectUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID) -> some View` | 26 | [SDK] |
| `glassEffectTransition(_:)` | `func glassEffectTransition(_ transition: GlassEffectTransition)`, com `GlassEffectTransition` igual a `.matchedGeometry`, `.materialize` ou `.identity` | 26 | [SDK] |
| `.buttonStyle(.glass)` | `extension PrimitiveButtonStyle where Self == GlassButtonStyle { static var glass; static func glass(_ glass: Glass) -> Self }` | 26 | [SDK] |
| `GlassButtonStyle` | `struct GlassButtonStyle: PrimitiveButtonStyle { init(); @available(macOS 26.1) init(_ glass: Glass) }` | 26 / **26.1** para o `init(_:)` | [SDK] |
| `.buttonStyle(.glassProminent)` / `GlassProminentButtonStyle` | `static var glassProminent`; `struct GlassProminentButtonStyle: PrimitiveButtonStyle { init() }` | 26 | [SDK] |
| `backgroundExtensionEffect()` | `func backgroundExtensionEffect()` e `func backgroundExtensionEffect(isEnabled: Bool)`, também em visionOS 26 | 26 | [SDK] |
| `ScrollEdgeEffectStyle` | `struct ScrollEdgeEffectStyle: Hashable, Sendable { static var automatic, hard, soft }` | 26 | [SDK] |
| `scrollEdgeEffectStyle(_:for:)` | `func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set)`, mais `scrollEdgeEffectHidden(_:for:)` | 26 | [SDK] |
| `safeAreaBar(edge:...)` | `func safeAreaBar(edge: VerticalEdge, alignment:, spacing:, content:)` e a variante com `HorizontalEdge`. Faz a barra própria ganhar scroll edge effect | 26 | [SDK] |
| `ToolbarSpacer` | `struct ToolbarSpacer: ToolbarContent, CustomizableToolbarContent { init(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic) }`, com `SpacerSizing` igual a `.flexible` ou `.fixed` | 26 (iOS/macOS) | [SDK] |
| `sharedBackgroundVisibility(_:)` | `extension ToolbarContent / CustomizableToolbarContent { func sharedBackgroundVisibility(_ visibility: Visibility) }` | 26 (iOS/macOS) | [SDK] |
| `ConcentricRectangle` | `struct ConcentricRectangle: Shape, Animatable { init(); init(corners: Edge.Corner.Style, isUniform: Bool = false); ... }`, mais `Shape.rect(corners:isUniform:)` e `Edge.Corner.Style.concentric`, `.concentric(minimum:)` e `.fixed(_:)` | 26 | [SDK] |
| `containerShape(_:)` | novo `containerShape(_ shape: some RoundedRectangularShape)` (26). O antigo `containerShape<T: InsettableShape>` continua | 26 | [SDK] |
| `.rect(corner: .containerConcentric)` | sintaxe mostrada na WWDC25 (sessão 323) que **não existe** no SDK final. Use `.rect(corners: .concentric)` ou `ConcentricRectangle()` | n/a | **Não encontrado no SDK** |
| `controlSize(.extraLarge)` | `ControlSize.extraLarge` com `@available(macOS 14.0)`. Já existia; no 26 ganha o visual novo de botão grande | 14 | [SDK] |
| `containerBackground(_:for:)` | macOS 14. No macOS só vale `ContainerBackgroundPlacement.window` (macOS 15); `.navigation` e `.navigationSplitView` são `unavailable` no macOS | 14/15 | [SDK] |
| `tabViewStyle(.sidebarAdaptable)` | macOS 15 | 15 | [SDK] |
| `windowToolbarStyle(_:)` / `.unified` | já existia; o Mo baile usa `.unified` | antigo | [SDK] |
| `toolbar(removing: .sidebarToggle)`, `searchToolbarBehavior` | presentes. `.minimize` é `unavailable` no macOS | 26 | [SDK] |

**AppKit, só como referência [SDK]:** `NSGlassEffectView` (`contentView`,
`cornerRadius`, `tintColor`, `style` igual a `.regular` ou `.clear`) e
`NSGlassEffectContainerView` (`contentView`, `spacing`, padrão 0). O header diz
que o container "processes similar glass effect views as a batch to improve
performance". Também chegam no 26: `NSBackgroundExtensionView`,
`NSBezelStyleGlass` (`NSButton.BezelStyle.glass`), `NSButton.tintProminence`,
`borderShape` e `NSView.prefersCompactControlSizeMetrics`.

### O que muda só por compilar com o SDK 26

- Barras, sheets, popovers e controles padrão adotam o material sozinhos e se
  adaptam a sobreposição e foco. [Doc: [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)]
- Toolbar: os itens vão para uma superfície de vidro flutuante e são agrupados
  automaticamente. `NavigationSplitView` ganha "a Liquid Glass sidebar that
  floats above your content". [Doc: [WWDC25 323](https://developer.apple.com/videos/play/wwdc2025/323/)]
- Menus ganham vidro e ícones à esquerda (também no macOS). Sheets ganham raio
  maior. Popovers: "remove those custom background views". [Doc: Adopting]
- Controles: "Most controls on macOS are slightly taller". Os tamanhos mini,
  small e medium mantêm o retângulo arredondado. [Doc: WWDC25 323]
- Opt-out temporário: `UIDesignRequiresCompatibility = YES` no Info.plist
  (macOS 26.0+). É ignorado ao compilar para o macOS 27. [Doc: [chave](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility)]
- Evidência local [Exp]: o catálogo `docs/design/telas/03-page-objects-inicial-claro.png`,
  gerado pelos testes no macOS 26, já mostra a sidebar flutuante e as cápsulas
  de vidro na toolbar. O vidro do sistema já está ativo no app hoje.

---

## 2. Regras do HIG e da Apple (com URL)

1. **Vidro só na camada funcional (navegação e controles flutuantes).** "Don't
   use Liquid Glass in the content layer… use standard materials for elements in
   the content layer". A exceção é slider ou toggle enquanto está sendo
   manipulado. [Doc: [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)]
   O exemplo da Apple é uma tabela: "making it Liquid Glass would make it compete
   with other elements". [Doc: [WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/)]
2. **Nunca vidro sobre vidro.** "always avoid glass on glass". [Doc: WWDC25 219]
   "avoid overcrowding or layering Liquid Glass elements on top of each other".
   [Doc: Adopting] "glass can not sample other glass". [Doc: WWDC25 323]
3. **Use com parcimônia.** "Limit these effects to the most important functional
   elements in your app". [Doc: HIG Materials]
4. **`.regular` é o padrão; `.clear` só sobre mídia.** `.regular` serve para
   qualquer contexto e para superfícies com muito texto (sidebar, popover).
   `.clear` exige três condições: estar sobre conteúdo rico em mídia, o conteúdo
   tolerar uma camada de escurecimento, e o que fica por cima ser forte e claro.
   "They should never be mixed". [Doc: WWDC25 219] Para escurecer: "If the
   underlying content is bright, consider adding a dark dimming layer of 35%
   opacity". [Doc: HIG Materials]
5. **Tint só para ação primária e estado.** "reserve it for elements that truly
   benefit from emphasis, such as status indicators or primary actions… apply
   color to the background rather than to symbols or text… Refrain from adding
   color to the background of multiple controls". [Doc: [HIG Color › Liquid Glass color](https://developer.apple.com/design/human-interface-guidelines/color)]
   Na toolbar: "Only specify one primary action, and put it on the trailing side".
   [Doc: [HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)]
6. **Sem fundo próprio em barras e controles.** "Reduce the use of toolbar
   backgrounds and tinted controls… use a ScrollEdgeEffectStyle when necessary".
   [Doc: HIG Toolbars] "Prefer to remove custom effects and let the system
   determine the background appearance". [Doc: Adopting]
7. **Legibilidade.** Rótulos e símbolos em vidro são monocromáticos por padrão.
   A sidebar é "more opaque… to preserve legibility". Evite cor parecida entre o
   rótulo e o conteúdo atrás dele. [Doc: HIG Color]
8. **Sidebar:** pode flutuar no vidro. Conteúdo visual rico pode passar por
   baixo via `backgroundExtensionEffect()`. Os ícones seguem o accent color do
   sistema. [Doc: [HIG Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)]
9. **Formas concêntricas** com o contêiner (`ConcentricRectangle`,
   `.rect(corners:)`). Na toolbar, componentes padrão já são concêntricos.
   [Doc: Adopting; HIG Toolbars]

Não achei uma página do HIG chamada só "Liquid Glass". As regras estão em
Materials, Color, Toolbars e Sidebars. [Doc]

### Acessibilidade: quem faz o quê

- **O sistema faz sozinho [Doc: WWDC25 219]:** "Reduced Transparency makes
  Liquid Glass frostier and obscures more of the content behind it. Increased
  contrast makes elements predominantly black or white and highlights them with
  a contrasting border and Reduced Motion decreases the intensity of some
  effects and disables any elastic properties… These are available
  automatically whenever you use the new material." Isso vale para o vidro do
  sistema e para o `glassEffect` próprio, porque os dois usam o mesmo material.
  O HIG acrescenta a preferência de aparência do Liquid Glass nos Ajustes.
  [Doc: HIG Materials]
- **O app precisa:** testar os elementos próprios, as cores e as animações com
  esses ajustes ligados ("Ensure you test your app's custom elements, colors,
  and animations"). [Doc: Adopting] Na prática:
  - não pintar por cima do vidro algo que impeça a adaptação (gradiente,
    sombra, borda fixa);
  - respeitar `@Environment(\.accessibilityReduceMotion)` nas animações próprias
    (`withAnimation` que move ou transforma vidro) [Inferido];
  - em Aumentar contraste, conferir as cores de tema sobre o vidro
    (`colorSchemeContrast`) [Inferido].
  Não é preciso ramificar em `accessibilityReduceTransparency` para o vidro do
  sistema [Inferido, a partir da citação acima]. A skill dickwu recomenda isso,
  mas para imitações (blur próprio), não para o material real.

---

## 3. Do macOS 14/15 para o 26, e o padrão de fallback

- **14/15:** materiais (`.regularMaterial`, `NSVisualEffectView`), toolbar
  unificada sem cápsulas, sidebar colada à borda e `borderedProminent`.
- **26:** vidro dinâmico (refração, adaptação claro/escuro conforme o que está
  atrás, morphing), sidebar flutuante, cápsulas agrupadas na toolbar, scroll edge
  effect e formas concêntricas.
- O pacote declara `.macOS(.v14)`. Tudo o que é do 26 fica atrás de
  `if #available(macOS 26, *)`, com o fallback para material dentro do mesmo
  `ViewModifier`. O exemplo abaixo foi **compilado** com
  `swiftc -typecheck -target arm64-apple-macos14`, sem erro nem aviso. [Exp]

```swift
import SwiftUI

/// Vidro do sistema no macOS 26; material no 14/15.
struct GlassSurface<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color? = nil        // só ação primária ou estado
    var interactive = false       // só se a superfície recebe clique

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

extension View {
    func glassSurface<S: Shape>(in shape: S, tint: Color? = nil,
                                interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }
}

/// Agrupa vidros vizinhos (fusão + uma passada de render). No 14/15 é transparente.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26, *) { GlassEffectContainer(spacing: spacing) { content } }
        else { content }
    }
}
```

Também compilou no mesmo teste [Exp]: `ToolbarSpacer(.fixed)` e
`.sharedBackgroundVisibility(.hidden)` dentro de `if #available` no
`@ToolbarContentBuilder`, além de `.buttonStyle(.glass(.regular.tint(.blue)))`,
`ConcentricRectangle()`, `.rect(corners: .concentric(minimum: .fixed(8)))`,
`scrollEdgeEffectStyle(.soft, for: .top)` e `backgroundExtensionEffect()`.

**O que o Mo baile já tem** (lido no código em 26/10):
- `UnifiedToolbar.swift`: `prominentGlassButton()` já aplica `.glassProminent`
  com fallback para `.borderedProminent`, e `ToolbarSpacer(.flexible, placement: .primaryAction)`
  fica atrás de `#available(macOS 26.0, *)`.
- `CommandPaletteView.swift:101`: `.background(.regularMaterial, in: RoundedRectangle(...))`
  é o único material explícito em `Sources/`. Candidato direto a `glassSurface`.
- `AppSidebar.swift:76-77`: com paleta alternativa, pinta `theme.bgSidebar` e
  esconde o fundo da lista. No 26 isso cobre o vidro da sidebar flutuante, o que
  contraria a regra 6 [Inferido]. Decidir se as paletas tingem o conteúdo, e não
  a sidebar.
- `MoBaileApp.swift`: `.windowToolbarStyle(.unified)`. `ContentView` usa
  `NavigationSplitView` com inspector próprio (não `.inspector`), de modo que o
  inspector **não** recebe o vidro automático do sistema [Inferido].

---

## 4. Os quatro repositórios indicados

Clonados com `--depth 1` só para leitura. Nenhum script, build ou APK foi
executado. Os arquivos `SKILL.md`, `AGENTS.md`, `GEMINI.md` e `.cursorrules` das
skills trazem texto dirigido a IA (por exemplo, o `SKILL.md` da dickwu abre com
"You are two people at once: a senior design reviewer…"). Tratei como dado e
ignorei como instrução.

**dickwu/apple-design-skill** (commit 914b6a3, 15/10/2026). É uma skill de
revisão de design com 123 páginas do HIG convertidas em Markdown
(`references/hig/*.md`, com data da última mudança na Apple), mais um guia
curado `references/hig/liquid-glass.md` e um `code-audit.md` com padrões de uso
errado a procurar no código.
- *Aproveitar:* a lista do code-audit vira um checklist de revisão de PR.
  Exemplos: `glassEffect` em linhas de lista, cartões ou fundos; vidro aninhado
  sem container; `.clear` sobre texto; mais de 1 ou 2 `glassProminent` por tela;
  `toolbarBackground` opaco.
- *Não serve:* os números de blur, opacidade e saturação servem para imitar o
  vidro em Flutter, Electron etc., e o próprio arquivo diz que não são
  especificação. O item "Reduce Motion drops refraction" vale para imitação; o
  material real já faz isso.

**dpearson2699/swift-ios-skills**, skill `skills/swiftui-liquid-glass` (commit
8d90fd1, 31/07/2026). Tem `SKILL.md` com workflow, tabela de API, exemplos,
"Common Mistakes" e checklist, além de `references/liquid-glass.md` (462 linhas).
- *Aproveitar:* a ordem "`.glassEffect()` after layout and appearance modifiers";
  um `GlassEffectContainer` por grupo, sem aninhar; `.interactive()` só em
  controle real (nunca em badge de status); `.glassEffectTransition` no filho que
  entra ou sai, não no container; `.glass(_:)` quando precisar de tint ou `.clear`.
- *Não serve:* é escrita para iOS (gates `iOS 26`, toque). O exemplo `.clear`
  com cápsula preta a 0.28 é para mídia, coisa que o Mo baile não tem fora do
  espelho. Ela cita a doc da Apple via o espelho `sosumi.ai`; prefira
  developer.apple.com.

**Kyant0/AndroidLiquidGlass** (biblioteca "Backdrop" para Compose Multiplatform,
Apache-2.0, commit 65ab177, 26/08/2026). Reimplementa o vidro com shaders AGSL
ou SkSL sobre um "backdrop" capturado.
- *Como a lente funciona* (`backdrop/.../internal/Shaders.kt`, `effects/Lens.kt`):
  um SDF de retângulo arredondado dá a distância `sd` de cada pixel até a borda.
  Numa faixa de largura `refractionHeight` junto à borda, o deslocamento
  `d = circleMap(1 - |sd|/h) * refractionAmount` (perfil de calota circular)
  empurra a amostra de fundo ao longo do gradiente do SDF:
  `content.eval(coord + d*grad)`. O centro fica sem distorção e a borda curva a
  imagem como uma lente. Há uma variante com dispersão cromática (RGB separado)
  e efeitos de blur e cor em passes à parte.
- *Por que não reimplementar em SwiftUI:* o vidro do sistema já faz refração,
  adaptação claro/escuro, morphing, scroll edge e as três adaptações de
  acessibilidade. E o faz no compositor, inclusive amostrando o que está **fora**
  da view. Um `layerEffect`/Metal em SwiftUI só enxerga a própria camada, perde
  a acessibilidade automática e custa GPU a cada quadro. [Inferido]
  *Aproveitar:* só o entendimento, para explicar ao time o que o vidro faz.

**elysia395/dsh-wallpaper-engine** (MIT, commit 7ba44b2, 26/10/2026). É um
plugin Node/JS que põe wallpapers do Wallpaper Engine atrás da interface web do
chat "DSH", com um "liquid glass" em CSS (`backdrop-filter: blur(16px)
saturate(1.8) brightness(1.04)`) e presets (`lib/glass-presets/*.json`, entre
eles `factory-readable`).
- *Aproveitar:* a postura de produto. Existe um preset "legível"; diante de texto
  ilegível, a orientação é ajustar primeiro "暗化、边框与玻璃底色" (escurecimento,
  borda e base do vidro); e há o cuidado com `prefers-reduced-motion`.
- *Não serve:* é CSS web, sem relação com a API da Apple. Instaladores
  (`scripts/install-source.mjs`) e rede ficam de fora. Nada de código vai para o
  Mo baile.

---

## 5. Armadilhas conhecidas

1. **Ordem dos modificadores.** "Apply the `glassEffect(_:in:)` modifier after
   other modifiers that affect the appearance of the view". O efeito "captures
   the content to send to the container". [Doc: [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)]
   `glassEffect` antes de `padding`/`frame` deixa a cápsula do tamanho do texto,
   e não do controle.
2. **Vidro no conteúdo.** `glassEffect` em linhas de `List`/`Table`, cartões de
   relatório ou editor fere a regra 1 e custa um efeito por linha.
3. **Vidros soltos sem `GlassEffectContainer`** não se fundem nem fazem morph, e
   custam mais. "Creating too many Liquid Glass effect containers and applying
   too many effects to views outside of containers can degrade performance".
   [Doc: Applying] Vidros vizinhos em containers diferentes têm comportamento
   inconsistente ("glass can not sample other glass"). [Doc: WWDC25 323]
4. **`glassEffect` sobre `.background(material)`, ou dentro de item de toolbar
   ou de popover**, é vidro sobre vidro. Itens de toolbar já ficam numa cápsula;
   para separar, use `ToolbarSpacer(.fixed)` ou `.sharedBackgroundVisibility(.hidden)`.
   Não use outro `glassEffect`. [Doc: WWDC25 323; Inferido]
5. **Fundo próprio em sheet, popover e barra** (`presentationBackground`,
   `toolbarBackground`, cor atrás da sidebar) tapa o material e o scroll edge
   effect. [Doc: WWDC25 323; HIG Toolbars]
6. **`.containerConcentric` da WWDC não compila.** O SDK final usa
   `.rect(corners: .concentric)`. [SDK]
7. **`GlassButtonStyle(_:)` é macOS 26.1.** No 26.0, use a forma estática
   `.glass(_:)`. [SDK]
8. **`.interactive()`** na WWDC aparece como recurso de iOS. No SDK não há
   restrição de macOS, mas em superfície não clicável ele só confunde. [SDK; Doc]
9. **Captura de tela do vidro (`WindowSnapshotTests`)** [Exp]. Probe próprio
   (`/private/tmp/.../scratchpad/glasstest/main.swift`): janela 400×300 com
   listras vermelhas e azuis e um retângulo de vidro no centro. Medi o desvio
   padrão do canal R numa faixa de pixels dentro do vidro (listras puras ≈ 0,34):

   | Captura | sem efeito | `.regularMaterial` | `glassEffect(.regular)` |
   |---|---|---|---|
   | `CGWindowListCreateImage` | 0,339 | 0,005 (blur) | 0,072 (vidro visível) |
   | `cacheDisplay` em `host.view` | 0,341 | 0,156 (véu sem blur) | **0,341 (vidro some)** |
   | `cacheDisplay` no frame view | 0,341 | 0,156 | **0,341 (vidro some)** |

   **Conclusão:** `bitmapImageRepForCachingDisplay`/`cacheDisplay` **não
   renderiza o Liquid Glass**. Ele não sai opaco nem cinza: sai como se o vidro
   não existisse (a imagem fica idêntica à sem efeito; conferido visualmente nos
   PNGs). Com material, sai um véu translúcido sem blur, também errado. Só a
   captura do compositor (`CGWindowListCreateImage`) mostra o vidro. Nos testes,
   o caminho principal já é `CGWindowListCreateImage`, e o `cacheDisplay` é
   fallback: se ele for usado, a foto sai **sem vidro e sem aviso**. Recomendo
   falhar o teste (ou marcar a imagem) em vez de cair no `cacheDisplay`.
   Cuidado: `CGWindowListCreateImage` é `obsoleted` no macOS 15
   (`SCREEN_CAPTURE_OBSOLETE(10.5,14.0,15.0)`, "use ScreenCaptureKit"). Compila
   hoje só porque o alvo é o 14. Se o pacote subir para o 15, a troca é
   `SCScreenshotManager.captureImage(contentFilter:configuration:)` (macOS 14+)
   [SDK]. Se essa API pede permissão de Gravação de Tela para as janelas do
   próprio processo: [Não verificado].
10. **Vidro e janela inativa ou fora da tela.** O vidro é composto pelo
    WindowServer. Fotografar janela minimizada ou fora da tela tende a falhar
    [Inferido]; os testes já usam `makeKeyAndOrderFront` e esperam o run loop.

---

## 6. Mapeamento recomendado

| Superfície | API recomendada | Regra / observação |
|---|---|---|
| Toolbar da janela | nenhuma: `.toolbar` + `.windowToolbarStyle(.unified)`; grupos com `ToolbarSpacer(.fixed)`, separados com `.sharedBackgroundVisibility(.hidden)` | No máximo 3 grupos; sem `toolbarBackground`; sem `glassEffect` em item. [HIG Toolbars] |
| Sidebar | nenhuma: `NavigationSplitView` dá a sidebar flutuante | Não pintar `bgSidebar` nem esconder o fundo no 26; cor de paleta vai para o conteúdo. |
| Barra acessória / filtro sobre o conteúdo | `safeAreaBar(edge: .top)` (26) com controles padrão; `scrollEdgeEffectStyle(.hard, for: .top)` se for densa | É barra de conteúdo: material ou nada; sem vidro próprio, para não empilhar sob a toolbar. [Inferido + Doc Adopting] |
| Cápsula flutuante (ex.: controles sobre o espelho) | `glassSurface(in: Capsule())` dentro de `GlassGroup`; botões com `.buttonStyle(.glass)` | É o único lugar legítimo de vidro próprio; `.regular`; `.clear` só se ficar sobre o vídeo do aparelho, com escurecimento de 35% se o fundo for claro. |
| Popover | nenhuma (o sistema aplica) | Remover fundos e efeitos próprios do conteúdo do popover. [Doc Adopting] |
| Sheet | nenhuma | Sem `presentationBackground`. [Doc WWDC25 323] |
| Paleta de comandos (painel flutuante) | `glassSurface(in: .rect(cornerRadius: …))` no lugar de `.regularMaterial` | A lista interna fica sem vidro. |
| Splash | conteúdo: fundo da marca, sem vidro | Não é camada de navegação. [Inferido] |
| Cartão de destaque (Início, Relatório) | sem vidro: cor ou superfície do tema, ou `.regularMaterial` no 14/15 | "use standard materials… in the content layer". [HIG Materials] |
| Banner / faixa de aviso | sem vidro; cor semântica no conteúdo | Tint é para estado só em controle; banner é conteúdo. |
| Botão primário (Rodar) | `.buttonStyle(.glassProminent)` (já existe) | Um por tela, no lado trailing. [HIG Toolbars, Color] |
| Botões secundários flutuantes | `.buttonStyle(.glass)`; na toolbar, o estilo padrão | Não tingir. |
| Tabela, lista, árvore, editor de código, log | nenhum vidro | Regra 1; o scroll edge effect da toolbar já cuida da borda. [WWDC25 219] |
| Forma de controle dentro de contêiner | `ConcentricRectangle()` / `.rect(corners: .concentric)` (26); `RoundedRectangle` no fallback | Concentricidade. [Doc Adopting] |

## Fontes

- SDK: `MacOSX26.2.sdk` em `SwiftUICore.swiftinterface`, `SwiftUI.swiftinterface`,
  `AppKit/NSGlassEffectView.h`, `CoreGraphics/CGWindow.h` e
  `ScreenCaptureKit/SCScreenshotManager.h`.
- [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials) ·
  [HIG Color](https://developer.apple.com/design/human-interface-guidelines/color) ·
  [HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) ·
  [HIG Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) ·
  [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) ·
  [UIDesignRequiresCompatibility](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility)
- [WWDC25 219 Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) ·
  [WWDC25 323 Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- Repositórios: [dickwu/apple-design-skill](https://github.com/dickwu/apple-design-skill) ·
  [dpearson2699/swift-ios-skills](https://github.com/dpearson2699/swift-ios-skills) ·
  [Kyant0/AndroidLiquidGlass](https://github.com/Kyant0/AndroidLiquidGlass) ·
  [elysia395/dsh-wallpaper-engine](https://github.com/elysia395/dsh-wallpaper-engine)
