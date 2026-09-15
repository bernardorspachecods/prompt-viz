# Estado atual da aplicação

Este documento regista apenas comportamento observado ou validado por comandos reproduzíveis. O baseline é o commit `11fff39`.

## Estado geral

Captura e edição estão verificadas no baseline. O envio está parcial; o detalhe da falha está no bloco correspondente.

## Funcionalidades verificadas

- Build Swift do produto `PromptViz`.
- Contract runner do domínio.
- `⌘E` identifica a tab ativa do Terminal.app por TTY.
- A janela do Terminal expõe a TUI do Codex como `AXTextArea` com `AXValue`.
- O placeholder `Ask Codex to do anything` não é tratado como texto de prompt.
- Prompts multilineares são capturadas.
- Wraps visuais de linhas longas foram observados e reconstruídos.
- O texto capturado aparece rapidamente no editor da app.
- Depois de `⌘E`, o editor recebe o foco e o cursor é colocado no fim do draft; a app garante um espaço de continuação quando o AX não o devolve.
- O fluxo observado não duplicou o texto já existente no terminal.
- Workspaces usam o TTY da sessão como identidade e não o título da janela.
- A troca entre workspaces da app atualiza-se imediatamente e pede a seleção assíncrona da tab do Terminal; o envio serializa e valida essa seleção antes de publicar teclas, evitando bloquear a interface ao alternar tabs.
- Inventários incompletos, vazios ou com contagens diferentes entre tabs e TTYs não removem workspaces; uma sessão só é removida após duas ausências completas consecutivas. Esta proteção está coberta por contracts e aguarda validação manual com tabs Codex reais.
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
swift run PromptVizContractRunner     PASS (29 checks)
```
