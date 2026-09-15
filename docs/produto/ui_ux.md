# Interface atual

## Janela e menu

- A app aparece na barra de menus do macOS.
- O menu contém a ação `Abrir compositor` e a ação para sair.
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

## Snippets

- A barra lateral permite pesquisar snippets e criar um novo através de `+`.
- Os favoritos aparecem primeiro, limitados aos nove primeiros favoritos, com
  atalhos `⌘⌥1` a `⌘⌥9`.
- Cada snippet pode ser inserido, editado ou apagado.
- O editor de snippet contém nome, conteúdo e opção para o mostrar nos
  favoritos.

## Templates e skills

- Templates mostram os campos encontrados no conteúdo e focam o primeiro campo
  ao abrir o formulário.
- A pesquisa de skills aparece sobre o editor quando existe uma referência
  iniciada por `$`.
- A sugestão selecionada fica realçada e pode ser escolhida pelo teclado.
