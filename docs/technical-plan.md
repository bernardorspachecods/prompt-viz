# Plano técnico inicial

Este documento transforma a [visão atual](vision.md) num plano de implementação. `vision.md` é a autoridade para produto e UX; este documento é a autoridade para arquitetura, estado técnico e validação.

## Estado de implementação — 2026-09-11

- `Package.swift` define um pacote executável macOS.
- Os modelos puros de workspace e snippet estão implementados.
- `TemplateEngine` encontra campos nomeados e renderiza valores.
- `WorkspaceStore` cria/reutiliza workspaces por sessão, mantém rascunhos separados e remove workspaces fechados.
- `SnippetLibrary` fornece snippets globais, favoritos, pesquisa e operações de edição.
- A biblioteca de snippets é persistida localmente em `UserDefaults`.
- A shell SwiftUI está implementada com menu bar, janela principal, editor, lista de workspaces e editor de snippets/templates.
- O adapter de automação do Terminal.app está implementado com identificação da app ativa, clipboard, `Cmd+V`, `Return` e pedido de Acessibilidade.
- O botão flutuante é discreto, ancorado à janela ativa do Terminal.app, junto ao fim da linha de escrita, e acompanha alterações de janela, tab e dimensão.
- O empacotamento local usa a identidade Apple Development disponível neste Mac, em vez de assinatura ad-hoc, para manter estável a autorização de Acessibilidade entre builds.
- Os nove primeiros snippets favoritos têm atalhos `⌘⌥1`–`⌘⌥9`.
- A associação de janelas usa o `CGWindowID` e a app verifica periodicamente se as janelas ainda existem, removendo o workspace quando uma janela fecha.
- A sessão focada usa o `CGWindowID` da janela do Terminal, obtido ao cruzar a janela AX com a lista de janelas do processo; se essa informação não estiver disponível, mantém-se o fallback por processo para permitir testar o envio.
- A sincronização Terminal → editor usa um hook opcional de `zsh` (`scripts/prompt-viz-zsh.zsh`) que publica o `BUFFER` por TTY em `/tmp/prompt-viz`; a app associa esse TTY ao workspace através do dicionário AppleScript do Terminal.app.

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

É o seam entre a app e as APIs de Acessibilidade do macOS. Identifica a sessão ativa, foca-a e executa colar + `Return`. A lógica restante não depende de AppKit Accessibility e pode usar um fake no contract runner.

## Fronteiras SwiftUI/AppKit

- **SwiftUI:** janela principal, lista lateral de workspaces, editor, snippets, templates, estados e comandos.
- **AppKit/Foundation:** menu bar, janela/painel flutuante, observação da app ativa, Acessibilidade do Terminal.app, clipboard e eventos de teclado.
- **Domínio puro:** modelos, store, pesquisa e expansão de templates.

A UI apresenta estado e envia comandos; não deve chamar diretamente `AXUIElement`, escrever na clipboard ou sintetizar teclas.
O arranque não apresenta pedidos de permissão. A app tenta identificar o Terminal quando o utilizador abre o compositor e só oferece as Definições de Acessibilidade se a API devolver explicitamente que está desativada.
No envio, a app coloca a prompt na clipboard e envia diretamente `Cmd+V` e `Return` ao processo do Terminal.app através de eventos de teclado direccionados ao PID. Assim a app depende apenas da autorização de Acessibilidade do próprio Prompt Viz e não do processo auxiliar `System Events`.

## Identificação de sessões

O adapter usa a janela focada no Terminal.app e produz um identificador estável durante a vida dessa janela, preferindo o `CGWindowID` ao título (que pode mudar). O identificador e o título são dados do adapter; não devem vazar para as views como lógica de descoberta.

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

- `swift run PromptVizContractRunner` — PASS, 7 contratos.
- `swift build --product PromptViz` — PASS.
- `./scripts/build-app.sh` — PASS; produziu `dist/PromptViz.app` arm64.
- `./scripts/build-app.sh` assina com uma identidade Apple Development estável; a identidade pode ser substituída por `PROMPT_VIZ_SIGNING_IDENTITY`.
- `swift test` não é uma validação disponível neste toolchain: as Command Line Tools instaladas não expõem o módulo `XCTest`.

## Riscos e limites

- Acessibilidade é necessária para automatizar o Terminal.app.
- A sincronização em tempo real requer a integração `zsh` instalada e autorização de Automação para ler o TTY do Terminal.app.
- A app não consegue garantir semanticamente que o Codex está pronto para receber input.
- Alterar título ou estrutura de tabs pode afetar a identificação da sessão; o adapter deve encapsular essa instabilidade.
- O envio deve falhar de forma explícita se não houver Terminal.app ou uma sessão-alvo válida.
