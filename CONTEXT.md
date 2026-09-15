# Contexto do repositório

Este ficheiro orienta a repo-mãe `prompt-viz`.

## Estrutura

- [`Package.swift`](Package.swift) — manifesto, produtos, targets e
  dependências Swift.
- [`Sources/CONTEXT.md`](Sources/CONTEXT.md) — fronteiras dos targets Swift e
  respetivos contextos locais.
- [`docs/CONTEXT.md`](docs/CONTEXT.md) — mapa da documentação durável; os
  documentos específicos de produto e arquitetura são orientados a partir daí.
- [`scripts/CONTEXT.md`](scripts/CONTEXT.md) — build e execução local.
- [`PLAN.md`](PLAN.md) — trabalho futuro decidido para a repo.
- [`AGENTS.md`](AGENTS.md) — regra específica para fechar rondas que alterem a
  app.

`dist/`, `.build/` e `.swiftpm/` são outputs ou estado gerado; não são entradas
de desenvolvimento nem devem receber contexto durável.
