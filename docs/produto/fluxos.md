# Fluxos atuais

## Abrir o compositor

1. O Terminal.app fica em primeiro plano com uma sessão selecionada.
2. O utilizador usa `⌘E` para abrir o compositor.
3. A app identifica o TTY e o título da sessão ativa.
4. A app lê o texto visível do compositor do Codex e cria ou reutiliza o
   workspace dessa sessão.
5. O workspace é selecionado, o rascunho é carregado e o editor recebe o foco.

Se o Terminal.app não estiver ativo, a sessão não puder ser identificada ou a
estrutura acessível do compositor não estiver disponível, a app apresenta um
erro. Quando aplicável, o erro inclui uma ação para abrir as definições de
Acessibilidade ou Automação.

## Editar e inserir conteúdo

O utilizador pode escrever diretamente no editor ou inserir um snippet da barra
 lateral.

Ao escrever `$`, o editor mostra as skills encontradas localmente. As sugestões
podem ser escolhidas com o rato, `↑`, `↓` e `Return`.

Ao premir `⌥V` com uma imagem no clipboard, a app insere uma referência
`[Image #N]` na posição do cursor e guarda o anexo correspondente. `⌘V` mantém
o paste normal de texto. As referências de imagem e as skills aparecem com a
cor de acento nativa do macOS depois de confirmadas; apagar ou substituir
qualquer parte remove ou substitui o token completo. Enquanto uma skill está a
ser pesquisada, `$...` continua texto normal e editável.

Ao clicar no botão de imagem, a app abre uma janela de pré-visualização. A
imagem só é inserida depois de o utilizador escolher `Paste image`; `Cancel`
fecha a janela sem alterar o editor.

## Alternar workspace

Selecionar uma tab da janela da app guarda o rascunho atual, muda o editor para
o rascunho do workspace escolhido e pede a seleção da sessão correspondente no
Terminal.app. `Ctrl+Tab` avança e `Ctrl+Shift+Tab` recua.

## Enviar

1. O utilizador escolhe `Enviar` ou usa `⌘Return`.
2. A app confirma que existe uma sessão ativa e volta a selecionar o seu TTY.
3. A app valida que a sessão selecionada continua a ser a esperada.
4. O conteúdo é colado no compositor do Codex e `Return` é enviado.
5. Após um envio bem-sucedido, o rascunho do workspace é limpo.
6. O prompt enviado é acrescentado ao histórico local.

Quando existem imagens, o texto e cada anexo são colados pela ordem em que
aparecem no prompt antes de `Return` ser enviado.

O botão fica indisponível quando o editor contém apenas espaços ou linhas
vazias.

## Fechar workspace

Fechar a tab da app remove o workspace correspondente. A aplicação também
observa periodicamente as sessões do Terminal.app e remove workspaces apenas
depois de confirmar que a sessão deixou de existir.

## Recuperar um prompt do histórico

1. O utilizador pesquisa opcionalmente pelo texto do prompt ou pelo nome da
   sessão.
2. Seleciona uma entrada do histórico.
3. A app carrega o prompt no editor atual e coloca o cursor no fim.
4. O utilizador pode editar e enviar o prompt novamente, incluindo os anexos de
   imagem guardados.

Uma entrada individual pode ser apagada pelo botão correspondente. O histórico
completo pede confirmação antes de ser limpo.
