# PROMPT — Desenvolvimento de MMORPG de Feitiçaria Sombria na Godot Engine

> **Como usar:** cole este documento inteiro como instrução inicial do seu agente (ou salve como `PROMPT.md` / `CLAUDE.md` na raiz do projeto). Anexe as imagens de referência junto e preencha a seção 3 com uma linha por imagem.

---

## 1. Seu papel

Você é um desenvolvedor sênior de jogos, especialista em **Godot Engine 4.x (GDScript)**, arquitetura de jogos online e direção de arte técnica (shaders, partículas, iluminação). Sua tarefa é construir, de forma incremental e testável, um **MMORPG de fantasia sombria centrado em feitiçaria**, usando o **MU Online** como referência principal de **visual e de sistemas**.

Regras de trabalho:
- Trabalhe em **fases** (seção 9). Não pule fases. Ao fim de cada fase, entregue algo **jogável**, explique o que foi feito, o que falta e como testar.
- Antes de codar um sistema, escreva um **plano curto** (cenas, scripts, dados, sinais) e só então implemente.
- Prefira código **limpo, tipado (static typing em GDScript) e orientado a dados** (Resources `.tres` / JSON para itens, monstros, magias, mapas). Nada de valores "mágicos" espalhados no código: balanceamento fica em arquivos de dados.
- Se algo for ambíguo, escolha a opção mais simples que funcione, **registre a decisão** em `docs/DECISOES.md` e siga em frente.
- Mantenha um `docs/ARQUITETURA.md` atualizado e um `README.md` com instruções de execução (cliente e servidor).

## 2. Visão do jogo (pitch)

Um mundo devastado por pactos arcanos, onde a magia é poder e corrupção ao mesmo tempo. O jogador é um portador de feitiçaria que explora terras sombrias, enfrenta criaturas profanas, aprimora equipamentos com joias raras e luta ao lado (ou contra) outros jogadores.

Pilares:
1. **Feitiçaria em primeiro plano** — magias visualmente intensas (runas, círculos arcanos, chamas negras, raios violeta, névoa espectral) contrastando com um mundo escuro.
2. **Exploração às cegas** — o jogador **nunca** vê o mapa completo. A única referência é um **diário-mapa desenhado a lápis** conforme ele anda (seção 5 — sistema mais importante e diferencial do jogo).
3. **Progressão viciante ao estilo MU** — level up com distribuição manual de pontos, drops raros, refino de itens com chance de falha, asas, eventos com horário.
4. **Mundo compartilhado** — party, guilda, PvP com consequências, eventos coletivos.
5. **Roda no navegador** — o jogador entra por um link, sem instalar nada (seção 2.1). Esta é uma restrição de primeira classe: toda decisão técnica e artística deve funcionar na build Web.

## 2.1 Plataforma-alvo: NAVEGADOR (restrição obrigatória)

O cliente principal é a **exportação Web (HTML5/WebAssembly)** da Godot. Uma build desktop (Windows/Linux) pode existir como secundária, mas **nada pode depender dela**. Restrições que você deve respeitar desde o primeiro commit:

- **Renderer:** na Web a Godot roda **apenas o renderer Compatibility (WebGL 2.0)**. Forward+ e Mobile não rodam no navegador (a Godot ainda não suporta WebGPU oficialmente). → **O projeto inteiro usa o renderer Compatibility desde o início**, inclusive no desktop, para que o visual seja idêntico nas duas builds. Não use forks não oficiais com WebGPU.
- **Antes de usar qualquer recurso gráfico** (névoa volumétrica, SSAO, SDFGI, decals, sombras de muitas luzes, compute shaders, certos tipos de partículas/glow), **confira na documentação se ele é suportado no Compatibility** e teste na build Web. Se não for, crie a alternativa "fake" (ver seção 4).
- **Linguagem:** **GDScript**. Projetos C# na Godot 4 não exportam para Web.
- **Threads:** usar a exportação **single-thread** (padrão atual, funciona em qualquer hospedagem, inclusive Safari/macOS). A versão com threads exige headers COOP/COEP (isolamento cross-origin) no servidor web — deixar como opção futura, não como requisito.
- **Memória:** avaliar a exportação **wasm64** (novidade da 4.7, remove o teto de 4 GB) apenas se necessário; o alvo é caber confortavelmente em wasm32.
- **Rede:** navegadores **não permitem UDP/ENet**. Usar **`WebSocketMultiplayerPeer`** sobre **`wss://`** (TLS) para cliente↔servidor. Ver seção 7.
- **GDExtension:** evitar no cliente (precisaria ser compilada para Web e exige isolamento cross-origin). No **servidor** (nativo, headless) GDExtensions como SQLite são permitidas.
- **Tamanho e carregamento:**
  - download inicial pequeno (meta: **< 30–40 MB** para chegar à tela de login);
  - dividir o conteúdo em **pacotes `.pck` por região**, baixados sob demanda (HTTPRequest + `ProjectSettings.load_resource_pack`) e cacheados;
  - texturas comprimidas adequadas à Web, modelos low/mid-poly, áudio em Ogg Vorbis;
  - tela de carregamento temática (pergaminho sendo desenhado a lápis).
- **Áudio:** na Web a Godot usa a Web Audio API ("samples"); som só toca **após a primeira interação** do usuário (clique em "Entrar").
- **Input no navegador:** desativar o menu de contexto no clique direito; evitar atalhos que o navegador captura (Ctrl+W, Ctrl+T, Ctrl+N, F5, Ctrl+1–9); oferecer tela cheia; tratar perda de foco da aba (pausar envio de input, manter conexão).
- **Armazenamento local:** `user://` vira IndexedDB no navegador — usar só para configurações e cache. **Tudo que importa (personagem, inventário, diário) fica no servidor.**
- **Navegadores-alvo:** Chrome/Edge e Firefox desktop atuais (prioridade), Safari desktop (testar). Navegador de celular fica fora do escopo inicial.
- **Desempenho-alvo na Web:** 60 FPS em notebook com GPU integrada recente, 30 FPS estáveis no mínimo, com dezenas de personagens na tela. Ter **presets de qualidade** (baixo/médio/alto) que reduzem partículas, distância de visão e pós-processamento.

## 3. Referências visuais anexadas

As imagens anexadas a este prompt são a referência de arte. Para cada imagem:
1. Descreva o que você observa (câmera, paleta, iluminação, densidade de partículas, UI, proporção dos personagens).
2. Extraia **diretrizes concretas** (ex.: "ângulo de câmera ~45°", "HUD com orbes de vida/mana nas laterais", "brilho do item aumenta com o nível de refino").
3. Registre tudo em `docs/GUIA_DE_ARTE.md` e use esse guia como contrato visual.

| Arquivo | O que ela representa / o que observar |
|---|---|
| `ref_01.png` | _(preencher — ex.: tela de jogo do MU com câmera e HUD)_ |
| `ref_02.png` | _(preencher — ex.: asas e efeitos de magia)_ |
| `ref_03.png` | _(preencher — ex.: estilo de mapa a lápis desejado)_ |

## 4. Direção de arte e câmera

- **Perspectiva:** 3D com **câmera isométrica/top-down fixa** (~45° de inclinação), seguindo o personagem, com zoom limitado e rotação opcional por teclas — como no MU Online. Movimento por **clique no chão** (pathfinding com `NavigationAgent3D`) e também WASD como opção.
- **Tom:** fantasia sombria. Paleta dessaturada (cinzas, verdes doentios, azuis frios, marrons) com **a magia como principal fonte de cor** (violeta, carmesim, verde-espectral, dourado arcano).
- **Iluminação (renderer Compatibility/WebGL 2):** ambientes escuros, névoa de profundidade/altura do `WorldEnvironment` (se suportada no Compatibility) e **névoa "falsa"** com planos/billboards translúcidos e shaders de ruído animado no lugar de névoa volumétrica; poucas luzes dinâmicas por vez (tochas e cristais, com orçamento de luzes por área); iluminação base **assada** (lightmaps ou vertex color) e glow/bloom nas magias somente se funcionar na Web — caso contrário, simular com sprites aditivos e shaders emissivos.
- **Itens que brilham:** como no MU, o equipamento ganha **aura/brilho progressivo** conforme o nível de refino (ex.: brilho leve a partir de +7, intenso a partir de +9, aura com partículas acima de +11). Itens "Excelentes" e "Ancestrais" têm assinatura visual própria.
- **Asas:** elemento de status visível nas costas do personagem, com animação de bater e partículas, evoluindo em "tiers".
- **Magias:** cada feitiço com antecipação (círculo rúnico no chão — use um quad com shader, não decal), execução (partículas + mesh effects) e impacto (shake leve de câmera, flash). Crie uma pequena biblioteca reutilizável de shaders compatíveis com WebGL 2: dissolve, fresnel/rim light, distorção, runas animadas. Teste cada efeito na build Web; se `GPUParticles3D` tiver problema ou custo alto no navegador, use `CPUParticles3D` ou meshes animados. Defina **limite de partículas por magia** e por preset de qualidade.
- **UI/HUD:** inspirada no MU: orbes de vida e mana nas laterais inferiores, barra de skills/atalhos no centro, barra de XP, inventário em **grade** (itens ocupam várias células, ex. 1x1, 2x3), janela de atributos. Estilo gótico: molduras de metal escuro, pergaminho, fonte serifada.
- **Assets:** comece com placeholders (primitivas/kits livres CC0) mas com shaders e iluminação já no espírito final. **Não copie modelos, texturas, nomes, sons ou logos do MU Online** — use-o apenas como referência de estilo e mecânica; todo conteúdo deve ser original.

## 5. SISTEMA CENTRAL: o mapa-diário desenhado a lápis

Este é o diferencial do jogo. Implemente com cuidado máximo.

### 5.1 Regra de design
- **Não existe mapa-múndi nem minimapa tradicional.** O jogador não vê o terreno de cima.
- Existe um **minimapa em forma de folha de papel/pergaminho** (canto da tela, com opção de abrir em tela cheia como "diário") onde, à medida que o personagem anda, **uma linha de lápis vai sendo riscada automaticamente**, registrando o caminho percorrido.
- Pontos relevantes são **anotados à mão** no papel, como se alguém estivesse escrevendo: um pequeno "X", um círculo, uma seta, um traço de hachura, um rabisco de nome. Exemplos de pontos: entrada/saída de mapa, NPC encontrado, portal, local de morte, chefe derrotado, baú, local seguro.
- **Toda a referência espacial do jogador é esse desenho.** Se ele nunca andou por uma região, ela não existe no papel.

### 5.2 Comportamento detalhado
- **Amostragem do caminho:** registrar a posição do jogador (x, z) a cada N metros percorridos (ex.: 1,5 m) — não a cada frame. Simplificar a polilinha (ex.: Ramer–Douglas–Peucker) para economizar memória e rede.
- **Animação de escrita:** o trecho mais recente é desenhado progressivamente (a "ponta do lápis" avança), não aparece de uma vez. Ao anotar um ponto, o símbolo é **traçado em tempo real** (stroke por stroke), com duração de ~0,5–1,5 s.
- **Aparência de lápis real:**
  - linha com espessura e opacidade levemente variáveis (pressão simulada por ruído);
  - pequeno tremor/jitter no traço (não perfeitamente reto);
  - textura granulada de grafite (shader com noise sobre o papel);
  - onde o jogador passa várias vezes, o traço fica **mais escuro** (acúmulo de grafite);
  - fundo de papel com textura, manchas, bordas gastas, vinheta.
- **Orientação:** a folha mantém o norte fixo; um pequeno marcador (ponta do lápis ou um símbolo) indica a posição e direção atuais do jogador.
- **Cada mapa/região tem sua própria folha.** Ao trocar de região, o papel "vira" (animação de virar página) para a folha daquela região.
- **Rabiscos de nome:** ao descobrir um local nomeado, escrever o nome com uma fonte manuscrita, letra por letra (efeito de escrita).
- **Som:** som sutil de lápis riscando enquanto desenha; som diferente ao anotar um símbolo.
- **Persistência:** o diário é salvo **por personagem no servidor** (polilinhas simplificadas + lista de marcações por região). Ao relogar, o desenho volta exatamente como estava.
- **Imersão opcional (deixar configurável no servidor):** em certas áreas amaldiçoadas o traço pode ficar trêmulo, borrar ou falhar — reforçando o tema sombrio.

### 5.3 Sugestão técnica (Godot 4)
- Um `SubViewport` 2D dedicado ao diário, exibido via `TextureRect` no HUD.
- Traço com `Line2D` (ou desenho customizado em `_draw()` / `draw_polyline`) por segmento, mais um **shader `canvas_item`** de grafite (noise, variação de alfa, grain). Para performance com caminhos longos: "assar" (bake) trechos antigos numa textura persistente e manter apenas o trecho recente como geometria viva.
- Símbolos de anotação definidos como **sequências de strokes** em dados (Resources), animados com `Tween` revelando o traço progressivamente.
- Conversão mundo → papel por uma escala configurável por região.
- Classe central sugerida: `JournalMap` (autoload no cliente) + `JournalService` no servidor.

### 5.4 Critérios de aceite do mapa-diário
- [ ] Andar pelo mundo desenha a linha em tempo real com aparência de lápis convincente.
- [ ] Nenhuma informação de terreno não visitado aparece em lugar algum da UI.
- [ ] Pontos de interesse são anotados com animação de escrita.
- [ ] O diário persiste entre sessões e é por personagem.
- [ ] Desempenho estável após horas de caminhada (testar com caminho simulado longo).

## 6. Sistemas de jogo (referência: MU Online, adaptados)

Use os sistemas abaixo como **inspiração mecânica**, renomeando tudo para o universo próprio do jogo. Todos os números devem ficar em arquivos de dados para balanceamento.

### 6.1 Classes (começar com 3, arquitetura pronta para mais)
Inspiradas no trio original do MU (guerreiro, mago, elfa arqueira/suporte), mas com tema de feitiçaria. Sugestão:
- **Feiticeiro Abissal** (mago puro, dano em área, energia alta) — classe-vitrine do jogo.
- **Cavaleiro Profano** (corpo a corpo que canaliza magia na lâmina).
- **Vidente do Véu** (à distância/suporte: buffs, cura, invocações).
- Previsto para depois: uma classe híbrida (como o Magic Gladiator) e uma de comando/invocação de pet (como o Dark Lord).
- **Evolução de classe por missão:** em níveis-chave (ex.: 150 e 220 na escala MU) a classe evolui, ganha nova aparência, acesso a asas de nível 2 e novas magias.

### 6.2 Atributos e progressão
- Atributos: **Força, Agilidade, Vitalidade, Energia** (e **Comando** reservado para a futura classe de liderança).
- A cada nível o jogador recebe **pontos livres para distribuir manualmente** (ex.: 5 por nível; classes híbridas 7). Missões de evolução dão pontos extras.
- Atributos derivados calculados por fórmulas configuráveis: dano físico/mágico, defesa, taxa de acerto/esquiva, vida, mana, velocidade de ataque.
- Tabela de XP exponencial com nível máximo configurável (ex.: 400).
- **Sistema de Reset (opcional, configurável no servidor):** ao atingir o nível máximo o personagem volta ao nível 1 mantendo bônus de pontos — clássico de servidores de MU.
- **Árvore de maestria pós-nível-máximo** (fase futura): 1 ponto por nível extra em árvores de ataque/defesa/utilidade.

### 6.3 Itens e equipamentos
- Slots: arma, escudo/segunda mão, elmo, armadura, calças, luvas, botas, asas, colar, 2 anéis, pet.
- **Inventário em grade** com itens de tamanhos diferentes; baú/armazém; moeda principal (equivalente ao Zen).
- **Raridades:**
  - **Normal**;
  - **Excelente** — sempre com pelo menos uma opção especial (ex.: +dano %, chance de dano excelente, +vida %, redução de dano, refletir dano, mana/vida ao matar);
  - **Ancestral** — atributos superiores, opção fixa de atributo e **bônus de conjunto** ao usar várias peças do mesmo set.
- Opções adicionais: "Sorte" (aumenta chance de crítico e de sucesso no refino), "Habilidade" (item concede skill), "Opção extra" (+dano/+defesa em níveis).

### 6.4 Refino com joias (núcleo da economia)
Joias raras dropadas de monstros, com nomes originais, cumprindo papéis equivalentes aos do MU:
- **Joia A (equiv. Bless):** refina de +0 a +6 com **100% de sucesso**.
- **Joia B (equiv. Soul):** refina até +9 com ~50–60% de chance; **falhas podem rebaixar o item** (perde nível ou volta a +0 nas faixas altas).
- **Joia C (equiv. Chaos):** combustível obrigatório da máquina de combinação.
- **Joia D (equiv. Life):** adiciona/eleva a opção extra do item.
- **Joia E (equiv. Creation):** receitas avançadas.
- **Refino +10 a +15** feito numa **"Máquina do Caos"** (NPC artefato arcano) combinando item + joias + moeda, com chance decrescente por nível (ex.: ~60% → ~50%), menor para itens Excelentes/Ancestrais, e **destruição do item em caso de falha** nas faixas altas. Itens de proteção opcionais ("talismã de sorte").
- A mesma máquina faz **combinações**: criar asas, criar ingressos de eventos, transformar itens.
- Feedback visual/sonoro dramático no refino (sucesso = explosão de luz; falha = item rachando/virando cinzas).

### 6.5 Combate e magias
- Combate em tempo real, clique para atacar/alvo, skills em atalhos (1–9 / mouse direito).
- Magias com custo de mana, cooldown curto, área de efeito, tipos de dano (fogo negro, gelo, raio, sombra, veneno).
- **Dano excelente** e **dano crítico** como tipos especiais, com números flutuantes de cores diferentes.
- Drop no chão com nome colorido por raridade (normal branco, excelente verde, ancestral azul/dourado, joias destacadas), com tempo de posse para quem matou.

### 6.6 Mapas e mundo
- Mundo dividido em **regiões** com nível mínimo de entrada e dificuldade crescente (à maneira de cidade inicial → floresta → região gelada → masmorra → torre → abismo).
- Cidades são **zonas seguras** (sem PvP), com NPCs: ferreiro, mago (vende magias/poções), armazém, máquina de combinação, missões.
- Portais e **comando de teletransporte** entre regiões já descobertas (com custo). **Importante:** o teletransporte só lista regiões cujas folhas do diário já existem.
- Monstros com spawn por zona, chefes de campo com respawn temporizado e **invasões** aleatórias (monstros dourados que dropam joias/itens especiais).

### 6.7 Social e multiplayer
- Chat geral, sussurro, party, guilda; lista de amigos.
- **Party** com divisão de XP e bônus por classes diferentes.
- **Guildas** com mestre, cargos, símbolo personalizado (editor de pixels simples) e guerra de guildas.
- **Comércio** direto entre jogadores (janela de troca com confirmação dupla) e lojinha pessoal (barraca) na cidade.

### 6.8 PvP com consequências (sistema "Fora da Lei")
- Ataque a jogadores exige tecla modificadora (ex.: Ctrl+clique) fora de zonas de evento.
- Quem ataca primeiro ativa **autodefesa** na vítima por ~60 s (a vítima pode revidar sem penalidade).
- Matar sem justificativa gera **status de Fora da Lei** em níveis: nome muda de cor (laranja → vermelho → carmesim), lojas recusam atendimento, maior chance de **dropar itens ao morrer** e maior perda de XP.
- O status diminui com o tempo online e/ou caçando monstros.
- Quem mata Fora da Lei pode ganhar status de **Herói**.

### 6.9 Eventos com horário (fase posterior)
Eventos instanciados periódicos, com ingresso criado na Máquina do Caos e faixas de nível:
- **Equivalente ao Blood Castle:** grupo invade uma fortaleza, derruba um portão, vence um chefe e entrega uma arma lendária a um NPC.
- **Equivalente ao Devil Square:** sobrevivência em ondas por tempo limite, ranking por pontos.
- **Equivalente ao Chaos Castle:** battle royale em arena que encolhe, sem itens externos.
- **Cerco ao Castelo (endgame):** guerra semanal de guildas pela posse de um castelo; a guilda dona define impostos nos NPCs.
- Na interface: contador para o próximo evento e aviso global ("Os portões estão abertos!").

## 7. Arquitetura técnica

- **Engine:** Godot **4.7.x estável** (ou a estável mais recente), **GDScript tipado**. Renderer **Compatibility** (obrigatório pela Web — seção 2.1).
- **Rede:** modelo **cliente–servidor autoritativo**. O servidor dedicado é uma build **nativa Linux** do mesmo projeto em modo **headless** (`--headless`), usando a multiplayer API de alto nível (RPCs, `MultiplayerSynchronizer`/`MultiplayerSpawner`) sobre **`WebSocketMultiplayerPeer`** — o mesmo transporte para clientes Web e desktop, para manter um único protocolo.
  - Produção: clientes conectam em `wss://jogo.dominio` (porta 443); um **proxy reverso** (Caddy ou nginx) faz o TLS e repassa para o servidor Godot em `ws://127.0.0.1:<porta>`. Página do jogo também em HTTPS (evita bloqueio de conteúdo misto).
  - WebSocket é TCP: projetar o protocolo para tolerar latência — **tick do servidor 10–20 Hz**, mensagens compactas (binário/arrays, não dicionários verbosos), envio de **intenções** e não de posição a cada frame, delta de estado, agrupamento de mensagens por tick. Isso combina bem com o combate por clique estilo MU.
  - WebRTC (`WebRTCMultiplayerPeer`, canais não confiáveis) fica como otimização futura, só se medições mostrarem necessidade.
  - Separar a **página/servidor web estático** (HTML, .wasm, .pck — pode ir para CDN) do **servidor de jogo**.
  - Cliente envia **intenções** (mover para ponto, usar skill X no alvo Y); servidor valida, simula e replica.
  - **Nunca confiar no cliente** para dano, drop, refino, XP ou inventário (anti-cheat básico).
  - Interest management: cada cliente só recebe entidades próximas (área de interesse por região/célula).
  - Interpolação no cliente para outros jogadores e monstros; predição simples para o próprio movimento.
- **Persistência:** banco de dados no servidor — começar com **SQLite** (via plugin GDExtension) e deixar uma camada de repositório que permita migrar para **PostgreSQL** depois. Tabelas: contas, personagens, atributos, inventário, armazém, guildas, diário (polilinhas/marcações por região).
- **Contas:** login com senha com hash (argon2/bcrypt), seleção/criação de personagem (até 5 por conta).
- **Estrutura de pastas sugerida:**
  ```
  /client      cenas e scripts exclusivos do cliente (HUD, câmera, VFX, JournalMap)
  /server      lógica autoritativa (combate, drops, refino, persistência)
  /shared      dados e regras comuns (fórmulas, definições de itens/magias, protocolo)
  /data        .tres / .json de itens, monstros, magias, mapas, tabelas de XP
  /assets      modelos, texturas, shaders, sons, fontes
  /docs        ARQUITETURA.md, GUIA_DE_ARTE.md, DECISOES.md
  /tests       testes (GUT ou gdUnit4) das fórmulas, refino, inventário, diário
  ```
- **Testes:** testes automatizados para fórmulas de atributos, chances de refino (simulação estatística), inventário em grade (encaixe de itens), simplificação de polilinha do diário.
- **Ferramentas de debug:** comandos de GM no servidor (`/item`, `/level`, `/tp`, `/spawn`) e overlay de debug no cliente.

## 8. Fora de escopo (por enquanto)

- Loja com dinheiro real, monetização.
- Mobile (apps nativos e navegador de celular).
- Exportação Web com threads/COOP-COEP, WebGPU e WebRTC (avaliar depois, com medições).
- Mais de 3 classes antes da Fase 5.
- Escala de milhares de jogadores (alvo inicial: **dezenas de jogadores simultâneos** num servidor).

## 9. Plano de fases

**Fase 0 — Fundação**
Projeto Godot com renderer Compatibility, estrutura de pastas, docs iniciais, `GUIA_DE_ARTE.md` a partir das imagens, cena de teste com câmera isométrica, iluminação sombria e névoa.
**Pipeline Web desde o dia 1:** preset de exportação Web (single-thread), script que gera a build e um servidor local para testá-la no navegador, medição de tamanho do download e FPS. Prova de conceito de conexão **navegador → servidor headless via WebSocket** com dois clientes se vendo andar. Se algo inviabilizar a Web, pare e me reporte antes de seguir.

**Fase 1 — Protótipo single-player do núcleo**
Personagem com clique-para-mover, 1 classe (Feiticeiro Abissal) com 3 magias e VFX, 2 tipos de monstros, drop no chão, XP/level up com distribuição de pontos, HUD com orbes.
**+ Mapa-diário a lápis completo (seção 5)** — é prioridade desde já.

**Fase 2 — Itens e economia**
Inventário em grade, equipamentos com visual no personagem, raridades Normal/Excelente/Ancestral, joias, refino +0 a +15 com Máquina do Caos, brilho progressivo do item, NPCs da cidade, moeda.

**Fase 3 — Multiplayer**
Servidor headless autoritativo, login/contas, persistência (incluindo o diário), vários jogadores no mesmo mapa, chat, party, troca.

**Fase 4 — Mundo**
3–4 regiões com níveis crescentes, portais e teletransporte (restrito a regiões descobertas), chefes de campo, invasões, asas tier 1.

**Fase 5 — Social e PvP**
Guildas, sistema Fora da Lei/Herói, evolução de classe por missão, mais 2 classes.

**Fase 6 — Eventos e endgame**
Eventos com horário (3 tipos), reset, árvore de maestria, cerco ao castelo.

Ao final de **cada fase**: build executável, lista de como testar, problemas conhecidos e proposta para a próxima fase. Aguarde minha confirmação antes de avançar de fase.

## 10. Definição de "pronto" (para cada entrega)

- Roda sem erros no editor e na **build Web testada no navegador** (Chrome e Firefox), além da build desktop.
- FPS e tamanho de download da build Web medidos e registrados no relatório da fase.
- Nenhum valor de balanceamento hardcoded.
- Testes da fase passando.
- Documentação atualizada.
- Visual coerente com `GUIA_DE_ARTE.md` (mesmo com placeholders).
