# Registro de decisões

Formato: data — decisão — motivo.

## Ajustes e redesenho (2026-11-14)

1. **Inimigos com 2× vida e 1,5× dano, e grupos dobrados nas regiões abertas** (pedido do usuário: "muito fracos" e poucos). Os portões de evento ficaram de fora, porque são objetivos com tempo.
2. **Licença OFL aceita, só para fontes** (Cinzel, Alegreya Sans, IM Fell English). Motivo: não há fonte serifada boa em CC0; a proposta de interface foi aprovada com elas. O `OFL.txt` vai junto de cada fonte.
3. **Redesenho da interface e da ambientação por propostas de especialistas** (`docs/design/PROPOSTA_UI.md` e `PROPOSTA_AMBIENTACAO.md`), aprovadas antes de implementar e aplicadas por partes.
4. **Tema único gerado a partir de `ui.json`** (`UiThemeBuilder`), com texturas 9-slice geradas por código. Motivo: as 14 janelas tinham estilos próprios, e a fonte da verdade tem de ser o dado.
5. **Clima das regiões vem de `ambience.json`, aplicado no cliente** (`AmbienceDirector`), e não das cenas. Motivo: os valores ficam ajustáveis sem abrir cenas, e o servidor não carrega nada visual.

## Assets no jogo (2026-11-13)

1. **Os modelos são só do cliente e cobrem as formas antigas, que continuam como colisão.** Motivo: a colisão e a grade de navegação do servidor não mudam, o servidor não carrega arte, e cenário e predição continuam batendo.
2. **A variante do modelo sai da posição, não do sorteio.** Motivo: um `randi()` a mais mudaria todo o cenário depois dele (e a colisão junto). Assim a semente continua valendo.
3. **Texturas com teto de 512 px (normal em 256 px), sem rugosidade e com compressão VRAM.** Motivo: a build Web. Com 1024 px e sem compressão o `.pck` passava de 20 MB; assim ficou em 9,9 MB. Os mapas de rugosidade quase não aparecem com a câmera de cima.
4. **Triplanar em muros, pedras e casas** (escala no mundo). Motivo: as caixas têm tamanhos muito diferentes, e o UV de cada uma esticaria a textura.
5. **Filtro de exportação gerado** (`tools/update_export_filter.py`) em vez de uma lista à mão. Motivo: a biblioteca tem centenas de arquivos e só uma parte entra no jogo. Esquecer um arquivo usado quebra a build, e esquecer de excluir um que não é usado a incha.
6. **O chão do Bosque foi tingido para um verde-oliva queimado.** Motivo: a textura é de grama viva, e a região é das "cinzas mortas".
7. **A QAL (Quaternius Asset License) foi aceita**, além de CC0 e CC-BY. Decisão do usuário. Os kits QAL aparecem com a licença própria em `CREDITS.md`.
8. **Classes com os modelos KayKit Adventurers, não com os Fantasy Races (QAL).** Motivo: os Fantasy Races são corpos-base de roupa de baixo, sem túnica nem armadura. Os KayKit já vestem mago, cavaleiro e encapuzado e trazem cerca de 75 animações, inclusive de magia. O traço é mais fofo que o das referências; trocar é só mudar `models.json`.
9. **Um arquivo de animações para todos os modelos KayKit** (`Skeleton_Minion.glb`), com os clipes copiados uma vez por modelo e apontados para o esqueleto dele. Os demais arquivos são importados sem animação. Motivo: cada arquivo trazia cerca de 1,5 MB de clipes repetidos na build Web.
10. **O imp (QAL, sem animações) usa a UAL1 (CC0)**, porque o esqueleto dele tem os mesmos nomes de ossos. As trilhas de ossos que não existem no modelo são descartadas.
11. **Armas na mão do modelo; armadura sem forma própria.** Motivo: as formas simples de túnica e capuz por cima de um modelo vestido ficavam estranhas. O brilho do refino e a raridade continuam visíveis na arma e na aura.
12. **Modelos dourados e invocações limpam o material de cada superfície antes de receber o material único.** Motivo: com os dois ao mesmo tempo, o renderer Compatibility perdia o material e enchia o log de erros, e o FPS caía para 26.
14. **Uma partícula com forma por tipo de efeito, não por magia.** Motivo: as magias já se diferenciam pela cor; oito formas bastam e cabem em cerca de 0,5 MB (128 px).
15. **Dissolução pela altura do mundo** (não pela posição local do vértice, como no shader original). Motivo: os modelos têm escalas e esqueletos diferentes, e no espaço do mundo a mesma faixa serve para todos. Material opaco com descarte, para não depender da ordenação de transparência no WebGL.
16. **Shaders de terceiros adaptados como cópia** (`assets/shaders/*`) e os originais intactos em `assets/vfx/shaders/`, com o crédito no cabeçalho. Motivo: a licença CC0 permite, e o original serve de referência.
17. **Filtro de exportação também segue as texturas extraídas dos glb e as partículas citadas por nome.** Motivo: os glb apareciam brancos na Web sem elas.
13. **Escala por altura (caixa das malhas) para glTF; escala fixa nos dados para os FBX.** Motivo: nos FBX da Quaternius o esqueleto está em outra unidade, e a caixa de descanso dava um tamanho errado.

## Identidade (2026-11-13)

1. **O jogo se chama Umbraheim** (antes, "Feitiçaria Sombria"). Mudaram o nome do projeto (título da janela e da página Web), o banco (`user://umbraheim.db`) e a tela de entrada. A pasta do projeto e os textos de tema ("feitiçaria sombria" como gênero na especificação) ficaram como estavam.
2. **A tela de entrada usa a arte do nome** (`client/ui/art/`): a larga em telas largas, encaixada inteira na largura quando a tela é mais estreita que 16:10 (para não cortar o nome), e a vertical em telas em pé. O formulário fica embaixo, e a seleção de personagens tem duas colunas, para não cobrir o nome. O texto de depuração só aparece no mundo.
3. **Artes em JPG importadas com compressão com perda (WebP 0,82)** e tela de carregamento em 640×360: somam cerca de 1,6 MB à build Web (40,4 MB), contra cerca de 6 MB sem compressão.
4. **A troca de nome muda a pasta de dados da Godot** (`user://` segue o nome do projeto). Não havia banco salvo na pasta antiga, só o último nome de conta, então nada se perdeu.

## Fase 6 (2026-11-13)

1. **Calendário pelo relógio do servidor em UTC** (`every_min`, `at_min`): o horário é previsível e igual para todos, como os eventos de hora marcada dos MMOs clássicos. Os portões abrem `entry_s` antes do começo. O cálculo do próximo horário é uma função pura e testada.
2. **Instância = cópia da região dos dados** (id `<região>@<faixa>`), criada quando o primeiro jogador da faixa entra e apagada no fim. Ela entra em `server.regions` enquanto dura, e por isso snapshot, interesse, combate, drops e invocações funcionam sem casos especiais. O cliente tira o `@...` para carregar a cena; o diário é por região, não por instância.
3. **Uma instância por faixa de nível** (sem mistura de níveis), com os monstros da faixa nos dados.
4. **Ingresso usado com o botão direito** durante a abertura, em vez de um NPC: menos passos e o mesmo papel (o selo vem da Forja). Fora da hora o selo não é gasto.
5. **Bloqueios que abrem** (`dynamic_blockers`): retângulos que começam bloqueados na grade (servidor e predição) e abrem por evento (`rpc_event_world`). O nó visual com o mesmo nome em `Blockers` some. Serve para grades, portões e, depois, para o castelo.
6. **O portão é um monstro "estrutura"** (não anda nem ataca) marcado como invulnerável até a etapa certa. O dano mostra "protegido" (0). Assim ele aparece com vida, nome e barra, e reaproveita o combate.
7. **Relíquia vai para quem mais feriu o chefe** (o mesmo critério do drop) direto na mochila, como item de missão (não se vende nem se troca). Ela some de quem sai ou quando o evento acaba.
8. **Morrer tira do evento** (renasce no Refúgio), como no MMO de referência. Instância vazia durante o evento = derrota imediata.
9. **Sem PvP na Fortaleza** (`pvp: false` na região): o evento é cooperativo. O Círculo que Encolhe (parte 2) terá PvP sem infâmia.
10. **GM `event <id> skip`** para os testes: adianta a etapa, mas ainda é preciso derrubar o portão e o chefe, então os caminhos de vitória são exercitados de verdade.
11. **Um tipo de lógica por evento** (`logic`: fortress, waves, circle), todas com os mesmos ganchos (start, update, on_kill, finish, cleanup, gm_skip). O EventSystem não sabe nada das regras de cada uma; um evento novo é uma classe e uma entrada nos dados.
12. **Arena: prêmio por pontos para quem está online no fim**, mesmo que tenha morrido antes (os pontos ficam). Quem sai do jogo perde o prêmio, porque não há como entregá-lo.
13. **Círculo "sem itens de fora" = equipamento sem bônus e consumíveis bloqueados** (`ignore_equipment` no recompute e `no_items` na região), em vez de tirar os itens da mochila. É justo (só atributos e magias contam) e não arrisca perder itens. A aparência continua a mesma.
14. **PvP livre como regra da região** (`pvp: "free"`): sem infâmia, herói, penalidade nem proteção de grupo e guilda. Os pontos vêm do gancho do evento.
15. **O anel queima até a antessala:** depois da largada ninguém pode se esconder na zona segura. Ela continua segura contra ataques, mas não contra o anel.
16. **Círculo com menos de 2 lutadores é cancelado e o ingresso volta**, porque um battle royale de um não tem graça e não deve custar o ingresso.
17. **Horários escalonados** (0, 10 e 20 min do ciclo de 30 min): sempre há um evento perto, e um personagem pode fazer os três em sequência.

### Parte 3: reset e maestria

18. **Reset no nível máximo, configurável** (`reset.json`, `enabled`), como pede a especificação. Ele volta ao nível 1 com os atributos iniciais da classe e dá pontos por reset que acumulam (o clássico dos servidores de MU). Itens, magias, evolução e maestria ficam. Os itens equipados continuam equipados mesmo acima do nível, porque tirá-los arriscaria perder itens sem espaço na mochila.
19. **Reset só no Refúgio, pela janela de atributos, com confirmação** em dois cliques. Não precisa de um NPC novo, e a cidade evita renascer no meio de uma região perigosa com nível 1.
20. **Maestria = níveis depois do máximo**, com XP própria e 1 ponto por nível, como pede a especificação. A XP dos monstros e dos eventos no nível máximo cai direto nela.
21. **Árvores em dados, nós em sequência** (cada nó exige 5 pontos no anterior). Os bônus usam as mesmas chaves do equipamento, então não precisam de código novo de combate. Valem dentro do Círculo, porque são do personagem, não de itens de fora.
22. **Sem redistribuir pontos de maestria** por enquanto: deixa a escolha com peso. Dá para ligar depois com um custo nos dados.

### Parte 4: cerco ao castelo

23. **O cerco é mais um evento com horário** (`logic: siege`), semanal, sobre a mesma estrutura: instância, painel, bloqueio do portão, avisos. O que é permanente (dono, imposto, tesouro, inscrições) fica no `CastleSystem` e no banco.
24. **Entrada pelo Arauto, sem ingresso**, e permitida durante o cerco (reforços). Inscrição só pelo mestre e só antes de os portões abrirem; a dona não se inscreve.
25. **Tomar o trono = a sua guilda sozinha perto dele por 20 s.** Disputa zera a contagem. É simples de entender e obriga a limpar a área, em vez de depender de um golpe final. O trono pode trocar de mãos várias vezes, e vale quem o tem no fim.
26. **No cerco, morrer devolve ao próprio lado**, sem sair do evento. A luta dura 30 min e é entre guildas: sair na primeira morte acabaria com o cerco em segundos.
27. **PvP "guild"**: todos contra todos, menos a própria guilda; sem infâmia. Grupo não protege (guildas diferentes no mesmo grupo se atacam), porque o que conta no cerco é a guilda.
28. **Imposto sobre as compras nas lojas** (não sobre as vendas nem o teletransporte), arredondado para cima e mostrado no preço. Ele vai para o tesouro do castelo, e só o mestre dono saca. Uma dona nova começa com 5% e o tesouro zerado, para o dinheiro não passar de uma guilda para a outra.
29. **Guilda dona desfeita = castelo sem dona.** Até o próximo cerco ninguém cobra imposto, e os Guardiões voltam a proteger o trono.

## Fase 5 (2026-11-12)

1. **PvP pelo mesmo caminho das magias:** alvo com id positivo é jogador; o cliente só manda isso com Ctrl. Não houve campo novo no protocolo, e o servidor confere tudo (zona segura, nível mínimo, região, grupo).
2. **Só magias de alvo único atingem jogadores.** Área e corrente acertariam inocentes por acidente perto de monstros; assim o PvP é sempre intencional.
3. **Dano entre jogadores a 60%** (`pvp.json`), para dar tempo de reagir e de usar a autodefesa.
4. **Autodefesa por agressor** (60 s): só contra quem atacou, e não contra todos. "Justificado" = o alvo é Fora da Lei ou atacou você antes.
5. **Infâmia em pontos com níveis por limiar** (1, 3 e 6), cada nível com as suas penalidades nos dados. O decaimento soma tempo online e monstros mortos num só contador.
6. **Penalidade só para Fora da Lei ao morrer** (XP e chance de deixar cair um item; o carmesim pode perder até equipamento). Cidadãos não perdem nada ao morrer, como antes.
7. **Migrações de banco por versão** (`SqliteRepository.MIGRATIONS`): bancos existentes ganham colunas novas ao abrir. Testado com um banco da versão 1.
8. **Status de PvP replicado à parte** (`rpc_player_tag`, nível de Fora da Lei e de herói), como o nome: muda pouco e todos precisam ver.
9. **Guildas em memória, gravadas na hora.** O servidor carrega todas as guildas ao abrir (são poucas e pequenas) e cada mudança (entrar, cargo, sair, símbolo, vitória) vai direto ao banco. Os membros são guardados pelo id do personagem, então a guilda existe com todos offline.
10. **Símbolo como texto hexadecimal** (8×8, um dígito por pixel, índice numa paleta de 16 cores dos dados, 0 = transparente). Cabe numa coluna de texto, viaja numa string e o servidor valida tamanho, cores e um mínimo de pixels pintados. O cliente gera a textura com cache.
11. **Cargos como índice numa lista dos dados** (`guilds.json -> roles`), com limite e permissões por cargo. Regra fixa no código: só se expulsa cargo abaixo do seu, e só o mestre muda cargos, símbolo e liderança. Passar a liderança troca os cargos dos dois, o que mantém os limites.
12. **Guerra de guildas em memória:** é curta (15 minutos), então não vai ao banco; só a vitória é gravada. Ela reaproveita o PvP: o ataque entre guildas em guerra conta como justificado (sem infâmia nem autodefesa), e a morte soma no placar em vez de dar infâmia ou herói. Uma guerra por guilda de cada vez, aceita por quem tem a permissão na outra guilda.
13. **Fundar guilda custa nível 15, 5000 Óbolos e estar na cidade.** É um ralo de moeda e evita guildas de personagens descartáveis. A tabela de guilda do MU usa um NPC; aqui a janela (G) basta, e a exigência de estar na cidade mantém o mesmo espírito.
14. **Amizade mútua** (pedido e aceite, duas linhas no banco): os dois veem um ao outro online, o nível e a região. Pedir exige o outro online, como os convites de grupo e guilda.
15. **Janela social única** (abas Guilda e Amigos) no lado esquerdo, e o chat se desloca enquanto ela está aberta, para o mundo e as mensagens continuarem visíveis.
16. **Convites com um terceiro campo** (`rpc_prompt(tipo, nome, detalhe)`, protocolo v13), para mostrar o nome da guilda no convite e na declaração de guerra.
17. **Magias por classe, com índice local** (posição na lista da classe), como já era o Feiticeiro. Assim a máscara de magias aprendidas salva no banco continua valendo. O cliente descobre a classe de cada jogador pelo `rpc_player_name` (nome, classe e evolução) e usa a lista certa para os efeitos dos outros.
18. **Um só tipo de dano para todas as classes** (`magic_min`/`magic_max`, rolagem igual). O que muda é a fórmula: o Cavaleiro tira o dano da força. Combate, refino, opções excelentes e PvP continuam sem nenhum caso especial; a janela só troca o rótulo ("Dano").
19. **Tipos de magia novos, nos dados** (`melee`, `nova`, `buff`, `heal`, `summon`), cada um com campos próprios em `spells.json`. Bônus temporários somam como bônus de equipamento (mesmas chaves) no `recompute`, sem acumular a mesma magia (renova a duração).
20. **Bônus e cura podem na cidade; ataques e invocação não.** Ninguém se fere com eles, e assim dá para se preparar antes de sair. A invocação não é um ataque, mas só serve para lutar.
21. **Invocação simples:** uma por jogador, segue o dono em linha reta (deslizando nas paredes), ataca o monstro mais próximo e não recebe dano (os monstros caçam o dono). O dano é do dono, então XP, drops e missões funcionam sem mudanças. Ela entra no snapshot como um terceiro tipo de entidade (`KIND_SUMMON`).
22. **Restrição de classe no item** (`classes` em `items.json`; sem a chave, vale para todas). O servidor recusa equipar e usar, e a dica mostra a classe em vermelho. Os cajados servem ao Feiticeiro e à Vidente; as espadas e a Cota de Cinzas, só ao Cavaleiro.
23. **Evolução por uma missão compartilhada** (`quests.json`, com um texto por classe), entregue a um NPC novo (papel `quest`). Etapas de matar numa região (conta o grupo) e de trazer um item que o chefe dá direto a quem ajudou. Recompensa: título, magia da evolução (no fim da lista da classe, para não mexer nos índices), +10 pontos e +2 por nível. Asas de nível 2 ficam para a Fase 6.
24. **A variável `str` das fórmulas vira `strength` antes de compilar**, porque `str` é uma função da `Expression` da Godot. Os dados continuam escritos com `str`.
## Fase 4 (2026-11-12)

1. **Um servidor simula todas as regiões no mesmo tick** (`RegionInstance` por região), em vez de um processo por região. Para três regiões e dezenas de jogadores, é o mais simples; separar em processos fica para quando a carga pedir.
2. **Ids de monstros e drops são globais** (contadores no GameServer): um id nunca se repete entre regiões, então o cliente e o codec de snapshot não precisam saber de região.
3. **Cenário procedural determinístico** (`RegionScenery`, semente fixa na cena). O WorldBuilder chama `populate()` antes de montar a grade, então servidor e cliente geram exatamente as mesmas peças. Só o tronco de cada peça bloqueia o caminho; galhos e copas não. Evita escrever centenas de nós à mão nas cenas.
4. **Portais definidos nos dados da região** (posição, raio, destino, portal de chegada e ponto de chegada). O cliente monta o visual a partir dos mesmos dados. A chegada fica fora do raio do portal de volta (testado), para ninguém ser jogado de volta na hora.
5. **Troca de região:** o servidor manda `rpc_region_changed` antes de qualquer snapshot da região nova e zera o encoder de delta daquele jogador. O cliente troca a cena, zera o decodificador e recebe tudo completo, sem misturar entidades de duas regiões.
6. **Virada de página feita com a própria folha antiga:** copia a tinta da SubViewport e os rótulos e anima a página dobrando para a esquerda sobre a folha nova (0,75 s, em `journal.json`). Não precisa de assets.
7. **Teletransporte pelo painel ao lado do diário (J)**, listando só as folhas existentes, como pede a especificação. O custo e o ponto de chegada ficam nos dados de cada região.
8. **Morrer fora da cidade leva ao Refúgio** (`respawn_region`), como nos MMOs clássicos. O Pergaminho do Retorno passou a funcionar de qualquer região.
10. **Chefe = monstro normal marcado como `boss`** (escala, multiplicador de XP, várias rolagens de drop, renascimento longo), posto nos `monster_spawns` com contagem 1. Reaproveita IA, combate e snapshot sem código novo.
11. **Monstros dourados gerados dos dados** (`MonsterCatalog`: id + `_dourado`, multiplicadores em `events.json`), não escritos à mão. Servidor e cliente geram a mesma lista na mesma ordem, então o tipo no snapshot continua sendo só um índice.
12. **Monstros de evento são temporários:** não renascem, saem da região ao morrer e são removidos quando a invasão acaba. O cliente os tira da tela porque deixam de aparecer no snapshot.
13. **Uma invasão por vez no mundo inteiro**, em região sorteada por peso, com intervalo sorteado. Mais simples de entender ("há uma invasão agora") e de equilibrar. Horários fixos (eventos com hora marcada, como pede a especificação para outros eventos) entram na Fase 5.
14. **Caveira no diário só para quem ajudou** a derrubar o chefe (quem causou dano), na folha da região, como pede a especificação ("chefe derrotado").
15. **Avisos de evento** por `rpc_announce` (faixa no alto e linha no chat), para todos os jogadores de todas as regiões.
16. **Asas como equipamento comum do slot "asas"**, refináveis e com raridade, para reaproveitar refino, brilho, aparência replicada e persistência. Bônus por chaves que o combate já entende (`damage_pct`, `damage_reduction_pct`, defesa, mana).
17. **Receita de asas sacrifica um equipamento refinado** (estilo clássico), e a chance cresce com o refino do sacrifício. É um ralo de itens bons e de joias. Ela é avaliada antes do refino superior; como os ingredientes não coincidem, as duas receitas não se confundem (testado).
18. **Visual das asas montado com primitivas** (penas em leque, batida por script, brasas com partículas), como o resto dos placeholders, até haver modelos de verdade (Fase 6). Asas de nível 2 ficam para a evolução de classe (Fase 5).
9. **Ficaram de fora desta parte**, conforme o plano: chefes, invasões e asas (partes 2 e 3) e os pacotes `.pck` por região (Fase 6, quando o tamanho da build pedir).

## Fase 3 (2026-11-12)

1. **SQLite com godot-sqlite v4.9** (MIT), baixado do GitHub com SHA-256 conferido. Só vão as bibliotecas de Windows (desenvolvimento) e Linux (produção). A pasta fica fora da exportação Web.
2. **O banco é usado sem tipo** (`ClassDB.instantiate("SQLite")`): o script do repositório compila também na Web, onde a extensão não existe e o código nunca roda.
3. **Repositório neutro** (`GameRepository` com Dictionaries). O SQLite é um detalhe; uma versão PostgreSQL implementa os mesmos métodos. O diário vai como JSON (coordenadas a 1 cm), portável entre bancos.
4. **Senhas com PBKDF2-HMAC-SHA256** (600 mil iterações, sal de 16 bytes, comparação em tempo constante) em vez de argon2/bcrypt. A Godot não tem argon2/bcrypt, e PBKDF2 é recomendado pelo NIST e pela OWASP. Cada conta guarda o próprio número de iterações, então dá para aumentar depois sem quebrar contas antigas.
5. **O hash roda no WorkerThreadPool**, fora do tick. Uma conta inexistente também passa pelo hash, para o tempo de resposta não revelar quais contas existem.
6. **Itens com uid global** (chave primária). A fábrica continua a partir do maior uid salvo. Salvar usa `INSERT OR REPLACE`, então um item que trocar de dono (troca, parte 2) nunca fica duplicado.
7. **Salvar = reescrever o personagem numa transação** (atributos, itens e diário), ao sair, a cada 60 s e quando a conta entra em outro lugar. Simples e seguro para dezenas de jogadores; salvar só o que mudou fica para quando o número de jogadores pedir.
8. **Mesma conta em dois lugares: vale a mais nova.** A antiga é salva antes e recebe o motivo (`rpc_kicked`); depois disso o cliente antigo não reconecta sozinho.
9. **Reconexão automática só com credenciais em memória** (da sessão atual). A senha nunca é gravada no disco ou no navegador; só o nome da última conta.
10. **Nomes de personagem com acentos**, únicos sem diferenciar maiúsculas (coluna `name_key`).
11. **Sem apagar personagem por enquanto:** exige confirmação e regras (itens, guilda) que fazem mais sentido na Fase 5.
13. **Chat e mensagens do jogo na mesma caixa** (a antiga lista de mensagens virou a caixa de chat), com uma cor por canal. Linhas em `Label`, não `RichTextLabel`: o texto dos jogadores nunca é interpretado como BBCode.
14. **Comandos do chat em português** (`/g`, `/s`, `/r`, `/convidar`, `/sair`, `/expulsar`, `/trocar`), interpretados no cliente. O servidor recebe só intenções tipadas (canal, alvo, texto; ação de grupo; ação de troca).
15. **Flood por jogador** (janela deslizante: 6 mensagens em 8 s, em `social.json`), avisado ao próprio jogador.
16. **XP do grupo proporcional ao nível** (como nos MMOs clássicos), com bônus por membro e por classe diferente. Só ganha quem está vivo e a até 30 m do monstro; quem matou sempre recebe.
17. **Só o líder convida e expulsa.** Se ele sai, o próximo da lista assume; quem desconecta sai do grupo (o grupo não sobrevive a um relogin, por enquanto).
18. **Troca em duas etapas** ("Pronto" e "Confirmar"), e qualquer mudança desmarca os dois lados: um jogador não consegue trocar a oferta depois que o outro aceitou. Antes de trocar, o servidor simula o pior caso de espaço (sem contar pilhas); se faltar, a troca não acontece e só destrava.
19. **Itens oferecidos vão para o container 400** (fora da grade, como a mesa da forja) e voltam ao cancelar. Os dois personagens são salvos numa transação só (`save_characters`), e cada troca vai para o log do servidor com os uids.
20. **Membros do grupo podem pegar os drops uns dos outros** durante a posse temporária.

21. **Seta de posição estilo GPS no lugar do lápis** (pedido do usuário): seta de navegação vermelha com contorno claro e halo pulsando, centrada na posição e apontando para onde o personagem olha. O lápis continua só como metáfora do traço. Cores e tamanho em `journal.json`.
22. **Minimapa pode ser ocultado** (tecla M, o × na folha ou o botão "Mapa (M)" para voltar). A escolha fica em `user://client.cfg`, uma preferência local do jogador, e o diário em tela cheia (J) continua disponível.

23. **Interesse por raio** (32 m + 4 m de folga) com grade espacial de 16 m remontada a cada tick. Para dezenas de jogadores numa região, remontar é mais barato e simples que manter a grade atualizada.
24. **Ficam globais:** nomes, aparência, drops e chat geral. São raros e pequenos, e assim quem entra numa área já tem o nome e a aparência de quem vai ver. Os drops passam a ser por área quando houver muitos ou regiões grandes (Fase 4).
25. **Snapshot binário com delta por jogador** no lugar dos arrays de floats. A precisão é de 1 cm, 1,4° e 1/255 de vida. O delta exige entrega confiável e em ordem: o snapshot passou de `unreliable_ordered` para `reliable`, o que no WebSocket já acontecia de fato. Se um dia houver um transporte que perde pacotes (WebRTC), o encoder terá de mandar estados completos de tempos em tempos.
26. **Predição reaproveitando o código do servidor** (`ServerEntity` e `NavGrid` no cliente, com a grade montada da mesma cena) em vez de um movimento "parecido". Reconciliação por histórico com o atraso medido pelo ping, sem números de sequência de entrada: o movimento é determinístico a partir das intenções, e o erro medido ficou abaixo de meio metro com 200 ms.
27. **Só o movimento é previsto.** Ataque, coleta e NPC dependem de decisões do servidor (alcance, alvo vivo, perseguição); prever isso traria mais correções visíveis do que ganho.
28. **Atraso simulado no próprio cliente** (`--sim-lag-ms`) para testar a predição sem ferramentas externas.

12. **Limite de tentativas por conexão**, não por IP: reconectar zera a contagem. Um limite por IP fica para o proxy de produção (Fase 6).

## Fase 2 (2026-11-12)

1. **Item é um Dictionary** (uid, base, nível, raridade, sorte, extra, opções, posição) e trafega como `PackedInt32Array` de 10 inteiros (`ItemCodec`). As opções excelentes vão numa máscara de bits sobre a lista ordenada (no máximo 31).
2. **`ItemCatalog` compartilhado** calcula nome, tooltip e bônus dos dois lados com os mesmos dados; o servidor é quem aplica os bônus.
3. **Inventário 8x8 com itens de vários tamanhos** e interação "clique pega, clique solta" (como os MMOs clássicos), em vez do arrastar nativo da Godot: funciona igual com mouse e na Web e permite usar joia sobre item (parte 2).
4. **Ancestral = item de uma base que pertence a um conjunto, com raridade 2.** O bônus fixo é +10 no atributo do conjunto; os bônus de conjunto somam por número de peças.
5. **Aparência replicada por evento** (`rpc_appearance`, [base, nível, raridade] por slot visível) e não no snapshot: muda raramente.
6. **Brilho de refino como contorno (rim) + emissão leve + aura de partículas no +11.** Emissão forte na peça inteira deixava o placeholder com cara de plástico.
7. **Bônus percentuais aplicados depois das fórmulas** (vida e mana); atributos de item (ex.: +Energia ancestral) entram antes, nas fórmulas.
8. **Comandos de GM só com `--allow-gm`** no servidor, enviados por RPC. Fora isso, o servidor ignora.
10. **Nomes originais:** a "máquina de combinação" do MU virou a **Forja do Vórtice**; as joias equivalentes são Lágrima Consagrada (Bless), Fragmento de Alma (Soul), Gema do Vórtice (Chaos), Seiva Vital (Life) e Pedra da Gênese (Creation); os itens de proteção são o Talismã da Fortuna (+chance) e o Selo de Preservação (não destrói na falha).
11. **`RefineRules` e `RecipeBook` compartilhados:** o cliente mostra a chance exata que o servidor vai usar, sem duplicar regras.
12. **Itens na forja ficam no container 200** do próprio jogador. Fechar a janela ou se afastar devolve tudo (o que não couber vai para o chão, com posse do dono).
13. **O resultado de uma receita fica na mesa da forja** para o jogador retirar. Assim nunca se perde por falta de espaço.
14. **O refino superior exige joias exatas** (nem a mais nem a menos), como nas máquinas clássicas; a janela explica o que falta.
15. **A cidade é uma zona segura dentro da mesma região**, e não um mapa separado. A troca de região (com virada de página do diário) é escopo da Fase 4; até lá, o Refúgio das Cinzas fica ao sul das ruínas, atrás de muros, e passa a ser o ponto de chegada e de renascimento.
16. **Zona segura como retângulo nos dados** (`safe_zones`), checada no servidor: monstros ignoram e desistem de quem está dentro, o dano a jogadores é anulado e não se lança magia. O cliente usa os mesmos dados só para o aviso na tela.
17. **NPCs genéricos por papel** (`shop`, `storage`, `vortex_forge`) num `NpcSystem`: alcance, janela aberta e fechamento automático ficam num lugar só; a Forja virou um papel como os outros.
18. **Preços compartilhados (`ShopRules`):** o cliente mostra exatamente o que o servidor cobra ou paga. A venda paga 30% do valor, e o valor cresce com refino (quadrático), raridade, sorte, opção extra e opções excelentes. Um teste garante que nenhuma loja paga mais do que cobra.
19. **Itens empilháveis com `count`** no próprio item (o `ItemCodec` passou a 11 inteiros). Pilhas se completam ao receber; dividir pilhas fica para depois.
20. **Cofre como container 300** com grade própria no servidor, por personagem. Sem guardar Óbolos no cofre por enquanto: a moeda não se perde ao morrer, então não faria diferença. Sem persistência ainda: o cofre zera ao reconectar, como todo o resto, até a Fase 3.
21. **O "mago que vende magias" vende grimórios:** a classe tem uma lista de magias e outra de magias iniciais; as demais se aprendem usando um grimório. A máscara de magias aprendidas vai no estado do jogador (`PS.SPELLS`). A primeira é a Chuva de Brasas (área, nível 8).
22. **Atalhos de poção em Z e X**, porque Q e E já giram a câmera. Z usa o tônico mais forte que o nível permite.
23. **Venda com confirmação no cliente** (segundo clique em 3 s) para itens valiosos. O servidor não pede confirmação: a intenção já é explícita.
9. **A opção "Habilidade" do item (dar uma skill) ficou de fora:** o Feiticeiro tem só 3 magias e ainda não existe um sistema de skills por item. Vai ser reavaliada junto com as novas classes (Fase 5).

## Fase 1 (2026-11-12)

1. **O diário é gerado no servidor** a partir da posição simulada e enviado ao dono por RPC (protocolo v2). Motivo: autoridade (o teletransporte depende dele) e persistência por personagem.
2. **Grafite numa SubViewport acumulativa** (`CLEAR_MODE_NEVER`) em vez de `Line2D` com "bake" manual. Motivo: custo constante, escurecimento natural nas passagens repetidas e menos código. Risco: perda de contexto WebGL apaga a textura; a solução é pedir o estado completo de novo ao servidor (a fazer junto com a reconexão, na Fase 3).
3. **Rótulos e marcador fora da textura** (overlay desenhado a cada frame). Motivo: o que muda a cada frame não pode ir para a textura que nunca é limpa.
4. **Fonte provisória:** os nomes usam a fonte padrão da Godot, levemente inclinada. Uma fonte manuscrita livre (licença OFL, por exemplo Caveat) depende de baixar o arquivo, o que precisa de autorização.
5. **Som do lápis adiado:** o projeto ainda não tem nenhum áudio. Entra junto com a tela "Clique para entrar", que libera o áudio no navegador.
6. **A virada de página entre regiões fica para a Fase 4**, quando houver uma segunda região. A troca de folha já existe (`set_region`), só falta a animação.
7. **Diário em memória por conexão:** ao reconectar, a folha começa de novo. A persistência entra na Fase 3.
9. **Pathfinding com AStarGrid2D no servidor** em vez de `NavigationAgent3D`. Motivo: a simulação do servidor é 2D (XZ), determinística e headless; uma grade de 0,5 m é barata (23 mil células) e serve a jogadores e monstros. Os obstáculos saem da própria cena da região (grupo `obstacle`), então visual e colisão não divergem. Reavaliar se houver terreno com relevo.
10. **Fórmulas como `Expression` da Godot nos dados** (`"hp_max": "60 + (level-1)*1 + (vit-15)*2"`). Motivo: o balanceamento fica todo nos dados sem um interpretador próprio; funciona na Web.
11. **Ids de entidade:** jogador = peer id (positivo); monstro = id negativo. O tipo do monstro vai no snapshot como índice na lista ordenada de `monsters.json`, igual nos dois lados.
12. **Eventos de combate como RPCs separados** (conjuração, dano, ataque, morte, nível, drop, recarga, mensagem), enviados por peer. São de baixa frequência; os snapshots continuam binários.
13. **Partículas com `CPUParticles3D`** e um shader de partícula próprio (disco aditivo). Motivo: comportamento previsível no WebGL 2; a quantidade segue o preset de qualidade (`data/config/vfx.json`).
14. **Itens são só uma lista no servidor na Fase 1.** O inventário em grade, os equipamentos e o refino com joias são o escopo da Fase 2.
15. **Sem predição local ainda** (continua a decisão 5 da Fase 0): o clique tem cerca de 120 ms de atraso visual mais a latência. Entra na Fase 3.
8. **Escala:** 13 px por metro numa folha de 1024 px (cobre ±39 m). O teste `test_regions_and_symbols` garante que a folha cobre o mundo.

## Fase 0 (2026-11-12)

1. **Um único projeto para cliente, servidor e bot**, com o papel escolhido por argumento (`--server`, `--bot`). Motivo: o protocolo e as regras ficam num só lugar, como pede a especificação.
2. **Todos os RPCs no autoload `Net`.** Motivo: na multiplayer API da Godot, o RPC exige o mesmo caminho de nó nos dois lados, e um ponto único evita divergência. O restante do código usa sinais.
3. **Input Map registrado por código a partir de `data/config/input.json`**, e não escrito no `project.godot`. Motivo: controles orientados a dados e fáceis de editar; mais tarde, a tela de opções reescreve o mesmo JSON (salvo em `user://`).
4. **Snapshots enviados por peer (`rpc_id`), não em broadcast.** Motivo: pular sockets que já estão fechando e preparar o interest management.
5. **Sem predição local na Fase 0.** O próprio personagem também é interpolado com 120 ms de atraso. Motivo: é o mais simples que funciona; em localhost não se percebe. A predição entra na Fase 3.
6. **Movimento sem navmesh na Fase 0.** O clique vira um ponto no plano y=0 (interseção do raio com o plano, sem física) e o servidor anda em linha reta. Motivo: a prova de conceito é de rede. `NavigationAgent3D` entra na Fase 1.
7. **Executor de testes próprio** (`tests/run_tests.gd`) em vez de GUT ou gdUnit4. Motivo: zero dependências enquanto há poucos testes. Reavaliar na Fase 1 ou 2.
8. **Névoa em duas camadas** (névoa do `Environment` mais planos com shader de ruído). Motivo: não há névoa volumétrica no Compatibility; a névoa do `Environment` renderizou corretamente no desktop com o Compatibility, mas **falta confirmar na build Web**.
9. **Glow e ajuste de cor (saturação/contraste) do `Environment` ligados.** Funcionaram no Compatibility desktop (cristais e círculo rúnico brilham). **Falta confirmar na build Web**; se falharem, o plano B são sprites aditivos.
10. **Fullscreen em F10.** Motivo: o navegador captura F11 e não deixa o jogo usá-lo.
11. **Porta padrão 7777** para o servidor de jogo; em produção ela fica atrás do proxy TLS em `/ws`.
13. **Iluminação mais clara depois das referências** (lua com energia 1,0 e ambiente 0,6). Motivo: em todas as referências o chão aparece com textura e sombra nítida; o tom sombrio vem da paleta, não da escuridão.
14. **Orbes de vida e mana colados à barra de skills, no centro** (como na ref_03), em vez de nas laterais da tela. Motivo: ficam mais perto do olhar e funcionam melhor em telas largas do navegador.
15. **Handshake WebSocket de 15 s e conexão adiada por 10 frames** (`network.json`). Motivo: na Web, a compilação de shaders do primeiro frame trava a página e estourava o timeout padrão de 3 s.
16. **Guias 8 e 9 confirmados**: névoa do `Environment`, glow e ajuste de cor funcionam na build Web (WebGL 2).
12. **Projeto em pasta sincronizada pelo OneDrive.** Atenção: a pasta `.godot/` (cache) é grande e muda muito. Se a sincronização atrapalhar, excluí-la da sincronização no OneDrive ou mover o projeto para fora dele.
