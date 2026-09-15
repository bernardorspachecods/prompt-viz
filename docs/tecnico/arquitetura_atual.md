# Arquitetura atual

Este documento descreve as fronteiras e os contratos técnicos implementados.
O comportamento observável está em [`../produto/requisitos.md`](../produto/requisitos.md),
[`../produto/fluxos.md`](../produto/fluxos.md) e
[`../produto/ui_ux.md`](../produto/ui_ux.md).

## Estrutura atual

```text
App shell macOS
  ├── WorkspaceStore ────────► drafts/sessions
  ├── SnippetLibrary ────────► snippets/templates
  ├── App state ─────────────► editor + insertion
  └── TerminalAutomation ────► focus + paste + Return
```

O desenho separa responsabilidades em módulos com interfaces pequenas:

### `WorkspaceStore`

Gere a criação, atualização e remoção de workspaces. A seleção visual e a
sessão ativa são coordenadas pelo estado da app. A UI não conhece a forma de
persistência nem os detalhes de identificação de tabs.

### `SnippetLibrary`

Gere snippets globais, favoritos, pesquisa e edição. A UI recebe modelos prontos para apresentar e não implementa regras de pesquisa ou expansão.

### `TerminalAutomation`

É a fronteira entre a app e as APIs de Acessibilidade do macOS. Identifica a
sessão ativa, captura o draft visível do Codex, foca a tab correta e executa
substituição + `Return` no envio. A lógica de parsing fica no domínio puro e é
exercida pelo contract runner.

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
- Depois da captura, o editor recebe o foco e o cursor fica no fim lógico do draft, com um espaço de continuação se o texto não terminar em whitespace.
- As alterações posteriores existem apenas no editor da app até ao envio.
- O envio substitui o conteúdo atual do campo e envia `Return` depois de uma breve pausa para o paste concluir; não depende de readback AX do texto.
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
- Workspaces e rascunhos ficam em memória e não são restaurados entre execuções.
- Não existe persistência de histórico de prompts enviadas.
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
