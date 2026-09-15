# Interface atual

## Janela e menu

- A app corre em segundo plano, sem aparecer na Dock ou na barra de menus do
  macOS.
- O compositor é aberto através de um atalho global, configurável nas
  definições e predefinido como `⌘E`.
- O compositor é uma janela nativa com tabs de workspaces.
- A janela tem tamanho mínimo de `760 × 500` e abre com tamanho inicial de
  `980 × 680`.

## Compositor

- A barra lateral esquerda contém a biblioteca de snippets.
- A área principal mostra o nome da sessão, o botão `Enviar` e o editor
  multilinear.
- O botão `Enviar` usa `⌘Return` e só fica ativo quando existe texto útil.
- O editor recebe foco e posiciona o cursor no fim quando um rascunho é
  capturado.
- As definições permitem ativar o arranque automático no login.
- As definições permitem personalizar e repor o atalho global do compositor.

## Snippets

- A barra lateral mostra os snippets e permite criar um novo através de `+`, ao
  lado da secção `Todos`.
- Os favoritos aparecem primeiro, limitados aos nove primeiros favoritos.
- Os templates aparecem diretamente em nove slots, de `⌘1` a `⌘9`.
- Templates novos entram no próximo slot disponível e podem ser reordenados por
  drag-and-drop.
- Cada snippet pode ser inserido, editado ou apagado.
- O editor de snippet contém nome, conteúdo e opção para o mostrar nos
  favoritos.

## Skills

- A pesquisa de skills aparece sobre o editor quando existe uma referência
  iniciada por `$`.
- A sugestão selecionada fica realçada e pode ser escolhida pelo teclado.

## Histórico

- A barra lateral contém uma secção `History` com os prompts enviados mais
  recentemente.
- A pesquisa filtra pelo conteúdo do prompt e pelo nome da sessão.
- Clicar numa entrada carrega-a no editor.
- Cada entrada tem uma ação para apagar; limpar todo o histórico exige
  confirmação.

## Imagens

- `⌥V` insere a imagem do clipboard como uma referência `[Image #N]` no editor.
- `⌘V` continua reservado para paste normal de texto.
- O botão de imagem junto ao envio abre uma pré-visualização com confirmação
  antes de inserir a imagem.
