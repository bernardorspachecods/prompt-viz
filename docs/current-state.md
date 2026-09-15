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
- O fluxo observado não duplicou o texto já existente no terminal.
- Workspaces usam o TTY da sessão como identidade e não o título da janela.
- O código antigo de sincronização contínua via `zsh` foi removido.

## Parcial ou com falhas conhecidas

- A confirmação pós-paste falhou pelo menos uma vez com a mensagem “A app não conseguiu confirmar que o texto chegou ao Terminal”. Nesse caso não houve envio e o texto ficou preservado.
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
