# Estado atual da aplicação

Este documento regista apenas comportamento observado ou validado por comandos reproduzíveis. O baseline é o commit `11fff39`.

## Estado geral

Captura e edição estão verificadas no baseline. O envio está parcial; o detalhe da falha está no bloco correspondente.

## Funcionalidades verificadas

- Build Swift do produto `PromptViz`.
- Contract runner do domínio.
- `⌘E` identifica a tab ativa do Terminal.app por TTY.
- A janela do Terminal expõe a TUI do Codex como `AXTextArea` com `AXValue`.
- Prompts multilineares são capturadas.
- Wraps visuais de linhas longas foram observados e reconstruídos.
- O texto capturado aparece rapidamente no editor da app.
- Depois de `⌘E`, o editor recebe o foco e o cursor é colocado no fim do draft; a app garante um espaço de continuação quando o AX não o devolve.
- O fluxo observado não duplicou o texto já existente no terminal.
- Workspaces usam o TTY da sessão como identidade e não o título da janela.
- O código antigo de sincronização contínua via `zsh` foi removido.

## Parcial ou com falhas conhecidas

- O envio agora valida a sessão antes de escrever, substitui o campo com `Ctrl+A` + `Ctrl+K` + paste e envia `Return` após uma breve pausa; esta alteração aguarda validação manual.
- A versão anterior falhava ocasionalmente com a mensagem “A app não conseguiu confirmar que o texto chegou ao Terminal”; essa confirmação foi removida do caminho de envio.
- O routing entre várias tabs/janelas ainda precisa de uma matriz de validação manual dedicada.

## Limites observados

- A captura depende da estrutura visual atualmente exposta pela TUI do Codex.
- Não há garantia de leitura do estado interno do Codex para além do texto renderizado.
- A validação manual realizada cobre o Terminal.app; outros terminais continuam fora do escopo descrito em [`vision.md`](vision.md).

## Validação automática

```text
swift build --product PromptViz       PASS
swift run PromptVizContractRunner     PASS (18 checks)
```
