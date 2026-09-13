# Visão e plano atual

## Objetivo

Criar uma aplicação desktop pessoal para macOS que permita escrever, melhorar e enviar prompts para diferentes sessões do Codex no Terminal.app sem copiar e colar manualmente entre um bloco de notas e o terminal.

## Problema

Escrever prompts longas diretamente no terminal é desconfortável. O fluxo atual exige escrever num bloco de notas, copiar o texto, colá-lo no terminal e submeter a mensagem. Esse trabalho interrompe o raciocínio e dificulta a reutilização de instruções frequentes.

## Experiência pretendida

1. O utilizador abre o Codex num tab do Terminal.app.
2. Clica no botão flutuante ou usa um atalho global.
3. A app abre ou foca o workspace associado àquele tab.
4. O utilizador escreve a prompt, usa snippets e preenche templates.
5. Ao clicar em `Enviar`, a app cola o texto no tab correto e pressiona `Return`.
6. O editor permanece aberto, limpa o texto e fica pronto para a prompt seguinte.

## Decisões de UX confirmadas

### Shell e abertura

- A app é nativa de macOS e usa Swift/SwiftUI.
- A app vive principalmente na barra de menus.
- Existe um botão flutuante discreto sobre a zona final da linha de escrita da janela ativa do Terminal.app.
- O botão acompanha a janela/tab ativa e não fica fixo num canto do monitor.
- Existe também um atalho global para abrir rapidamente o compositor.
- O onboarding de Acessibilidade é curto e informal, adequado a uma ferramenta pessoal.

### Workspaces e sessões

- Existe um workspace por tab/sessão do Terminal.app.
- Uma única janela da app apresenta os workspaces numa barra nativa de tabs do macOS.
- Cada workspace mantém o seu próprio rascunho.
- `Ctrl+Tab` avança entre workspaces e `Ctrl+Shift+Tab` volta ao anterior.
- A linha atualmente escrita no `zsh` do tab ativo é sincronizada em tempo real para o editor do workspace correspondente.
- Ao voltar a um tab, o rascunho desse tab continua disponível.
- Ao fechar o tab do Terminal, o workspace associado desaparece.
- A app não lê nem interpreta o estado interno do Codex.

### Snippets e templates

- A biblioteca de snippets é global e está disponível em todos os workspaces.
- O utilizador pode criar, editar, apagar e organizar os seus snippets.
- Snippets podem ser texto fixo ou templates com campos `{{nome}}`.
- Ao escrever `$`, o compositor apresenta as skills locais do Codex para pesquisa e seleção.
- Os campos são preenchidos e percorridos com `Tab`.
- Os snippets favoritos aparecem numa barra compacta.
- O restante catálogo pode ser pesquisado numa paleta.
- Snippets frequentes podem ter atalhos de teclado.

### Envio e privacidade

- `Enviar` cola a prompt no tab-alvo e pressiona `Return` automaticamente.
- O editor permanece aberto depois do envio e limpa o texto.
- O estado do rascunho é guardado enquanto a sessão existe.
- Não existe histórico de prompts enviadas por defeito.
- Não existem contas, cloud, sincronização ou chamadas de IA.
- O utilizador não precisa de uma deteção semântica de que o Codex está pronto; a app trabalha com o tab ativo identificado pelo Terminal.app.

## Escopo do MVP

- Aplicação local para macOS.
- Shell de menu bar e janela principal SwiftUI.
- Botão flutuante condicionado ao Terminal.app ativo.
- Atalho global para abrir/focar a app.
- Associação de workspaces a tabs/sessões do Terminal.app.
- Rascunhos separados por workspace.
- Biblioteca local global de snippets.
- Snippets fixos, favoritos e pesquisa.
- Templates com campos nomeados e navegação por `Tab`.
- Envio por colar + `Return` através de Acessibilidade.
- Limpeza do editor depois do envio.
- Contract runner para regras puras sem dependências gráficas.

## Fora do escopo inicial

- Outros terminais, como iTerm2.
- Reescrita ou avaliação de prompts por IA.
- Cloud sync, contas e colaboração.
- Histórico de prompts.
- Deteção semântica do estado do Codex.
- Distribuição pela App Store.

## Evolução futura

- Suporte a outros terminais.
- Histórico opcional e pesquisa de prompts enviadas.
- Sincronização entre Macs.
- Ações de melhoria de prompt usando um modelo local ou externo.
- Templates mais avançados, com validação e tipos de campo.

## Cenário de sucesso do MVP

O utilizador mantém vários chats do Codex em tabs diferentes, escreve prompts diretamente no Prompt Viz, reutiliza frases como “sê honesto” ou “sem bias”, preenche templates e envia cada prompt para o chat certo sem alternar para um bloco de notas.
