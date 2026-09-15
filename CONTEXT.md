# Contexto da repo

Prompt Viz é uma aplicação macOS nativa para compor prompts e entregá-las a sessões do Codex abertas no Terminal.app.

## Entradas

- `README.md`: instalação e utilização pública.
- `Sources/PromptViz`: shell SwiftUI, automação do Terminal.app e estado da aplicação.
- `Sources/PromptVizCore`: domínio puro, workspaces, snippets e parser do input Codex.
- `Sources/PromptVizContractRunner`: contratos executáveis sem UI.
- `scripts`: build e execução local.
- `docs`: visão, arquitetura e estado verificado.

## Fontes de verdade

| Pergunta | Documento |
|---|---|
| O que o produto pretende fazer? | [`docs/vision.md`](docs/vision.md) |
| Como está desenhado tecnicamente? | [`docs/architecture.md`](docs/architecture.md) |
| O que funciona comprovadamente hoje? | [`docs/current-state.md`](docs/current-state.md) |
| Que trabalho futuro foi decidido? | [`PLAN.md`](PLAN.md) |

Os contextos locais explicam apenas as fronteiras da respetiva pasta e apontam para estes documentos quando necessário.
