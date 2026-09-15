# Plano técnico inicial

Este documento transforma a [visão atual](vision.md) num plano de implementação. `vision.md` é a autoridade para produto e UX; este documento é a autoridade para arquitetura, estado técnico e validação.

## Estado de implementação — 2026-09-15

- `Package.swift` define um pacote executável macOS.
- Os modelos puros de workspace e snippet estão implementados.
- `TemplateEngine` encontra campos nomeados e renderiza valores.
- `WorkspaceStore` cria/reutiliza workspaces por sessão, mantém rascunhos separados e remove workspaces fechados.
- `SnippetLibrary` fornece snippets globais, favoritos, pesquisa e operações de edição.
- A biblioteca de snippets é persistida localmente em `UserDefaults`.
- A shell SwiftUI está implementada com menu bar, janela principal, tabs nativas de workspaces, editor e editor de snippets/templates.
- O adapter de automação do Terminal.app identifica a app ativa, lê o `AXTextArea` da janela e suporta clipboard, `Ctrl+A`/`Ctrl+K`, `Cmd+V`, `Return` e pedido de Acessibilidade.
- O compositor pode ser aberto com `⌘E` ou pelo item do Prompt Viz na menu bar; não há UI persistente sobre as janelas do Terminal.app.
- O empacotamento local usa a identidade Apple Development disponível neste Mac, em vez de assinatura ad-hoc, para manter estável a autorização de Acessibilidade entre builds.
- Os nove primeiros snippets favoritos têm atalhos `⌘⌥1`–`⌘⌥9`.
- A associação de sessões usa o TTY da tab do Terminal.app como identidade estável durante a vida da sessão; o PID do processo é guardado separadamente apenas para envio de teclas.
- A app enumera periodicamente os TTYs de todas as tabs do Terminal.app através do seu dicionário AppleScript e remove o workspace quando o TTY deixa de existir.
- A janela AX e o `CGWindowID` são usados apenas para geometria visual e contexto da janela, nunca para distinguir tabs. Se a tab selecionada não expuser um TTY, a app falha explicitamente em vez de usar um fallback por processo que possa confundir sessões.
- A sincronização de input só fica ativa quando o Terminal.app está em primeiro plano e a tab selecionada corresponde ao workspace ligado; ao mudar para outra janela ou tab, a app suspende o espelhamento e retoma-o ao voltar à sessão original.
- O Codex TUI é tratado separadamente: a app lê o conteúdo renderizado pelo `AXTextArea`, extrai o draft atual através de `CodexTerminalInputParser` e, no envio, substitui o input com `Ctrl+A`/`Ctrl+K` + paste. O envio só carrega `Return` depois de confirmar novamente o draft através da Acessibilidade.
- O catálogo de skills é read-only: descobre manifests `SKILL.md`, expõe nome e descrição no compositor e insere apenas a invocação `$skill-name`, deixando o carregamento para o Codex.

O executável pode ser empacotado como `dist/PromptViz.app` através de `scripts/build-app.sh`.

## Arquitetura recomendada

```text
App shell macOS
  ├── WorkspaceStore ────────► drafts/sessions
  ├── SnippetLibrary ────────► snippets/templates
  ├── PromptComposer ────────► editor + insertion
  └── TerminalAutomation ────► focus + paste + Return
```

O desenho mantém três módulos profundos com interfaces pequenas:

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
No envio para o Codex, o adapter limpa o campo atual, cola o editor completo e confirma que o draft reconstruído corresponde ao texto esperado antes de enviar `Return`. Assim a app não acrescenta o editor ao texto que já estava na TUI.
Antes do envio, o adapter seleciona explicitamente a tab cujo TTY pertence ao workspace, eleva essa janela do Terminal e só depois valida a sessão e publica as teclas.
Enquanto uma superfície está em primeiro plano, ela é a proprietária temporária da edição. A app não aceita uma versão concorrente do Terminal durante uma atualização pendente; se a confirmação falhar, preserva o texto e bloqueia o envio.

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

## Validação

O projeto usa um executable contract runner em vez de depender de `swift test`, porque o CommandLineTools deste ambiente não expõe `XCTest`.

O runner deve validar:

- campos de templates na ordem de aparição;
- renderização de campos e campos repetidos;
- reutilização de um workspace pela mesma sessão;
- separação de rascunhos entre sessões;
- remoção do workspace ao fechar a sessão;
- favoritos e pesquisa de snippets;
- exemplos iniciais da biblioteca.

A integração de Acessibilidade para envio, a estabilidade do identificador de tabs, o posicionamento visual do botão flutuante sobre a linha de escrita e a remoção automática quando um tab fecha exigem validação manual num Mac com permissões concedidas.

### Última validação local

- `swift run PromptVizContractRunner` — PASS, 25 checks, incluindo parsing do input Codex.
- `swift build --product PromptViz` — PASS.
- `./scripts/build-app.sh` — PASS; produziu `dist/PromptViz.app` arm64.
- `./scripts/build-app.sh` assina com uma identidade Apple Development estável; a identidade pode ser substituída por `PROMPT_VIZ_SIGNING_IDENTITY`.
- `swift test` não é uma validação disponível neste toolchain: as Command Line Tools instaladas não expõem o módulo `XCTest`.

## Riscos e limites

- Acessibilidade é necessária para automatizar o Terminal.app.
- O Terminal.app expõe a TUI como um `AXTextArea` com histórico e layout visual, não como um campo Codex separado; a extração depende do formato atual da TUI.
- Wraps visuais e novas linhas reais são distinguidos pelas margens observadas na TUI e exigem validação manual após atualizações do Codex.
- A app não consegue garantir semanticamente que o Codex está pronto para receber input.
- Alterar título ou estrutura de tabs pode afetar a identificação da sessão; o adapter deve encapsular essa instabilidade.
- O envio deve falhar de forma explícita se não houver Terminal.app ou uma sessão-alvo válida.
