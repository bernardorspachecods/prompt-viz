# Arquitetura técnica

Este documento descreve as fronteiras e contratos técnicos da aplicação. A intenção do produto está em [vision.md](vision.md); o funcionamento verificado está em [current-state.md](current-state.md).

## Arquitetura recomendada

```text
App shell macOS
  ├── WorkspaceStore ────────► drafts/sessions
  ├── SnippetLibrary ────────► snippets/templates
  ├── App state ─────────────► editor + insertion
  └── TerminalAutomation ────► focus + paste + Return
```

O desenho separa responsabilidades em módulos com interfaces pequenas:

### `WorkspaceStore`

Gere a criação, seleção, atualização e remoção de workspaces. A UI não conhece a forma de persistência nem os detalhes de identificação de tabs.

### `SnippetLibrary`

Gere snippets globais, favoritos, pesquisa e edição. A UI recebe modelos prontos para apresentar e não implementa regras de pesquisa ou expansão.

### `TerminalAutomation`

É o seam entre a app e as APIs de Acessibilidade do macOS. Identifica a sessão ativa, captura o draft visível do Codex, foca a tab correta e executa substituição + `Return`. A lógica de parsing fica no domínio puro e pode usar um fake no contract runner.

## Fronteiras SwiftUI/AppKit

- **SwiftUI:** janela principal, tabs nativas de workspaces, editor, snippets, templates, estados e comandos.
- **AppKit/Foundation:** menu bar, observação da app ativa, Acessibilidade do Terminal.app, clipboard e eventos de teclado.
- **Domínio puro:** modelos, store, pesquisa e expansão de templates.

A UI apresenta estado e envia comandos; não deve chamar diretamente `AXUIElement`, escrever na clipboard ou sintetizar teclas.
O arranque não apresenta pedidos de permissão. A app tenta identificar o Terminal quando o utilizador abre o compositor e só oferece as Definições de Acessibilidade se a API devolver explicitamente que está desativada.

### Handoff do input Codex

O `Workspace.draft` é capturado uma vez quando `⌘E` é usado e passa a ser propriedade do editor até ao envio.

As invariantes são:

- `⌘E` captura o último bloco iniciado por `›` e terminado pela linha de estado do Codex.
- A parser remove a margem visual das linhas reais e junta continuações causadas por wrap.
- As alterações posteriores existem apenas no editor da app até ao envio.
- O envio substitui o conteúdo atual do campo e só envia `Return` depois da confirmação por Acessibilidade.
- Qualquer divergência bloqueia o envio e preserva o texto do editor.

## Identificação de sessões

O adapter lê a tab selecionada no Terminal.app e usa o seu TTY como identificador da sessão. O TTY e o PID são dados do adapter; não devem vazar para as views como lógica de descoberta. O título e a geometria da janela são apenas metadados de apresentação.

Se a sessão deixar de existir, o adapter notifica o `WorkspaceStore`, que remove o workspace correspondente.

## Persistência

- Guardar snippets e preferências localmente.
- Guardar o rascunho apenas enquanto a sessão correspondente existe.
- Não guardar conteúdo histórico de prompts enviadas.
- Manter a persistência atrás de uma interface pequena para poder testar o domínio sem filesystem ou UserDefaults.

## Riscos e limites

- Acessibilidade é necessária para automatizar o Terminal.app.
- O Terminal.app expõe a TUI como um `AXTextArea` com histórico e layout visual, não como um campo Codex separado; a extração depende do formato atual da TUI.
- Wraps visuais e novas linhas reais são distinguidos pelas margens observadas na TUI e exigem validação manual após atualizações do Codex.
- A app não consegue garantir semanticamente que o Codex está pronto para receber input.
- Alterar título ou estrutura de tabs pode afetar a identificação da sessão; o adapter deve encapsular essa instabilidade.
- O envio deve falhar de forma explícita se não houver Terminal.app ou uma sessão-alvo válida.
