# Umbraheim — instruções para o agente

O jogo se chama **Umbraheim** (antes, "Feitiçaria Sombria"; a pasta do projeto manteve o nome antigo). Arte do nome em `client/ui/art/`.

A especificação completa do projeto está em [docs/PROMPT.md](docs/PROMPT.md). Ela é o contrato: leia antes de qualquer trabalho.

Resumo das regras que mais importam no dia a dia:
- Godot 4.7.x, **GDScript tipado**, renderer **Compatibility** (a build Web é a plataforma principal).
- Rede: `WebSocketMultiplayerPeer`, servidor autoritativo headless; o cliente só envia intenções.
- Nenhum valor de balanceamento no código: tudo em `data/`.
- Trabalhar por fases; ao fim de cada fase, entregar algo jogável e **esperar a confirmação** antes de avançar.
- Decisões em [docs/DECISOES.md](docs/DECISOES.md); arquitetura em [docs/ARQUITETURA.md](docs/ARQUITETURA.md); contrato visual em [docs/GUIA_DE_ARTE.md](docs/GUIA_DE_ARTE.md).
- O MU Online é só referência de estilo e mecânica: todo nome, modelo, som e texto deve ser original.

Comandos (PowerShell, na raiz do projeto):
- Testes: `.\tools\run_tests.ps1`
- Servidor + 2 clientes no desktop: `.\tools\run_local.ps1`
- Build Web: `.\tools\build_web.ps1`, depois `python tools/serve_web.py`

Estado atual: **todas as fases do plano concluídas (Fase 6 aceita).** Eventos com horário (Fortaleza Sitiada, Arena das Ondas, Círculo que Encolhe), reset, maestria e cerco ao castelo com impostos. É a última fase do plano em docs/PROMPT.md. Depois dela, a biblioteca de assets e a aplicação dos assets no jogo (mundo, personagens e monstros, efeitos) também foram aceitas (2026-11-13). O redesenho de interface e ambientação (`docs/design/`, partes A–I e 1–6) foi aceito em 2026-11-16. Relatórios em [docs/FASES.md](docs/FASES.md).

Notas dos assets no jogo (parte 1, mundo):
- Materiais do mundo em `client/world/materials/*.tres`. Texturas 3D: VRAM, mipmaps, até 512 px (normal: 256, `compress/normal_map=1`). O `--import` headless não detecta uso 3D: ajuste o `.import` à mão.
- `RegionScenery`: modelos (`MODELS`) só fora do headless, cobrindo as primitivas, que ficam como colisão. Não use o rng para escolher a variante.
- Depois de usar um asset novo de `assets/`, rode `python -I tools/update_export_filter.py` (senão ele fica fora da build).
- Licenças aceitas: CC0, CC-BY, QAL (Quaternius) e, só para fontes, OFL (Google Fonts, com o OFL.txt junto). Créditos: `python -I tools/asset_reports.py`.

Notas dos assets no jogo (parte 2, personagens e monstros):
- Modelos animados em `data/config/models.json` (seção `models` do GameConfig), montados por `ModelRig` (`client/entities/model_rig.gd`) dentro do `Avatar`. Monstro: `model` em `monsters.json`; classe: `models.json -> classes`.
- KayKit: animações só em `Skeleton_Minion.glb` (`anims: "kaykit"`); modelo KayKit novo = `.import` com `animation/import=false`. Imp/Puglin: `anims: "ual"`.
- Para conferir: `scenes/dev/model_lineup.tscn` (`--state=`, `--only=`, `--golden`, `--die`).
- Material único em todas as peças (dourado, invocação): use `Avatar._override_all`, que limpa os materiais por superfície (com os dois, o Compatibility perde o material).

Notas dos assets no jogo (parte 3, efeitos):
- Partículas: `VfxPlayer._particles(..., shape)` com o tipo de `vfx.json -> particle_shapes` (texturas da Kenney). Morte: dissolução (`Avatar._dissolve_materials`, `vfx.json -> dissolve`). Aura: `aura` em `monsters.json` + `vfx.json -> auras`. Portal: `portal_dither.gdshader` + `vfx.json -> portal`.
- Nos shaders, `INSTANCE_CUSTOM` só existe no `vertex()`: passe para o `fragment()` por `varying`.
- Depois de exportar, abra a build Web e veja o console: um asset fora do filtro só aparece lá ("No loader found").

Notas do redesenho (interface e ambientação, propostas em `docs/design/`):
- Tema: `ui.json -> theme` (paleta em hex, fontes, tamanhos, moldura). Use `UiPalette.c("gold")` etc., nunca `Color(...)` fixo. `UiThemeBuilder.install()` mescla no tema padrão (o tema da janela raiz não chega a CanvasLayer).
- Painéis: `theme_type_variation = &"WindowPanel"` (também `WellPanel`, `PrimaryButton`, `DangerButton`, `GhostButton`, `TitleLabel`, `HeaderLabel`, `HintLabel`, `LoreLabel`, `ValueLabel`). Texturas 9-slice geradas no código.
- Cores da paleta são `var`, não `const`: não servem em argumento padrão nem em classe interna (lá use `UiPalette.c` direto).
- Clima por região: `data/config/ambience.json`, aplicado por `AmbienceDirector` depois de carregar a cena (que precisa de WorldEnvironment, Moon, Ground, Fog/*). Debug `--ambience-profile=baixo|medio|alto`.
- `OFL.txt` das fontes entra na build pelo `include_filter` dos perfis de cliente.
- `UiFx` (criado no `client_main`) dá animação, som e arrastar a toda janela solta com `WindowPanel` (não dentro de Container); botão com texto "×" vira `CloseButton`. Ícones e botões em losango: `DiamondButton`.
- HUD: texto de depuração só com F3 (`--debug-hud` para capturas que precisem dele); botões de sistema em `ui.json -> theme.system_buttons` disparam a ação de entrada (`_on_system_button`).
- Partículas de ambiente: `ambience.json -> particle_types` + `particles` por região; seguem `AmbienceDirector.follow` (o próprio personagem).
- Entrada: `LoginScene` (fundo animado, `login_scene.json`) atrás da `LoginScreen`; modelo da seleção em `ClassPreview` (SubViewport com mundo próprio). Painel fixo de tela com `WindowPanel`: `set_meta("no_window_fx", true)` para o `UiFx` não animar nem arrastar. Debug `--login-form=conta:senha[:create]`.
- Janelas de itens: `UiDraw` (grade em poço, tracejado, moeda, círculo rúnico, silhuetas dos slots), chamado dentro do `_draw`.
- Capturas com `--quick-login`: use `--screenshot-frames=700` ou mais (a entrada ficou rápida e a captura saía antes do login).
- Avisos: `Notices` (no HUD: `show_event`, `show_area`, `show_toast`, `notices.set_death`); prévia `--preview-notice=event|toast|death|chat`. Pergaminho: `ParchmentPanel` + `InkLabel`/`InkTitle`.
- Fontes na Web não têm fallback: símbolos fora da fonte viram caixinha. Em losangos e toasts, prefira letras.
- Materiais do mundo por dados: `ambience.json -> regions.<id>.ground.macro|bump`, `rim`, `banners`; `materials.ice`; `contact_shadow`. Prévia de região sem servidor: `scenes/dev/region_preview.tscn -- --region=castelo --at=0,-14 --shot=...`.
- Decoração: `DecorLayer` (`ambience.json -> regions.<id>.decor`, MultiMesh, só cliente, semente própria); `scenery_tint` retinge os modelos do RegionScenery; `fires` põe chama/fagulha/fumaça (e modelo) nas luzes da cena. Modelos por "pasta/Nome" (`decor_dirs`). Kit Quaternius novo: confira o `.import` das texturas (3D).
- Ícones: `UiIcons` (desenhados no código), escolhidos em `ui.json -> theme.icons`; no `DiamondButton` é `icon_id`. Sons de interface: `audio.json -> ui` (evento → som) e `SoundDirector.ui(evento)`.

Notas do áudio (etapa extra):
- Originais em `assets/_raw/audio/` (`tools/fetch_audio.py`); convertidos em `assets/audio/` por `tools/process_audio.py` (ffmpeg no PATH), que também gera `candidates.json`, `REVIEW.md` e o manifesto. Áudio do usuário: `downloads/<categoria>/`.
- Sons no jogo: `SoundDirector` (`client/audio/sound_director.gd`), dados em `data/config/audio.json` (caminhos relativos a `assets/audio/`; o filtro de exportação lê esse arquivo). Som novo: entrada em `sounds` + referência; `test_audio_references` confere.
- Escolha: `scenes/dev/audio_preview.tscn` grava `assets/audio/selection.json`; `process_audio.py --apply-selection` apaga o resto e anota em `rejected.json` (não volta nas próximas rodadas). Depois de `--import`, rode o `process_audio.py` de novo para pôr `loop=true` nas músicas e reimporte.

Notas da Fase 6:
- Eventos: `EventSystem` (`scheduled_events.json`); lógica de cada evento numa classe (`FortressEvent`) com start/update/on_kill/on_altar/finish/cleanup/gm_skip. Instâncias = `server.create_instance(dados, "<região>@<faixa>")`; use `region.data_id` para dados e diário, `region.id` para a instância.
- Lógicas de evento: `FortressEvent`, `ArenaEvent`, `CircleEvent` (escolhidas por `logic` nos dados). Regiões: `pvp: false|"free"`, `no_items` (→ `p.ignore_equipment`).
- Castelo: `CastleSystem` (`castle.json`, tabela `castles`), cerco = `SiegeEvent`. GM `castleowner [none]`, `event cerco ...`; bots `--bot-siege=a:Outro|b:Outro`, `--bot-siege-invite=Nome`; cliente `--castle-enter=s`.
- Reset e maestria: `MasterySystem` (`reset.json`, `mastery.json`); `give_xp` no nível máximo vai para a maestria. GM `masterxp <n>`; bot `--bot-endgame=write|check`; cliente `--open-mastery`.
- O cliente gráfico compila scripts que os bots e os testes não carregam (HUD, efeitos): depois de mexer neles, rode o cliente (uma captura basta) para pegar erros de tipo.
- Bloqueios que abrem: `dynamic_blockers` na região + `WorldBuilder.apply_blockers` (servidor e predição).
- GM `event <id> open|start|skip|end`; bots `--bot-event=lead|help[:arena|circulo]`, `--bot-solo`; cliente `--use-item=base:segundos`, `--add-stat=atributo:n`.
- Códigos do brilho (`rpc_level_up_event` com nível negativo): -1 magia aprendida, -2 evolução, -3 chegada de teletransporte.

Notas da Fase 5:
- Banco: mudança de esquema = nova entrada em `SqliteRepository.MIGRATIONS` e `SCHEMA_VERSION` + 1 (nunca editar o esquema da versão 1).
- PvP: regras em `PvpSystem` (`pvp.json`); bots `--bot-pvp=attacker:Nome` / `victim:Nome`; GM `infamy <n>`.
- Guildas: `GuildSystem` (`guilds.json`), em memória e gravadas na hora; guerra justifica o PvP e conta no placar (`PvpSystem.on_kill`). Amigos: `FriendSystem` (`social.json -> friends`). Bots `--bot-guild=a:Nome` / `b:Nome`; GM `guildwar <s>`; cliente `--open-guild` / `--open-friends`.
- Ao chamar o Godot por `Start-Process`, argumentos com espaço (ex.: `--gm=level 20`) precisam de aspas.
- Classes: tudo por `p.class_id` (`server.class_data(p)`, `calc_for(p)`, `spells.spell(p, i)`); magias novas de uma classe vão **no fim** da lista dela (o índice é salvo na máscara). Tipos de magia e campos em `spells.json -> _doc`.
- Missões: `QuestSystem` (`quests.json`), NPC com papel `quest`. Bots `--bot-class=`, `--bot-classtest=support|evolve`; GM `quest <id> <etapa> [n]`, `evolve`; cliente `--login=conta:senha:Nome:classe`.
- Em strings GDScript, `\b` é backspace: em regex use `\\b`.

Notas da Fase 4:
- Tudo que é por região vem de `server.region_of(p)` (grid, monsters, drops, npcs, safe). Ids de monstros/drops são globais.
- Cenário procedural: `RegionScenery` (semente na cena); o WorldBuilder chama `populate()`. Não mudar a semente sem querer: muda colisão e visual.
- GM `goto <região> [x z]`, `invasion [região]`, `boss`; bots `--bot-travel`, `--bot-events` e `--bot-wings`.
- Monstros: use `MonsterCatalog.from_config()` (inclui as variantes douradas), nunca `GameConfig.table("monsters")` direto para montar tipos.

Notas da Fase 3:
- SQLite (addons/godot-sqlite) é só do servidor: use `ClassDB.instantiate("SQLite")` sem tipo, nunca o tipo `SQLite` no código, para a build Web compilar.
- Testes de servidor: `--db=:memory:` para não sujar o banco de desenvolvimento; os bots entram sozinhos (`--bot-account=`, `--bot-character=`).
- Cliente gráfico em capturas: `--quick-login` ou `--login=conta:senha:Personagem`; latência simulada com `--sim-lag-ms=N`.
- No painel do navegador, digitar no jogo funciona com teclas individuais (ação `key`), não com `type`.
