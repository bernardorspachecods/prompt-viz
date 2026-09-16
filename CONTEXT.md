# Contexto do repositório

Este ficheiro orienta a repo-mãe `prompt-viz`.

## Estrutura

- [`Package.swift`](Package.swift) — manifesto, produtos, targets e
  dependências Swift.
- [`Sources/CONTEXT.md`](Sources/CONTEXT.md) — fronteiras dos targets Swift e
  respetivos contextos locais.
- [`Assets/CONTEXT.md`](Assets/CONTEXT.md) — assets de identidade visual da app.
- [`docs/CONTEXT.md`](docs/CONTEXT.md) — mapa da documentação atual do produto e
  da implementação.
- [`PLAN.md`](PLAN.md) — registo da refatoração estrutural dos targets Swift,
  concluída em 2026-09-16.
- [`scripts/CONTEXT.md`](scripts/CONTEXT.md) — build e execução local.
- [`AGENTS.md`](AGENTS.md) — regra específica para fechar rondas que alterem a
  app.

Os testes de coordenação do modelo usam dependências falsas e executam com
[`scripts/run-prompt-viz-tests.sh`](scripts/run-prompt-viz-tests.sh). O
`PromptVizContractRunner` continua a validar o domínio puro.

`dist/`, `.build/` e `.swiftpm/` são outputs ou estado gerado; não são entradas
de desenvolvimento nem devem receber contexto durável.
