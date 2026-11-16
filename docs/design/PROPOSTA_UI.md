# Proposta de interface — Umbraheim

Proposta de design para menus, HUD e janelas. **Nada foi implementado no jogo**: este documento e os mockups em [mockups/](mockups/) servem para aprovação. Depois do "ok", a implementação segue o plano da seção 5, por partes.

- Mockups (abrir no navegador; só usam Google Fonts e imagens locais do projeto):
  - [mockups/login_selecao.html](mockups/login_selecao.html) — entrada e seleção de personagem (troque de tela e de classe pelos botões do topo);
  - [mockups/hud.html](mockups/hud.html) — HUD em jogo, com chat, aviso de evento, alvo e lista de eventos;
  - [mockups/inventario.html](mockups/inventario.html) — inventário com loja aberta ao lado, tooltip e item na mão;
  - [mockups/componentes.html](mockups/componentes.html) — kit de componentes: janela, botões e seus estados, abas, campos, diálogo, avisos.
- Capturas do estado atual em [img/](img/) (`atual_*.png`, tiradas em 2026-11-14 com `--quick-login`).

Contrato visual seguido: [GUIA_DE_ARTE.md](../GUIA_DE_ARTE.md) (paleta, ref_03 para o HUD, ref_04 para menus, ícones em losango, maiúsculas espaçadas e serifadas).

---

## 1. Diagnóstico geral

O que se vê no código (`client/ui/*.gd`) e nas capturas:

1. **Não há Theme compartilhado.** Não existe nenhum `.tres` de tema nem `gui/theme/custom` no `project.godot`. Cada janela cria o próprio `StyleBoxFlat` e repete as constantes `GOLD`/`PARCHMENT` (14 arquivos as declaram). Resultado: bordas, raios, margens e fundos diferem um pouco de janela para janela (inventário com borda 2 px marrom, login com borda violeta e raio 4, viagem com borda dourada...).
2. **Botões, campos, abas, barras de rolagem e tooltips são os padrões do Godot** (cinza-azulado, cantos arredondados). Há 39 `Button.new()` e só o chat e o editor de símbolo trocam os estilos de `normal/hover/pressed`. É isso que dá a sensação de "simples": o controle padrão do motor aparece no meio de um jogo sombrio.
3. **Uma só fonte, a padrão do Godot** (sans-serif genérica), em tamanhos soltos (10 a 30 px escolhidos em cada arquivo). Não há hierarquia tipográfica: título de janela, rótulo e valor usam a mesma família; o guia pede maiúsculas espaçadas e serifadas.
4. **Superfícies chapadas.** Painéis são retângulos pretos translúcidos com uma linha; não há textura, relevo, cantos ornamentados nem separadores desenhados. Nada lembra metal escuro ou pergaminho.
5. **Sem movimento nem som de interface.** Só o diário tem animação (virar página). Janelas aparecem e somem em um quadro; não há estado de hover/press visível na maioria dos elementos. De áudio de UI só existe `sfx/ui/fs488381_uihover1_wav.ogg`.
6. **Ícones improvisados.** Magias são uma letra num círculo colorido ("S", "C", "C"); itens são formas geométricas desenhadas por código. Funciona, mas é o ponto que mais "denuncia" protótipo.
7. **Texto de depuração na tela de jogo.** FPS, ping, tick e a linha de atalhos ocupam o canto superior esquerdo, justamente onde o guia põe o nome da região, e o título do diário fica por baixo deles.

### Por tela

| Tela | Captura | O que está fraco |
|---|---|---|
| Entrada (login) | [atual_login.png](img/atual_login.png) | A arte do nome é forte, mas o formulário é uma caixa genérica com borda violeta fina, campos e botões padrão do Godot. Frase de efeito pequena e cinza, sem peso. Não há fumaça, brasas nem nenhum movimento (o guia pede). |
| Seleção de personagem | (só código: `login_screen.gd`) | Lista de botões de texto, classes como três botões de alternância e uma descrição em 11 px. **Não mostra o personagem** nem atributos, e a tela não muda de cor com a classe (decisão do guia, ainda não aplicada). "Criar" e "Entrar no mundo" têm o mesmo peso visual. |
| HUD | [atual_hud.png](img/atual_hud.png) | Orbes são círculos chapados (vermelho e azul puros, sem vidro, sem moldura, sem líquido). Barra de magias fina, com 4 vagas vazias tão destacadas quanto as cheias. "Nível 1" solto acima da barra, XP quase invisível (barra de 6 px), contadores de poção "Z ×5" flutuando acima dos orbes. Botão "Mapa (M)" padrão. Eventos à direita em texto cru sem fundo, competindo com o cenário. |
| Atributos | [atual_status.png](img/atual_status.png) | Lista de texto plana; "+" em botão minúsculo; derivados (vida, dano, defesa) misturados com dados de conta (renascimentos, óbolos). Sem ícones nem agrupamento. |
| Inventário | [atual_inventario.png](img/atual_inventario.png) | A janela encosta na borda de baixo (a ajuda chega a y≈715 em 720) e cobre um terço da tela. Slots de equipamento com rótulos de 10 px cinza-escuro quase ilegíveis, sem silhueta do que vai ali. Grade sem moldura nem relevo. Instruções ocupam espaço fixo em vez de virar dica (tooltip). Moeda em texto simples. |
| Loja, cofre, forja, troca | (código) | Mesmo estilo do inventário, cada uma com o próprio `StyleBoxFlat`. Preço e botões de confirmação sem destaque; a troca não deixa claro, visualmente, quando o outro lado confirmou. |
| Maestria | [atual_maestria.png](img/atual_maestria.png) | Boa separação por cor (ataque, defesa, utilidade), mas é uma tabela de texto. Não há nós, progresso visual (0/10) nem ponto clicável evidente. Botão de fechar "×" padrão. |
| Diário / mapa | [atual_diario.png](img/atual_diario.png) | O pergaminho é a peça mais bonita da UI hoje. Problemas: o painel "Viajar" ao lado usa outro estilo (preto com borda dourada) e o título fica sob o texto de depuração. |
| Chat e log | (capturas) | Texto solto sobre o mundo, sem fundo; legível só sobre chão escuro. Linha de digitação padrão. Canais têm cores boas (já em `chat_box.gd`), mas sem rótulo de canal. |
| Avisos | (capturas) | Título de área e aviso de evento são `Label` com contorno preto; sem moldura nem entrada animada. |
| Grupo, guilda, amigos, cerco, missões, diálogos | (código) | Mesma linguagem: `PanelContainer` + `StyleBoxFlat` próprio + controles padrão. |

---

## 2. Direção visual

**Conceito: "relicário de ferro negro".** As janelas parecem placas de metal escurecido com filetes de ouro gasto; o conteúdo fica num fundo de couro/feltro quase preto; o que é mágico (seleção, item raro, magia pronta) brilha na cor da magia. Pergaminho só onde faz sentido narrativo (diário, missões, cartas de NPC). Original: nada de cantos em forma de dragão, asas ou brasões de outros jogos; os ornamentos são losangos, cravos e runas simples do próprio Umbraheim.

### 2.1 Cores (todas do guia)

| Token | Cor | Uso |
|---|---|---|
| `ink` | `#0B0B0D` | fundo base de painéis (92–96% de opacidade) |
| `iron` | `#1A1719` → `#0F0D10` | gradiente da placa da janela |
| `iron_edge` | `#3A3128` | filete externo escuro |
| `gold` | `#C9A24A` | títulos, filetes internos, losangos, valores |
| `gold_dim` | `#7A6533` | filetes secundários, texto desabilitado com destaque |
| `ember` | `#E07A2E` | hover, alertas, timers de evento |
| `bone` | `#D9D1BD` | texto principal |
| `bone_dim` | `#8F887A` | texto secundário, dicas |
| `blood` | `#D11A33` | vida, perigo, PvP |
| `frost` | `#5AB4FF` | mana |
| `void` | `#9E47FF` | Feiticeiro Abissal; seleção padrão |
| `spectral` | `#59FF8C` | Vidente do Véu; sucesso, "excelente" |
| `arcane` | `#E0B040` | joias, refino alto |

Cor de assinatura por classe (já decidida): Feiticeiro = `void`, Cavaleiro = `blood`, Vidente = `spectral`. Ela tinge a seleção de personagem e o **foco** (borda de slot selecionado, magia ativa) do personagem em jogo.

Raridade: manter `data/config/ui.json -> rarity_colors`; a proposta só acrescenta um brilho externo (glow) proporcional.

### 2.2 Tipografia (Google Fonts, licença OFL)

| Papel | Fonte | Detalhe |
|---|---|---|
| Títulos, nomes de janela, botões principais, nome de classe | **Cinzel** (OFL) | maiúsculas, espaçamento +0,14 a +0,25 em; 600/700 |
| Texto de interface, valores, chat | **Alegreya Sans** (OFL) | legível em 12–14 px; algarismos com bom desenho; 400/500/700 |
| Diário, missões, falas de NPC, lore | **IM Fell English** (OFL) | só em pergaminho, nunca em números de combate |

Escala fixa (no Theme, não por arquivo): 11 (dica), 13 (texto), 15 (destaque), 18 (título de janela), 24 (cabeçalho), 34 (aviso de evento), 44 (título de área). No Godot: `FontFile` com `antialiasing` padrão, `subpixel_positioning` desligado (Web), oversampling do projeto; Cinzel com **contorno de 1–2 px** quando fica sobre o mundo.

> As três fontes são OFL, licença que ainda não está na lista aceita (CC0, CC-BY, QAL). **Precisa de decisão** para entrar em `docs/DECISOES.md`. Alternativa sem OFL: nenhuma fonte serifada de qualidade é CC0; por isso a recomendação é aceitar OFL só para fontes.

### 2.3 Molduras e painéis

- **Janela padrão (`UmbraWindow`)**: placa com gradiente `iron`, filete externo 1 px `iron_edge`, filete interno 1 px `gold` a 35% inset 3 px, **losango dourado em cada canto** (4 px) e sombra externa preta 14 px. Barra de título com o nome em Cinzel, um separador fino que esmaece nas pontas e tem um losango no meio, e o fechar como losango com "×".
- **Poço (área de conteúdo, grades, listas)**: fundo `ink` mais escuro com sombra interna (borda superior mais escura que a inferior), dá relevo de "rebaixo".
- **Pergaminho**: reaproveita o papel do diário (`client/journal/`) para missões, cartas e diálogo de NPC.
- **Implementação**: StyleBoxTexture em 9-slice (textura de 48×48 com margens de 12 px) para a janela e o poço; StyleBoxFlat para o resto (separadores, barras, campos). A textura é **gerada por script** (ruído leve + filetes + losangos), sem depender de arte externa. Os mockups simulam isso com CSS (gradientes, `box-shadow` e pseudo-elementos).

### 2.4 Ícones em losango

- Magias, buffs, botões de sistema (inventário, atributos, guilda...) e classes usam **moldura em losango**: quadrado girado 45°, filete dourado, interior escuro, ícone no centro.
- Itens continuam em **células quadradas** (o inventário é por tamanho: 1×4, 2×3...); o losango aparece como selo de raridade/refino no canto.
- Ícones: silhuetas monocromáticas tingidas (game-icons.net, CC-BY 3.0), recoloridas pela cor da magia. Enquanto não houver ícones, o losango com a inicial já melhora muito.

### 2.5 Estados (todos os controles clicáveis)

| Estado | Visual | Som |
|---|---|---|
| normal | filete `gold_dim`, texto `bone` | — |
| hover | filete `gold`, texto branco-quente, brilho `ember` 25% por dentro, +1 px de "luz" no topo | hover (já existe) |
| pressionado | placa 1 px mais baixa, sombra interna, texto `gold` | clique (novo) |
| foco (teclado/gamepad) | contorno pontilhado de losangos `gold` | — |
| desabilitado | 45% de opacidade, sem brilho, cursor padrão | erro curto ao clicar (novo) |
| selecionado/alternado | borda na cor da classe + brilho suave pulsando (2,4 s) | — |
| recarga (magia) | varredura radial escura + segundos em Alegreya Sans 700 | "pronto" sutil ao terminar (opcional) |

### 2.6 Movimento

- **Abrir janela**: 140 ms, escala 0,96 → 1, opacidade 0 → 1, `EASE_OUT`/`TRANS_CUBIC`; os filetes dourados "acendem" (alpha 0 → 0,35) 80 ms depois. **Fechar**: 90 ms, só opacidade. Tudo por `Tween`, barato no Compatibility.
- **Aviso de evento**: desce 12 px e aparece em 250 ms; o separador se estende do centro para as pontas; fica 4 s; some em 400 ms.
- **Título de área**: letras em Cinzel com espaçamento que encolhe de 0,5 em para 0,25 em em 600 ms (efeito de "assentar"), e some depois de 3 s.
- **Orbes**: líquido com onda lenta (shader de CanvasItem) e um "solavanco" de 120 ms ao perder vida.
- **Login/seleção**: fumaça (shader de ruído em `ColorRect`) e brasas (`CPUParticles2D`, já previsto no guia). Na troca de classe, a tinta do fundo faz transição de 500 ms.
- Regra: nada passa de 300 ms em ação frequente (inventário, troca de aba).

### 2.7 Sons

Já existem: `assets/audio/sfx/ui/fs488381_uihover1_wav.ogg` (hover). Em outros grupos, `fs554791_mage_teleport_skill.ogg` serve para "subiu de nível/maestria", `kenney_drawknife1.ogg` para equipar arma e `fs871710_sound_design_impact_1.ogg` (baixo volume) para o aviso de evento. Faltam: clique, abrir/fechar janela, pegar/soltar item, moedas, erro e "missão concluída" (lista na seção 6). Os sons ficam no `UiSound` (um `AudioStreamPlayer` no bus "UI", com volume em `data/config/ui.json`).

---

## 3. Proposta por tela

### 3.1 Entrada e seleção ([mockup](mockups/login_selecao.html))

**Entrada**
- Mantém a arte larga/vertical atual de fundo (é a identidade). Por cima: névoa animada na faixa de baixo e brasas subindo devagar.
- Formulário centralizado embaixo, numa **placa estreita** (360 px) com cantos em losango. A frase "o caminho só existe no seu diário" vira subtítulo em IM Fell English itálico, `bone_dim`.
- Campos: fundo `ink`, filete inferior dourado que acende no foco, rótulo em Cinzel 11 px espaçado acima.
- "Entrar" é o **botão principal** (placa com brilho `ember` no hover); "Criar conta" é secundário (só contorno). Status ("Conectando…") com um losango girando ao lado.
- Rodapé discreto: versão e servidor em 11 px.

**Seleção de personagem** (inspirada no modelo da ref_04, com layout nosso)
- Fundo: preto com fumaça e brasas, **tingido pela cor da classe** do personagem destacado.
- Centro: o **modelo 3D da classe** (o mesmo `ModelRig` do jogo num `SubViewport` transparente), girando devagar, sobre um círculo rúnico no chão (o shader `rune_circle` já existe).
- Esquerda: atributos em caixas pequenas (Força, Agilidade, Vitalidade, Energia), valores em `gold`, e uma descrição curta da classe.
- Direita: os personagens da conta como **cartões** (nome, classe, nível, evolução), com losango na cor da classe; um cartão "+ Novo personagem" no fim.
- Embaixo, no centro: o nome da classe em Cinzel grande com setas ‹ › (só no modo criar); embaixo à direita, "Entrar no mundo" (principal); à esquerda, "Sair" e "Apagar" (perigo, pede confirmação).
- Criar: o mesmo layout; os cartões dão lugar ao campo de nome e as setas trocam a classe (e a cor do fundo).

### 3.2 HUD ([mockup](mockups/hud.html))

- **Barra inferior centralizada** (guia/ref_03): placa de metal de ~760 px com orbes nas pontas, em **anéis de metal com 4 cravos** e vidro (reflexo curvo no topo).
  - Orbe de vida `blood` à esquerda, mana `frost` à direita, valor "60 / 60" dentro em Alegreya Sans 700 com contorno.
  - Poções viram **dois losangos pequenos colados ao orbe** (tecla Z/X + quantidade), em vez de texto flutuando.
- **9 vagas de magia**: quadrados com cantos chanfrados, tecla num losango no canto superior esquerdo, recarga em varredura radial. A selecionada ganha borda na cor da classe e brilho. Vagas vazias ficam **apagadas** (só o rebaixo, sem filete), para não competir.
- **Nível** num losango no centro, logo acima da barra, sobre a **barra de XP** (agora com 8 px, segmentada em 10, com brilho dourado na ponta que avança).
- **Botões de sistema** (inventário, atributos, diário, guilda, amigos, maestria) como losangos pequenos à direita da barra, com a tecla no tooltip. Substituem a linha de atalhos de texto.
- **Canto superior esquerdo**: nome da região em Cinzel com subtítulo (zona segura etc.) — no lugar onde hoje está o texto de depuração, que passa para F3 (só debug).
- **Topo central**: quadro do alvo (nome em `blood` claro, nível, barra de vida fina com moldura). Abaixo dele, quando houver, o **aviso de evento** com moldura própria.
- **Direita**: lista de eventos numa placa recolhível (título "EVENTOS", cada linha com losango de status: cinza = fechado, `ember` = abre em breve, `spectral` = aberto).
- **Buffs**: losangos de 28 px acima do orbe de vida, com tempo restante embaixo.
- **Grupo** (party_frame): coluna à esquerda, abaixo da região; cada membro com retrato em losango (cor da classe), barra de vida e de mana finas.

### 3.3 Inventário e loja ([mockup](mockups/inventario.html))

- Janela padrão com título "INVENTÁRIO", colada à direita, **limitada à altura da tela** (nada passa de `viewport - 150 px`; com 8×8 células de 34 px cabe com folga em 720p).
- **Boneco**: os slots de equipamento ganham uma **silhueta-guia** desenhada (elmo, arma, anel…) em `gold_dim` a 25% e o nome aparece só no tooltip. Atrás deles, a silhueta vaga do personagem em linha fina.
- **Grade**: poço com células de rejunte fino; itens com fundo na cor da raridade a 12%, borda da raridade e, a partir de +7, brilho pulsante (já existe a lógica; só muda o desenho).
- Item na mão: segue o mouse com 85% de opacidade e uma sombra; a área de soltura mostra verde/vermelho como hoje, mas com borda tracejada.
- **Rodapé**: moeda (óbolos) com ícone de moeda e valor em `arcane`; as instruções saem da janela e viram tooltip do botão "?" no título.
- **Tooltip** de item: placa estreita com o nome na cor da raridade em Cinzel, tipo/requisitos em `bone_dim`, opções excelentes em `spectral`, separadores com losango, preço no fim. Requisito não atendido em `blood`.
- **Loja** (abre à esquerda do inventário, mesmo estilo): abas por categoria em losangos, prateleira em grade, preço sob cada item; "clique de novo para vender" vira um botão de confirmação dentro do tooltip.
- **Cofre** e **forja** reaproveitam o mesmo poço/grade; a forja ganha um círculo rúnico atrás das vagas de combinação, com a porcentagem de sucesso no centro em Cinzel.
- **Troca**: duas colunas espelhadas (você | outro) com selo "CONFIRMADO" em `spectral` sobre a coluna de quem já aceitou, e o botão final só acende quando os dois confirmam.

### 3.4 Outras janelas

- **Atributos**: cabeçalho com classe e nível; os 4 atributos em linhas com ícone em losango, valor grande e o "+" como losango `ember` que pulsa quando há pontos livres. Derivados num segundo bloco (2 colunas). Renascer/maestria como botões no rodapé.
- **Maestria**: três colunas viram **três trilhas verticais** de nós em losango (cor da trilha), com barra de progresso fina embaixo de cada nó (0/10). Nó com ponto disponível brilha; clique abre confirmação.
- **Missões**: pergaminho (o papel do diário) com título em IM Fell English e objetivos com caixinha em losango que se preenche.
- **Guilda e amigos**: abas em losango; listas com linhas alternadas sutis, ponto de presença (verde online, cinza offline), símbolo da guilda num quadro de metal.
- **Cerco**: placa com o castelo dono no topo, imposto atual grande e cronômetro em `ember`.
- **Viajar (teleport_panel)**: passa a usar o estilo do pergaminho do diário, ao lado da página, para ficar coerente.
- **Diálogo (prompt_dialog)**: janela pequena centralizada, escurecendo o fundo a 40%; botão de confirmação principal à direita, cancelar à esquerda; ação perigosa (apagar, largar item caro) usa o botão de perigo `blood`.

### 3.5 Chat e log

- Caixa no canto inferior esquerdo com **fundo `ink` a 55%** que some junto com as linhas (o fade já existe); ao digitar, o fundo vai a 85% e aparece a moldura.
- Cada linha com **etiqueta de canal** curta e colorida: `[G]` geral, `[Gr]` grupo, `[Gu]` guilda, `[S]` sussurro, `[!]` sistema (as cores atuais continuam).
- Linha de digitação com o canal atual num losango à esquerda (clicar troca o canal).

### 3.6 Avisos

- **Aviso de evento** (topo central): placa larga e baixa, título em Cinzel 22–34 px `ember` com contorno, subtítulo em `bone`, separador com losango. Entrada animada (2.6).
- **Título de área**: Cinzel 44 px, sem placa, só contorno e uma sombra larga; separador fino embaixo.
- **Toasts** (item obtido, missão atualizada, amigo entrou): pilha à direita, acima da lista de eventos, cada um com ícone em losango; somem em 4 s.
- **Morte**: tela escurece com vinheta vermelha, "VOCÊ CAIU" em Cinzel, cronômetro de retorno.

---

## 4. Princípios técnicos (Godot 4.7, Compatibility, Web)

- Um único **`Theme`** aplicado em `gui/theme/custom` do projeto: todo `Button`, `LineEdit`, `PanelContainer`, `TabBar`, `ScrollBar`, `TooltipPanel`, `ProgressBar` e `Label` herda o visual. As janelas passam a usar **variações de tipo** (`theme_type_variation`: `WindowPanel`, `WellPanel`, `PrimaryButton`, `DangerButton`, `DiamondButton`, `TitleLabel`, `HintLabel`…), em vez de `add_theme_*_override`.
- Paleta e tamanhos ficam em `data/config/ui.json -> theme` (regra do projeto: nada de valor solto no código). Um `UiPalette` (classe estática) lê dali e substitui as 14 cópias de `GOLD`/`PARCHMENT`.
- O `Theme` é **gerado por código** (`UiThemeBuilder.build() -> Theme`) a partir da paleta e das texturas, e salvo como `client/ui/theme/umbra_theme.tres` por uma ferramenta (`tools/build_ui_theme.gd`, rodada no `--headless`). Assim a fonte da verdade é o JSON e o `.tres` só é cache versionado.
- Texturas de 9-slice **geradas** (`tools/gen_ui_art.gd`, `Image` + `FastNoiseLite`) em `client/ui/theme/tex/`: placa, poço, botão (3 estados), losango (3 tamanhos), separador, anel do orbe. Pequenas (≤ 128 px), importadas como 2D **sem mipmaps, filtro linear, sem compressão VRAM** (é UI). Depois de criar: `python -I tools/update_export_filter.py` (se o filtro cobrir `client/`) e conferir o console da build Web.
- Shaders de CanvasItem (orbe, fumaça, varredura de recarga, brilho de raridade) são simples e funcionam no GLES3/WebGL2. Evitar `SCREEN_TEXTURE` (custa caro na Web); blur do fundo **não** é proposto.
- `UiSound` como autoload só do cliente (o servidor headless não carrega).
- O cliente gráfico compila scripts que os bots e testes não carregam: depois de cada parte, rodar o cliente com captura (`--quick-login --screenshot=...`) para pegar erros de tipo.

---

## 5. Plano de implementação

Cada parte entrega algo visível e pode ser aprovada separadamente. Esforço em dias de trabalho do agente (aproximado); risco = chance de retrabalho ou problema técnico.

| # | Parte | O que entra | Esforço | Risco |
|---|---|---|---|---|
| A | **Fundação** | `ui.json -> theme` (paleta, tamanhos), `UiPalette`, fontes em `assets/fonts/` com `OFL.txt`, `UiThemeBuilder` com StyleBoxFlat para Button/LineEdit/Panel/Tab/Scroll/Tooltip/ProgressBar, aplicado em `gui/theme/custom`. Remove as constantes duplicadas. | 1–1,5 | **Baixo**. Muda tudo de uma vez, mas é só visual; o risco é algum `add_theme_*_override` antigo brigar com o tema (resolvido ao migrar cada janela). |
| B | **Texturas geradas e 9-slice** | `tools/gen_ui_art.gd` → placa, poço, botões, losangos, separador, anel; StyleBoxTexture no Theme; ajuste de margens. | 1,5 | **Médio**. 9-slice mal calibrado borra em 125%/150% de escala; testar em 1280×720 e 1920×1080 e na Web. |
| C | **Componentes** | `UmbraWindow` (título, fechar, arrastar, animação de abrir/fechar, som), `DiamondButton`/`DiamondSlot`, `RichTooltip`, `UiSound`. | 1,5 | **Baixo**. |
| D | **HUD** | Barra nova, orbes com shader (líquido + vidro), poções em losango, XP segmentada, botões de sistema, região no canto, alvo e aviso de evento com moldura, eventos em placa, buffs em losango, debug só no F3. | 2–3 | **Médio**. É a tela mais vista; `is_over_ui` e os cliques precisam continuar certos; desempenho do shader na Web. |
| E | **Entrada e seleção** | Fumaça (shader) e brasas, formulário novo, seleção com cartões, atributos, tinta da classe, modelo 3D da classe em `SubViewport` com `ModelRig`. | 2–3 | **Médio/alto**. O `SubViewport` 3D na tela de login carrega modelos antes de entrar no mundo (tempo de carga e memória na Web); plano B: retrato 2D pré-renderizado por classe (gerado com o `model_lineup`). |
| F | **Inventário e janelas de NPC** | Inventário (silhuetas, grade em poço, tooltip rico, rodapé), loja, cofre, forja, troca no mesmo kit. | 2–2,5 | **Médio**. Muito desenho custom em `_draw()`; manter os retângulos de clique idênticos aos desenhados. |
| G | **Demais janelas** | Atributos, maestria (trilhas), missões (pergaminho), guilda/amigos (abas), cerco, viajar, diálogo, grupo. | 2 | **Baixo**. Em grande parte é trocar overrides por variações do tema. |
| H | **Chat, avisos e toasts** | Fundo do chat, etiquetas de canal, avisos animados, título de área, toasts, tela de morte. | 1 | **Baixo**. |
| I | **Ícones e sons** | Ícones de magias e itens (game-icons.net, tingidos), sons de UI que faltam, créditos (`tools/asset_reports.py`). | 1,5–2 | **Médio**. Depende da escolha e aprovação de assets; CC-BY exige créditos visíveis. |

Ordem sugerida: **A → B → C → D**, apresentar; depois **F → E → G → H → I**. Total estimado: 15–18 dias.

Critérios de aceite por parte: captura antes/depois em `docs/design/img/`, build Web aberta sem "No loader found" no console, testes (`.\tools\run_tests.ps1`) verdes e o cliente gráfico compilando sem erro de tipo.

---

## 6. Assets necessários (não baixados)

Licenças: CC0, CC-BY e QAL já aceitas; **OFL precisa ser aceita para as fontes**.

| Asset | Fonte | Licença | Uso |
|---|---|---|---|
| Cinzel (variável, 400–900) | Google Fonts | OFL 1.1 | títulos, botões |
| Alegreya Sans (400, 500, 700, itálico 400) | Google Fonts | OFL 1.1 | texto de interface, chat |
| IM Fell English (normal e itálico) | Google Fonts | OFL 1.1 | diário, missões, falas |
| Ícones de magias, atributos, sistema, itens | game-icons.net (vários autores: Lorc, Delapouite, Skoll…) | CC-BY 3.0 | silhuetas SVG tingidas nos losangos e células |
| Interface Sounds (cliques, abrir/fechar, erro) | Kenney | CC0 | sons de UI que faltam |
| RPG Audio (moedas, couro, metal: pegar/soltar item, comprar) | Kenney | CC0 | inventário, loja, troca |
| (opcional) Fantasy UI Borders | Kenney | CC0 | só como referência de proporção de 9-slice; a proposta gera as texturas por script |
| (opcional) textura de metal escovado/couro escuro em 256 px | ambientCG ou Poly Haven | CC0 | grão sutil na placa da janela, se o ruído gerado não bastar |

Nada disso é imprescindível para as partes A–C: elas usam só fontes e texturas geradas. Ícones e sons entram na parte I.

---

## 7. Pendências e decisões para o usuário

1. Aceitar **OFL** para fontes (registrar em `docs/DECISOES.md`).
2. Seleção de personagem com **modelo 3D ao vivo** ou **retrato pré-renderizado** (custo na Web).
3. Mostrar a **cor da classe** também no HUD (borda do slot selecionado, anel dos orbes) ou só na seleção.
4. Esconder o **texto de depuração** atrás do F3 também nas builds de teste.
5. O que não foi verificado: a tela de seleção de personagem, a loja/cofre/forja/troca, guilda/amigos (o `--open-guild` não abriu nada sem guilda) e o cerco foram analisados **só pelo código**; os mockups usam CSS e não medem o custo real dos shaders na Web.
