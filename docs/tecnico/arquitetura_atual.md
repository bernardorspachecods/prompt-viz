# Arquitetura atual

Este documento descreve as fronteiras e os contratos técnicos implementados.
O comportamento observável está em [`../produto/requisitos.md`](../produto/requisitos.md),
[`../produto/fluxos.md`](../produto/fluxos.md) e
[`../produto/ui_ux.md`](../produto/ui_ux.md).

## Estrutura atual

```text
App shell macOS (background agent)
  ├── WorkspaceStore ────────► drafts/sessions
  ├── SnippetLibrary ────────► snippets
  ├── PromptHistoryStore ────► sent prompts
  ├── App state ─────────────► editor + insertion
  └── TerminalAutomation ────► focus + paste + Return
```

O desenho separa responsabilidades em módulos com interfaces pequenas:

### `WorkspaceStore`

Gere a criação, atualização e remoção de workspaces. A seleção visual e a
sessão ativa são coordenadas pelo estado da app. A UI não conhece a forma de
persistência nem os detalhes de identificação de tabs.

### `SnippetLibrary`

Gere snippets globais, favoritos e edição. A UI recebe modelos prontos para apresentar.

### `PromptHistoryStore`

Gere as entradas dos prompts enviados com sucesso, ordenadas da mais recente
para a mais antiga, com pesquisa por prompt/sessão e limite de 100 entradas.
`LocalPromptHistoryPersistence` serializa as entradas em `UserDefaults`.

### `TerminalAutomation`

É a fronteira entre a app e as APIs de Acessibilidade do macOS. Identifica a
sessão ativa, captura o draft visível do Codex, foca a tab correta e executa
substituição + `Return` no envio. A lógica de parsing fica no domínio puro e é
exercida pelo contract runner.

## Fronteiras SwiftUI/AppKit

- **SwiftUI:** janela principal, tabs nativas de workspaces, editor, snippets, estados e comandos.
- **AppKit/Foundation:** observação da app ativa, Acessibilidade do Terminal.app, clipboard, eventos de teclado e registo do atalho global.
- **Domínio puro:** modelos, store, pesquisa e referências de imagens.

A UI apresenta estado e envia comandos; não deve chamar diretamente `AXUIElement`, escrever na clipboard ou sintetizar teclas.
O arranque não apresenta pedidos de permissão. A app tenta identificar o Terminal quando o utilizador abre o compositor e só oferece as Definições de Acessibilidade se a API devolver explicitamente que está desativada.

O `PromptVizModel` compõe os efeitos externos através de interfaces internas
pequenas. As implementações reais cobrem automação do Terminal, persistência,
descoberta de skills, clipboard, login e atalhos; a inicialização por defeito é
a composição usada pela app e a inicialização por dependências permite testar a
coordenação sem Terminal.app real.

### Handoff do input Codex

O `Workspace.draft` é capturado uma vez quando `⌘E` é usado e passa a ser propriedade do editor até ao envio.

As invariantes são:

- `⌘E` captura o último bloco iniciado por `›` e terminado pela linha de estado do Codex.
- A parser remove a margem visual das linhas reais e junta continuações causadas por wrap.
- Depois da captura, o editor recebe o foco e o cursor fica no fim lógico do draft, com um espaço de continuação se o texto não terminar em whitespace.
- As alterações posteriores existem apenas no editor da app até ao envio.
- O envio substitui o conteúdo atual do campo e envia `Return` depois de uma breve pausa para o paste concluir; não depende de readback AX do texto.
- As referências `[Image #N]` são resolvidas contra os anexos do draft; a
  automação cola cada segmento de texto ou PNG pela ordem original.
- O editor identifica referências de imagem e skills escolhidas como tokens
  inline, aplica-lhes `NSColor.controlAccentColor` e expande edições parciais
  para o intervalo completo do token; texto `$...` ainda não escolhido não é
  tratado como token.
- A seleção e validação da sessão acontecem antes de qualquer tecla ser publicada.

### Troca de workspaces

A troca entre workspaces da app atualiza imediatamente a seleção, o editor e a sessão lógica em memória. Pede também a seleção assíncrona da tab do Terminal numa fila serial, sem bloquear a interface. O envio usa a mesma fila de forma síncrona e valida a sessão imediatamente antes de publicar teclas.

## Identificação de sessões

O adapter lê a tab selecionada no Terminal.app e usa o seu TTY como identificador da sessão. O TTY e o PID são dados do adapter; não devem vazar para as views como lógica de descoberta. O título e a geometria da janela são apenas metadados de apresentação.

O inventário de tabs é válido para remoção apenas quando a enumeração percorreu
todas as janelas e tabs sem erros, o número de TTYs lidos coincide com o número
de tabs e o inventário não está vazio. Uma resposta incompleta ou vazia não
remove workspaces. Uma sessão só é removida depois de duas observações completas
consecutivas; se reaparecer entretanto, o workspace é mantido.

## Persistência

- Snippets são serializados em `UserDefaults.standard`.
- Eventos e erros de runtime são registados em `~/Library/Logs/PromptViz.log` e
  no sistema de logs do macOS.
- Workspaces e rascunhos ficam em memória e não são restaurados entre execuções.
- O histórico de prompts enviados é persistido localmente em `UserDefaults` e
  não é partilhado com outros dispositivos, incluindo os dados dos anexos de
  imagem.
- A persistência de snippets está atrás de uma interface pequena para permitir
  testar o domínio sem depender diretamente de `UserDefaults`.

## Limites técnicos atuais

- Acessibilidade é necessária para automatizar o Terminal.app.
- O Terminal.app expõe a TUI como um `AXTextArea` com histórico e layout visual, não como um campo Codex separado; a extração depende do formato atual da TUI.
- Wraps visuais e novas linhas reais são distinguidos pelas margens observadas
  na TUI.
- A app não consegue garantir semanticamente que o Codex está pronto para receber input.
- Alterar título ou estrutura de tabs pode afetar a identificação da sessão; o adapter deve encapsular essa instabilidade.
- O envio deve falhar de forma explícita se não houver Terminal.app ou uma sessão-alvo válida.
