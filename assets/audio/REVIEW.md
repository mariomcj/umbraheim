# Revisão de áudio

Candidatos já convertidos (OGG Vorbis, loudness normalizado, silêncio cortado). Ouça e escolha na cena
`scenes/dev/audio_preview.tscn` (botão ▶ toca; marque os que ficam e clique em **Salvar escolha**).
Depois, `python -I tools/process_audio.py --apply-selection` apaga os descartados de `assets/audio/`
(os originais continuam em `assets/_raw/audio/`).

Duração: original → processado (segundos).

Loudness: música a -20 LUFS. SFX miram -16 LUFS, mas os sons muito curtos e secos (cliques, passos,
golpes de metal) ficam entre -17 e -27 LUFS: o limitador segura o pico em cerca de -1 dBFS para não
distorcer, e nesses sons quase todo o volume está no pico. O volume final de cada um se ajusta no jogo.

## Música do menu (1)

| Arquivo | Nome original | Duração | Autor · licença | Tags | Descrição |
|---|---|---|---|---|---|
| `incompetech_oppressive_gloom.ogg` | [Oppressive Gloom](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100885) | 199.4 → 197.6 | Kevin MacLeod (incompetech.com) · CC-BY 4.0 | Dark, Eerie, Epic, Mysterious, Somber, Suspenseful, Strings, Bass Clarinet, Percussion | Moody moody dark score. Almost a death march. Loops pretty darned well - but you need to trim the end. |

## Magia (5)

| Arquivo | Nome original | Duração | Autor · licença | Tags | Descrição |
|---|---|---|---|---|---|
| `fs522705_fireball_woosh_pass_fast.ogg` | [Fireball, Woosh, Pass, fast](https://freesound.org/people/julianmateo_/sounds/522705/) | 6.0 → 4.0 | julianmateo_ · CC0 | Fast, Fireball, Woosh | busca: "fireball". Fireball, Woosh, Pass, fast. Channel: Mono 24 Bits - 48 Khz |
| `fs554791_mage_teleport_skill.ogg` | [Mage Teleport Skill](https://freesound.org/people/EminYILDIRIM/sounds/554791/) | 1.4 → 0.6 | EminYILDIRIM · CC-BY 4.0 | curse, mage, magic, magician, skill, spell, telekinesis, teleport | busca: "curse spell". Recorded at 24bit 96kHz WAV. using the Zoom H6 Recorder. If you like my recording, please feel free to rate and comment |
| `fs720112_teleport_cast.ogg` | [Teleport_Cast](https://freesound.org/people/BaggoNotes/sounds/720112/) | 1.4 → 1.1 | BaggoNotes · CC0 | Ability, Ableton, Portal, Sci-Fi, Shoot, Short, Video-Game, VideoGame | busca: "portal". Sound for using an ability that casts a portal. |
| `fs861568_dark_ghost_warrior_voice_04_spectral_war.ogg` | [Dark Ghost Warrior Voice 04 - Spectral Warlock Vocal Defeat](https://freesound.org/people/TommasoMotteran/sounds/861568/) | 4.5 → 3.2 | TommasoMotteran · CC-BY 4.0 | attack, cinematic, creature, curse, dark, demon, evil, fantasy, game, ghost | busca: "dark magic". Dark ghost warrior / spectral warlock vocal, perfect for horror, fantasy, RPGs, games, films, trailers, and sound design. I used my voice + fxs. Available under the CC BY 4.0 license (attribution required). More ghost an |
| `fs871710_sound_design_impact_1.ogg` | [Sound Design Impact 1](https://freesound.org/people/CAT-FOX_ALEX/sounds/871710/) | 0.9 → 0.7 | CAT-FOX_ALEX · CC0 | Boom, Cannon, Design, Gun, Hit, Impact, Modern, Portal, Sci-fi, Sound | busca: "portal". Sample used: <a href="https://freesound.org/people/SingleCoil/sounds/459515/" rel="nofollow">https://freesound.org/people/SingleCoil/sounds/459515/</a> <a href="https://freesound.org/people/Anthousai/sounds/539695/" rel= |

## Combate (4)

| Arquivo | Nome original | Duração | Autor · licença | Tags | Descrição |
|---|---|---|---|---|---|
| `kenney_impactpunch_heavy_000.ogg` | [impactPunch_heavy_000.ogg](https://kenney.nl/assets/impact-sounds) — soco/pancada pesada (Kenney Impact Sounds) | 0.7 → 0.6 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_drawknife1.ogg` | [drawKnife1.ogg](https://kenney.nl/assets/rpg-audio) — sacar lâmina (Kenney Rpg Audio) | 0.4 → 0.3 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_knifeslice.ogg` | [knifeSlice.ogg](https://kenney.nl/assets/rpg-audio) — corte de lâmina (Kenney Rpg Audio) | 0.6 → 0.5 | Kenney (kenney.nl) · CC0 |  |  |
| `fs492250_imperius_spear_hit_03_wav.ogg` | [Imperius - Spear Hit - 03.wav](https://freesound.org/people/SoundFlakes/sounds/492250/) | 2.0 → 1.1 | SoundFlakes · CC-BY 4.0 | axe, bludgeon, chain, diablo, fly, free, game, game-developing, hit, medieval | busca: "sword hit". This sound is a part of my sound redesign project which you can watch here: <a href="https://www.youtube.com/watch?v=rgOWWBOmZj4" rel="nofollow">https://www.youtube.com/watch?v=rgOWWBOmZj4</a> As always you can use this  |

## Monstros (4)

| Arquivo | Nome original | Duração | Autor · licença | Tags | Descrição |
|---|---|---|---|---|---|
| `fs315769_dragon_growl_omnious_aiff.ogg` | [dragon growl omnious.aiff](https://freesound.org/people/bevibeldesign/sounds/315769/) | 6.2 → 6.0 | bevibeldesign · CC0 | beast, creature, dragon, foreboding, growl, growling, monster, ominous, roar, scary | busca: "monster growl". Dragon sound created for a production of Shrek. Recorded and distorted the voice of the actress playing the dragon using Audacity. Feel free to let me know what you are using the sound for! :) |
| `fs348307_zombie_monster_growl_3.ogg` | [Zombie Monster Growl 3](https://freesound.org/people/redafs/sounds/348307/) | 1.6 → 1.3 | redafs · CC-BY 4.0 | beast, dark, deep, evil, growl, horror, human, male, man, metal | busca: "monster growl". Horror voice, sound like zombie or monster Artist: Awaludian / Recording Date: April 2015 / Studio: rumahrekam Thanks for download. If you are interested in professional sfx and music with simple licensing, look there: A |
| `fs555425_zombie_pain_6_wav.ogg` | [Zombie Pain 6.wav](https://freesound.org/people/tonsil5/sounds/555425/) | 0.7 → 0.6 | tonsil5 · CC0 | ache, beast, creature, creepy, death, demon, game, game-sound, gnarl, growl | busca: "monster growl". This could also be a zombie death sound, but for good measure it's in the pain category. |
| `fs800277_insect_animal_growl_chitter.ogg` | [Insect Animal Growl Chitter](https://freesound.org/people/SecureSubset/sounds/800277/) | 1.7 → 1.4 | SecureSubset · CC0 | animal, creature, growl, insect, monster, roar | busca: "monster growl". A strange chitter sound. This is actually the sound of a guinea pig being defensive, but reversed. |

## Passos (4)

| Arquivo | Nome original | Duração | Autor · licença | Tags | Descrição |
|---|---|---|---|---|---|
| `kenney_footstep_concrete_000.ogg` | [footstep_concrete_000.ogg](https://kenney.nl/assets/impact-sounds) — passo em pedra/concreto (Kenney Impact Sounds) | 0.1 → 0.1 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_footstep_grass_000.ogg` | [footstep_grass_000.ogg](https://kenney.nl/assets/impact-sounds) — passo na grama (Kenney Impact Sounds) | 0.8 → 0.2 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_footstep00.ogg` | [footstep00.ogg](https://kenney.nl/assets/rpg-audio) — passo (pacote RPG) (Kenney Rpg Audio) | 0.2 → 0.2 | Kenney (kenney.nl) · CC0 |  |  |
| `fs517136_footsteps_stone_7_wav.ogg` | [Footsteps Stone (7).wav](https://freesound.org/people/Wdomino/sounds/517136/) | 0.5 → 0.4 | Wdomino · CC0 | footstep, shoe, step, stone | busca: "footsteps stone". footstep stone 7 |

## Ambiente (3)

| Arquivo | Nome original | Duração | Autor · licença | Tags | Descrição |
|---|---|---|---|---|---|
| `fs166187_creepy_dungeon_ambience.ogg` | [Creepy Dungeon Ambience](https://freesound.org/people/DrMinky/sounds/166187/) | 48.0 → 48.0 | DrMinky · CC-BY 4.0 | ambience, ambient, cave, creepy, dripping, dungeon, game, loopable, scary, video | busca: "dungeon ambience". Loopable "creepy dungeon ambience", made using synths and pitched down cows! Please leave a comment with any feedback, and if you use one of my sounds then read the post on my profile! Thank you. |
| `fs422720_a_dungeon_ambience_loop_wav.ogg` | [A_Dungeon_Ambience_Loop.wav](https://freesound.org/people/Grubzyy/sounds/422720/) | 28.9 → 28.9 | Grubzyy · CC0 | ambient, dungeon, loop | busca: "dungeon ambience". Deep ominous sounds echoing from a distance |
| `fs607205_ooooo_chorus_and_reverb.ogg` | [ooooo + Chorus and Reverb](https://freesound.org/people/Fupicat/sounds/607205/) | 25.4 → 25.4 | Fupicat · CC0 | air, ambience, ambient, anxious, artificial, atmosphere, creepy, dark, deep, drone | busca: "wind". A deep, windy loop that sounds like nothing in particular, but makes you feel uneasy. Could be used to establish a feeling of anxiety or fear. |

## Interface (13)

| Arquivo | Nome original | Duração | Autor · licença | Tags | Descrição |
|---|---|---|---|---|---|
| `kenney_select_002.ogg` | [select_002.ogg](https://kenney.nl/assets/interface-sounds) — clique (seleção) (Kenney Interface Sounds) | 0.0 → 0.0 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_click3.ogg` | [click3.ogg](https://kenney.nl/assets/ui-audio) — clique seco (Kenney Ui Audio) | 0.1 → 0.1 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_handlesmallleather.ogg` | [handleSmallLeather.ogg](https://kenney.nl/assets/rpg-audio) — couro (abrir janela) (Kenney Rpg Audio) | 0.3 → 0.3 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_handlesmallleather2.ogg` | [handleSmallLeather2.ogg](https://kenney.nl/assets/rpg-audio) — couro (fechar janela) (Kenney Rpg Audio) | 0.3 → 0.2 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_confirmation_002.ogg` | [confirmation_002.ogg](https://kenney.nl/assets/interface-sounds) — confirmação suave (Kenney Interface Sounds) | 0.5 → 0.5 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_error_006.ogg` | [error_006.ogg](https://kenney.nl/assets/interface-sounds) — erro grave (Kenney Interface Sounds) | 0.5 → 0.3 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_dropleather.ogg` | [dropLeather.ogg](https://kenney.nl/assets/rpg-audio) — soltar item (Kenney Rpg Audio) | 0.4 → 0.4 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_belthandle1.ogg` | [beltHandle1.ogg](https://kenney.nl/assets/rpg-audio) — pegar item (Kenney Rpg Audio) | 0.3 → 0.3 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_cloth2.ogg` | [cloth2.ogg](https://kenney.nl/assets/rpg-audio) — equipar (Kenney Rpg Audio) | 0.4 → 0.4 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_handlecoins2.ogg` | [handleCoins2.ogg](https://kenney.nl/assets/rpg-audio) — moedas (Kenney Rpg Audio) | 0.3 → 0.3 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_bookflip2.ogg` | [bookFlip2.ogg](https://kenney.nl/assets/rpg-audio) — virar página (Kenney Rpg Audio) | 0.4 → 0.4 | Kenney (kenney.nl) · CC0 |  |  |
| `kenney_metallatch.ogg` | [metalLatch.ogg](https://kenney.nl/assets/rpg-audio) — trinco (baú) (Kenney Rpg Audio) | 0.3 → 0.3 | Kenney (kenney.nl) · CC0 |  |  |
| `fs488381_uihover1_wav.ogg` | [UIHover1.wav](https://freesound.org/people/wobesound/sounds/488381/) | 0.3 → 0.1 | wobesound · CC0 | Click, Hover, UI, videogame | busca: "ui click". Sound played when hovering over an UI element in a videogame. Made for a cancelled student game. Created from other CC0 sounds from Freesound but edited &amp; mixed together. |

## Pendências

- **Fora da regra de licença (não baixadas):** do OpenGameArt, "Dark Gothic Haunted Masquerade" e "Dark Solemn Choral with Organ" (ISAo, OGA-BY 3.0), "Orchestral Epic Fantasy Music" (Zefz, CC-BY-SA 3.0 / GPL 3.0) e "The Dance of Death" (Michael Klier, CC-BY-SA 3.0).
