# Arquitetura

## Visão geral

```
 Navegador (Web/WASM)   ─┐
 Desktop (Windows)      ─┼── WebSocket (ws:// local, wss:// em produção) ──► Servidor Godot headless
 Bots de teste          ─┘                                                   (mesmo projeto, -- --server)
```

O projeto é **um só**. O arquivo [main.gd](../main.gd) decide o papel pelo argumento de linha de comando:

| Papel | Como inicia | Nó raiz |
|---|---|---|
| Servidor | `--server` ou feature `dedicated_server` (export "Servidor Linux") | `GameServer` |
| Cliente | padrão | `client/client_main.tscn` |
| Bot de teste | `--bot` | `BotClient` |

## Autoloads (cliente e servidor)

- **`GameConfig`** ([shared/config/game_config.gd](../shared/config/game_config.gd)): carrega `data/config/*.json` e registra o Input Map a partir de `input.json`. É a única fonte de números de ajuste.
- **`Net`** ([shared/net/net.gd](../shared/net/net.gd)): cria o `WebSocketMultiplayerPeer` e concentra **todos os RPCs**. Assim o caminho `/root/Net` é igual nos dois lados, e o resto do código usa sinais em vez de RPCs espalhados.

## Protocolo (v1)

| Direção | RPC | Conteúdo | Observação |
|---|---|---|---|
| C → S | `rpc_hello` | versão do protocolo | o servidor recusa versão diferente |
| C → S | `rpc_move_to` | `Vector2` (x, z) | intenção: andar até um ponto; o servidor limita aos limites do mundo |
| C → S | `rpc_move_dir` | `Vector2` direção | intenção WASD; enviada só quando a direção muda |
| S → C | `rpc_welcome` | id do jogador e tick do servidor | |
| S → C | `rpc_snapshot` | tick, `PackedInt32Array` ids, `PackedFloat32Array` (x, z, yaw)×N | um envio por peer, por tick |

- Tick do servidor: **15 Hz** (`network.tick_rate_hz`), com passo fixo e limite de ticks por frame para não entrar em espiral.
- O snapshot é binário compacto ([shared/net/snapshot_codec.gd](../shared/net/snapshot_codec.gd)). Os ids ficam em int32 porque os peer ids da Godot passam de 2^24 e perderiam precisão em float32.
- **Cliente:** interpola as entidades com atraso de 120 ms (`movement.interpolation_delay_ms`). Ainda não há predição do próprio movimento (previsto para a Fase 3).
- **Servidor:** é a única autoridade sobre posição. Valida as intenções (valores finitos, direção normalizada, alvo limitado ao mapa).

### Próximos passos de rede (Fase 3)
- Interest management por células: `Net.send_snapshot` já envia por peer, então cada peer passa a receber só as entidades próximas.
- Delta de estado (enviar só o que mudou) e quantização (int16 para posições).
- Predição local com reconciliação.
- Login, contas e persistência (SQLite via GDExtension **só no servidor**, atrás de uma camada de repositório).

## Simulação do servidor (Fase 1)

```
GameServer (tick 15 Hz)
 ├ jogadores: ação atual (andar | conjurar | pegar) + WASD com deslize
 ├ SpellSystem   valida alcance/recarga/mana, agenda acertos (voo do projétil, antecipação da área)
 ├ MonsterSystem spawn por zona, IA (vagar → perseguir → atacar → voltar), respawn
 ├ DropSystem    sorteio por tabela, posse temporária, expiração, coleta validada por distância
 ├ JournalService diário (ver abaixo)
 └ NavGrid       A* numa grade XZ montada pelo WorldBuilder a partir da cena da região
Regras compartilhadas (shared/rules): StatCalculator (fórmulas Expression), Progression (XP), CombatRules (dano)
```

| Direção | RPC | Conteúdo |
|---|---|---|
| C → S | `rpc_cast` | magia, id do alvo, ponto, contínuo? |
| C → S | `rpc_pickup` / `rpc_add_stat` | drop / atributo e quantidade |
| S → C | `rpc_snapshot` | tick, ids, metas (tipo), (x, z, yaw, vida)×N |
| S → C | `rpc_player_state` | `PackedInt64Array` (índices em `Protocol.PS`), só quando muda |
| S → C | `rpc_cast_event`, `rpc_damage_event`, `rpc_attack_event`, `rpc_died_event`, `rpc_level_up_event` | efeitos visuais |
| S → C | `rpc_drop_spawned` / `rpc_drop_removed`, `rpc_cooldown`, `rpc_message` | |

Cliente: `client_main` (input → intenções, eventos → visual), `VfxPlayer` (efeitos), `Hud` (orbes, skills, atributos), `Avatar` (entidade interpolada) e `DropView`.

## Contas e persistência (Fase 3, protocolo v7)

```
conexão -> rpc_hello (versão) -> rpc_login (entrar/criar) -> rpc_login_result (lista de personagens)
        -> rpc_create_character / rpc_enter_world -> rpc_welcome (no mundo)
GameServer
 ├ AccountService     sessões por conexão, PBKDF2 no WorkerThreadPool, limite de tentativas, conta duplicada
 ├ GameRepository     interface neutra (Dictionaries) <- SqliteRepository (godot-sqlite, só no servidor)
 ├ CharacterCodec     ServerPlayer <-> registro (atributos, itens, diário)
 └ save_all()         ao sair, a cada autosave_interval_s e ao encerrar
Tabelas: accounts, characters, items (uid global; container 0 mochila, 1..12 equipado, 300 cofre), journals (JSON por região)
```

| Direção | RPC | Conteúdo |
|---|---|---|
| C → S | `rpc_login` | conta, senha, criar? (em produção sempre por wss://) |
| C → S | `rpc_create_character` / `rpc_enter_world` | nome / id do personagem |
| S → C | `rpc_login_result` | ok, mensagem, `[[id, nome, classe, nível], ...]` |
| S → C | `rpc_player_name` | id da entidade e nome do personagem, para todos |
| S → C | `rpc_kicked` | motivo antes de derrubar a conexão (o cliente não reconecta sozinho) |

Cliente: `LoginScreen` (conta e personagens), `AutoLogin` (bots, `--login`, reconexão) e a reconexão em `client_main` (tenta a cada `network.reconnect_delay_s`).

## Regiões (Fase 4, protocolo v10)

```
GameServer
 ├ regions: {id -> RegionInstance}   (data/world.json -> regions)
 │    RegionInstance: data, grid (WorldBuilder + RegionScenery.populate), monsters, drops, npcs,
 │                    safe, spatial, players
 ├ region_of(p) -> RegionInstance    (p.region_id; salvo no banco)
 ├ transfer_player(p, região, ponto)  portal | teletransporte | pergaminho | renascimento
 │    -> rpc_region_changed (antes dos snapshots), encoder zerado, journal.player_changed_region
 ├ _check_portals(p)                  a cada portal_check_interval_ticks
 └ InvasionSystem                     invasões douradas (events.json); chefes = monstros boss nos spawns;
                                      avisos por rpc_announce; MonsterCatalog gera as variantes douradas
cliente: rpc_region_changed -> _load_region (troca $World, NPCs, zonas, portais, grade da predição)
diário: rpc_journal_full da região nova -> virada de página; rpc_journal_sheets -> painel Viajar -> rpc_teleport
```

## Interesse, snapshots e predição (Fase 3, protocolo v9)

```
servidor, a cada tick:
  SpatialHash (células de interest_cell_m) <- jogadores + monstros vivos
  para cada jogador: query(raio + folga) -> SnapshotCodec.Encoder (do jogador) -> bytes -> rpc_snapshot
  eventos de combate: broadcast_near(posição) -> só quem enxerga
cliente:
  Net._decoder -> snapshot_received(tick, ids, metas, states)
  LocalPredictor: intenção (WASD/clique) -> ServerEntity + NavGrid locais -> posição do próprio avatar
                  snapshot do servidor -> reconcile(histórico em now - rtt) -> corrige se erro > limite
  ping a cada ping_interval_s (rpc_ping/rpc_pong) -> rtt usado na reconciliação
```

Formato do snapshot: `tick u32 | n u16 | (id s32, flags u8, [meta s32], [x s16, z s16, yaw u8, vida u8])×n`. `flags`: 1 = tipo, 2 = estado. Ver `shared/net/snapshot_codec.gd`.

## Social (Fase 3, protocolo v8)

```
GameServer
 ├ ChatService   geral | sussurro | grupo | sistema; limpeza do texto; flood (social.json)
 ├ PartySystem   convites, líder, estado 2x/s aos membros, divisão de XP (shares() é pura e testada)
 └ TradeSystem   Deal(a, b): ofertas no container 400, Pronto/Confirmar dos dois, simulação de espaço,
                 execução + save_characters([a, b]) numa transação; cancela por distância, morte ou saída
```

| Direção | RPC | Conteúdo |
|---|---|---|
| C → S | `rpc_chat` | canal (`Protocol.Chat`), alvo (sussurro), texto |
| C → S | `rpc_party_action` | `Protocol.Party` (INVITE, ACCEPT, DECLINE, LEAVE, KICK) e nome |
| C → S | `rpc_trade_action` | `Protocol.Trade` (REQUEST, ACCEPT, DECLINE, ADD_ITEM, REMOVE_ITEM, SET_CURRENCY, LOCK, CONFIRM, CANCEL), valor, nome |
| S → C | `rpc_chat_message` | canal, quem mandou, texto |
| S → C | `rpc_prompt` | convite de grupo ou pedido de troca (Aceitar/Recusar no cliente) |
| S → C | `rpc_party_state` | `[[id, nome, nível, vida, líder?], ...]` |
| S → C | `rpc_trade_state` / `rpc_trade_closed` | ofertas, Óbolos e as marcas de Pronto/Confirmar dos dois / motivo |

Cliente: `ChatBox` (no Hud), `PromptDialog`, `PartyFrame`, `TradeWindow` e o menu de clique em jogador (`client_main`).

### Cerco ao castelo (Fase 6, protocolo v18)

```
data/castle.json, scheduled_events.json -> cerco (logic siege), data/regions/castelo.json
GameServer
 ├ CastleSystem  owner_guild, tax_pct, treasury, registered (banco: tabela castles, versão 6)
 │               handle (Arauto: REGISTER, ENTER, SET_TAX, WITHDRAW), collect (imposto da loja), set_owner (fim do cerco)
 └ EventSystem   SiegeEvent: respawn_point (lado da guilda), can_damage_by (a dona não fere o portão),
                 capture_step (pura, testada), on_pvp_kill, finish -> castle.set_owner
Ganchos: _respawn_player -> events.respawn_point; ShopSystem.buy -> CastleSystem.tax_on + collect;
         GuildSystem.disband -> castle.on_guild_disbanded; PvpSystem: região pvp "guild"
```

| Direção | RPC | Conteúdo |
|---|---|---|
| C → S | `rpc_castle_action` | `Protocol.Castle` (REGISTER, ENTER, SET_TAX em milésimos, WITHDRAW) |
| S → C | `rpc_castle_state` | dono, símbolo, imposto, tesouro (só para o mestre dono), inscritas, taxa, a minha guilda |

### Reset e maestria (Fase 6, protocolo v17)

```
data/reset.json, data/mastery.json
GameServer
 └ MasterySystem  nodes (índice das árvores); bonuses_for / can_spend / reset_cost são puras e testadas
                  gain_xp (give_xp no nível máximo), spend, refresh (p.mastery_bonuses -> recompute), reset_check, do_reset
ServerPlayer: resets, master_level, master_xp, master_points, mastery {nó: pontos}, mastery_bonuses
PS (estado do jogador): RESETS, MASTER_LEVEL, MASTER_XP, MASTER_XP_NEXT, MASTER_POINTS
Banco (versão 5): characters.resets, master_level, master_xp, master_points, mastery (JSON)
```

| Direção | RPC | Conteúdo |
|---|---|---|
| C → S | `rpc_reset` | renascer (o servidor confere tudo) |
| C → S | `rpc_mastery_spend` | id do nó |
| S → C | `rpc_mastery_state` | `{nó: pontos}` |

### Eventos com horário (Fase 6, protocolo v15)

```
data/scheduled_events.json -> eventos (horário, faixas, regras); data/regions/fortaleza.json -> região de evento
GameServer
 └ EventSystem   Run por evento: IDLE -> OPEN (ingresso) -> RUNNING -> ENDING -> IDLE; relógio UTC (+ clock_offset)
     └ Instance  uma por faixa: RegionInstance(dados "fortaleza", id "fortaleza@1") em server.regions
         └ logic (dados: logic)  FortressEvent | ArenaEvent (ondas, pontos, ranking) | CircleEvent (anel, PvP livre)
             ganchos: on_enter / on_leave / start / update / on_kill / on_pvp_kill / on_altar / finish / cleanup / gm_skip
Ganchos: item event_ticket -> try_enter; transfer_player/logout -> on_left; damage_monster -> can_damage / on_monster_killed;
         NPC role event_altar -> on_altar; PvpSystem: região pvp:false
NavGrid.set_rect_solid + WorldBuilder.apply_blockers (dynamic_blockers) no servidor e na predição
```

| Direção | RPC | Conteúdo |
|---|---|---|
| S → C | `rpc_event_schedule` | `[[id, nome, estado, segundos], ...]` a cada 5 s e a cada mudança |
| S → C | `rpc_event_state` | painel do evento: title, line, extra, left_s, waiting, done, won, ring [x, z, raio] ({} = fora) |
| S → C | `rpc_event_world` | id do bloqueio que abriu (grade, portão) |

### Classes, invocações e missões (Fase 5, protocolo v14)

```
data/classes/index.json -> ordem e classe padrão; data/classes/<id>.json -> atributos, fórmulas, magias, evolução
GameServer
 ├ classes / calc_for(p) / points_per_level(p)   tudo por classe do personagem (p.class_id)
 ├ SpellSystem   by_class[classe] = magias; tipos projectile, melee, area, nova, chain, buff, heal, summon
 │               bônus em p.buffs (somados no recompute), vencem a cada 0,5 s -> rpc_buffs
 ├ SummonSystem  uma invocação por dono; segue, ataca, some (tempo, morte, saída, troca de região)
 └ QuestSystem   p.quests {id: {step, count} | {done}}; apply_kill / can_turn_in são puras e testadas;
                 on_monster_kill (grupo na região), on_boss_killed (item direto na mochila), evolve(p)
Banco (versão 4): characters.evolution, characters.quests (JSON)
```

| Direção | RPC | Conteúdo |
|---|---|---|
| C → S | `rpc_create_character` | nome e classe |
| C → S | `rpc_quest_action` | `Protocol.Quest` (ACCEPT, TURN_IN, ABANDON) e o id da missão (com a janela do NPC aberta) |
| S → C | `rpc_player_name` | id, nome, classe, evolução (reenviado ao evoluir) |
| S → C | `rpc_quest_state` | missões do próprio personagem |
| S → C | `rpc_buffs` | `[[nome, segundos], ...]` |

Snapshot: `KIND_SUMMON` (2) com o tipo = índice em `SummonSystem.summon_type_ids` (ordem das magias summon em `spells.json`). Cliente: `LoginScreen` (escolha de classe), `QuestWindow`, `Avatar.set_class_look` / `setup_summon`, efeitos `_slash` e `_aura_burst`.

### Guildas e amigos (Fase 5, protocolo v13)

```
GameServer
 ├ GuildSystem   guildas em memória (carregadas do banco ao abrir), cada mudança gravada na hora;
 │               cargos = índice em guilds.json -> roles; War(a, b, placar, meta, fim) só em memória
 │               PvpSystem: guerra = ataque justificado; on_kill -> war_kill (placar, sem infâmia)
 └ FriendSystem  amizade mútua; lista carregada ao entrar; avisa os amigos ao entrar e sair
Banco (versão 3): guilds(id, name, name_key, symbol, wins) | guild_members(character_id, guild_id, role) | friends(character_id, friend_id)
```

| Direção | RPC | Conteúdo |
|---|---|---|
| C → S | `rpc_guild_action` | `Protocol.Guild` (CREATE, INVITE, ACCEPT, DECLINE, LEAVE, KICK, PROMOTE, DEMOTE, TRANSFER, DISBAND, WAR_DECLARE, WAR_ACCEPT, WAR_DECLINE, SET_SYMBOL), alvo, extra (símbolo) |
| C → S | `rpc_friend_action` | `Protocol.Friend` (REQUEST, ACCEPT, DECLINE, REMOVE) e nome |
| S → C | `rpc_guild_state` | a própria guilda: nome, símbolo, cargo, vitórias, membros `[[nome, cargo, nível, classe, online?, região]]`, guerra |
| S → C | `rpc_player_guild` | guilda de um jogador (nome e símbolo sobre a cabeça), para todos |
| S → C | `rpc_friends_state` | `[[nome, online?, nível, classe, região], ...]` |
| S → C | `rpc_prompt` | agora com um terceiro campo (nome da guilda) para convite de guilda, guerra e amizade |

Símbolo: texto hexadecimal de 64 caracteres (8×8), um índice da paleta por pixel. Cliente: `SocialWindow` (G/F), `GuildSymbolEditor`, `GuildSymbol` (textura com cache) e `Avatar.set_guild`.

## Itens, NPCs e economia (Fase 2, protocolo v6)

```
GameServer
 ├ InventoryService  mochila 8x8, equipamento, cofre 8x10 (container 300), mesa da forja (200), pilhas
 ├ NpcSystem         NPCs da região por papel (shop | storage | vortex_forge): alcance, abrir, fechar ao se afastar
 ├ ShopSystem        compra/venda com preços de ShopRules
 ├ ForgeSystem       joia sobre item (RefineRules) e combinações da forja (RecipeBook)
 ├ ItemUseSystem     consumíveis: vida, mana, Pergaminho do Retorno, grimórios (magias aprendidas)
 └ SafeZones         cidade: sem aggro, sem dano a jogadores, sem magia
Compartilhado (shared/items): ItemCatalog, ItemCodec (11 ints), InventoryGrid, RefineRules, RecipeBook, ShopRules
```

| Direção | RPC | Conteúdo |
|---|---|---|
| C → S | `rpc_item_action` | ação (`ITEM_MOVE`, `AUTO`, `DROP`, `USE_ON`, `USE`), uid, destino, x, y |
| C → S | `rpc_npc_interact` / `rpc_npc_close` | id do NPC (o servidor anda até ele e abre) |
| C → S | `rpc_shop_buy` / `rpc_shop_sell` | índice no estoque e quantidade / uid |
| C → S | `rpc_forge_combine`, `rpc_gm` | |
| S → C | `rpc_inventory` | todos os itens do jogador (`ItemCodec`), quando mudam |
| S → C | `rpc_appearance` | equipamento visível de um jogador, para todos |
| S → C | `rpc_npc_opened` / `rpc_npc_closed`, `rpc_refine_fx` | o cliente escolhe a janela pelo papel do NPC nos dados da região |

As janelas do cliente (`InventoryWindow`, `ForgeWindow`, `ShopWindow`, `StorageWindow`) só pedem; o servidor valida tudo, inclusive se a janela do NPC está aberta e se o jogador ainda está perto.

## Mapa-diário a lápis

```
Servidor (autoritativo)                              Cliente
JournalService                                       JournalMap
 ├ amostra a posição simulada a cada 1,5 m ──point──► fila da ponta do lápis ─► GraphiteBrush
 ├ quebra o traço em saltos > 6 m                    (SubViewport 1024², NUNCA limpa: o
 ├ RegionJournal: simplifica blocos com RDP           traço fica "assado" na textura)
 ├ descobre marcos por proximidade ───────mark──────► símbolo traço a traço + nome letra a letra
 └ ao entrar: estado completo ─────────────full─────► redesenha a folha de uma vez
                                                     JournalView ×2 (minimapa e diário aberto, J):
                                                      shader de papel + grafite; overlay com
                                                      rótulos e a seta de posição
```

- **Por que no servidor:** o diário decide para onde o teletransporte pode levar (Fase 4) e precisa ser salvo por personagem (Fase 3). Ele vem da posição que o servidor simulou, nunca do cliente.
- **Custo constante:** o cliente não guarda geometria; cada trecho é desenhado uma vez numa textura que nunca é limpa. Passar de novo pelo mesmo lugar soma alfa, e o grafite escurece sozinho.
- **Determinismo:** o ruído do traço (pressão, tremor, ondulação) depende só da distância acumulada.
- **Dados:** `data/config/journal.json` (amostragem, aparência e UI), `data/journal/symbols.json` (símbolos como traços) e `data/regions/<id>.json` (escala da folha, tremor da tinta e marcos).
- **Medição:** 60 mil amostras (cerca de 5 h de caminhada) viram cerca de 17 mil pontos guardados, processados em cerca de 80 ms (teste automatizado).

## Produção (alvo)

```
Navegador ──HTTPS──► CDN / servidor estático (index.html, .wasm, .pck)
Navegador ──wss://jogo.dominio/ws──► Caddy/nginx (TLS, 443) ──ws://127.0.0.1:7777──► Godot headless (Linux)
```

Exemplo de Caddyfile:
```
jogo.dominio {
    handle /ws* { reverse_proxy 127.0.0.1:7777 }
    handle      { root * /srv/umbraheim/web; file_server }
}
```

## Renderização

- Renderer **Compatibility** em todas as builds, para que desktop e Web tenham o mesmo visual.
- Shaders em `assets/shaders/`, com ruído procedural compartilhado em `include/noise.gdshaderinc` (sem texturas).
- Névoa em duas camadas: a névoa de profundidade e altura do `Environment`, mais planos de névoa falsa com shader no lugar da névoa volumétrica (que não existe no Compatibility).

## Testes

`tests/run_tests.gd` é um executor mínimo: cada suíte tem métodos `test_*()` que retornam `""` (ok) ou a mensagem de falha. Hoje cobre o codec de snapshot e a validade dos arquivos de configuração.
