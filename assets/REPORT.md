# Relatório da biblioteca de assets

Gerado por `tools/asset_reports.py` em 2026-11-16.

## Totais

- **Baixado (originais em `assets/_raw/`):** 197.2 MB em 559 arquivos.
- **Itens no manifesto:** 96 (CC-BY 4.0: 6, CC0: 85, OFL 1.1: 3, QAL v1.0 (Quaternius Asset License): 2).

## Tamanho por pasta (o que o jogo usa)

| Pasta | Tamanho | Arquivos |
|---|---|---|
| `assets/textures/ground` | 23.1 MB | 24 |
| `assets/textures/stone` | 17.0 MB | 21 |
| `assets/textures/metal` | 7.6 MB | 12 |
| `assets/textures/wood` | 12.7 MB | 18 |
| `assets/textures/misc` | 51.6 MB | 1318 |
| `assets/hdri` | 4.4 MB | 3 |
| `assets/vfx/shaders` | 0.0 MB | 20 |
| `assets/vfx/particles` | 5.1 MB | 97 |
| `assets/models/characters` | 55.0 MB | 56 |
| `assets/models/monsters` | 32.6 MB | 30 |
| `assets/models/props` | 18.4 MB | 333 |
| `assets/models/environment` | 41.5 MB | 527 |
| `assets/models/weapons` | 0.3 MB | 24 |
| `assets/audio/sfx` | 0.8 MB | 33 |
| `assets/audio/music` | 3.4 MB | 1 |
| **total** | **273.4 MB** | |

## Itens pesados

- **Imagens:** 1598 conferidas, maior lado 1024 px. Nenhuma acima de 1024 px.
- **Kenney Game Icons:** 421 PNG (3.4 MB) porque o pacote traz cada ícone em várias resoluções e cores; ao usar na interface, fique só com uma resolução e apague o resto.
- **Modelos acima de ~20000 triângulos:** 492 modelos conferidos; nenhum acima do limite.

## Observações

- Kits da Quaternius (Fantasy Props, Medieval Village, Stylized Nature) entram como glTF (.gltf + .bin) com uma pasta de texturas por kit, porque todos os modelos de um kit usam os mesmos atlas: em .glb, cada arquivo levaria uma cópia. A Godot importa .gltf direto. Importados por `tools/import_kits.py`; FBX/OBJ avulsos vão por `tools/convert_models.py` (Blender).
- Animações: `assets/models/characters/animations/UAL1_Standard.glb` e `UAL2_Standard.glb` (86 clipes, esqueleto de 65 ossos, o mesmo dos personagens elfo e orc; os monstros usam outro, de 55 ossos). Clipes principais renomeados: idle, walk, run, sprint, attack, attack_2..4, cast, hit, death.
- Blender 5.3 extraído do instalador (sem instalar) em `%LOCALAPPDATA%\Programslender-5.3.0-portable`.
- Os 10 shaders compilam no renderer Compatibility (testado na vitrine `scenes/dev/asset_showcase.tscn`). O `aura_3d` vinha com espaços inquebráveis do HTML e foi corrigido; ele é uma camada de contorno (vai por cima de outro material).
- Nada de `assets/textures`, `hdri`, `vfx`, `models`, `audio` e `scenes/dev` entra na build: estão no `exclude_filter` dos perfis de exportação até serem usados pelo jogo. Ao integrar um asset, tire a pasta dele do filtro (ou mova o arquivo para fora delas).
- Build Web depois do filtro: 45,11 MB (antes 38,83 MB). A diferença não vem desta biblioteca: é a arte nova do UMBRAHEIM em `client/ui/art/` (tela de carregamento de 1 MB, que também vira o `index.png` da Web, e duas imagens de título), que entram no `.pck` (6,5 MB). Vale reduzir essas imagens ou exportá-las com compressão com perda.

## Pendências

- **Puglin sem animação:** o Imp e o Puglin (Bestiary gratuito) não trazem animações, mas o esqueleto deles tem os mesmos nomes de ossos da Universal Animation Library (só faltam os mindinhos). O jogo copia os clipes da UAL1 para eles (`ModelRig`); o Imp já está em uso (Bruto Acorrentado), o Puglin ainda não.
- **Sketchfab (11 modelos, sem arquivo de licença):** pela busca na API do Sketchfab, todos os nomes batem com modelos CC-BY (crédito obrigatório), mas 6 nomes têm mais de um modelo igual e um dos "Modular Dungeon" é NonCommercial. Preciso do link exato de cada um para confirmar a licença e o autor. Vários são pesados para a Web (70 mil a 1,4 milhão de triângulos).
- **`texturas e assets/fornitures` e `weaponsassetspackbyStyloo` (sem licença):** não importados; diga de onde vieram e a licença.
- **Shaders com licença MIT, para você revisar** (fora da regra CC0/CC-BY, não baixados): [Dissolve with Glowing Edge](https://godotshaders.com/shader/dissolve-with-glowing-edge/), [3D Burn Dissolve](https://godotshaders.com/shader/3d-burn-dissolve/), [3D Vertical Dissolve](https://godotshaders.com/shader/3d-vertical-dissolve/), [Frost Overlay for any Mesh](https://godotshaders.com/shader/frost-overlay-for-any-mesh/).
- **Texturas 2048 px para personagens principais:** só se você aprovar (hoje tudo está em até 1024 px).
- **Áudio:** nenhum som ou música ainda (fora desta etapa).
