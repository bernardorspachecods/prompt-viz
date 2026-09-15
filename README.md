# Prompt Viz

Compositor local de prompts para sessões do Codex no Terminal.app do macOS.

## Objetivo

Reduzir a fricção entre escrever uma prompt, melhorá-la com snippets/templates e enviá-la para o tab correto do Terminal.app.

O projeto é pessoal, local e começa focado em macOS.

## Estado

O núcleo inicial de workspaces, snippets e expansão de templates está implementado, juntamente com a shell SwiftUI, botão flutuante e integração inicial com o Terminal.app. A validação manual de tabs e permissões de Acessibilidade ainda falta.

## Executar

```bash
swift run PromptViz
```

Para gerar uma app local:

```bash
./scripts/build-app.sh
```

Para fechar instâncias antigas, recompilar e abrir a app numa só operação:

```bash
./scripts/run-prompt-viz.sh
```

O fluxo atual lê a prompt em edição diretamente da TUI do Codex através da
Acessibilidade do Terminal.app. Não é necessário instalar um hook no `zsh`.

## Validação automática

```bash
swift run PromptVizContractRunner
```

O contract runner valida a lógica pura de templates, workspaces e snippets sem depender de uma janela gráfica ou de permissões de Acessibilidade.

## Documentação

- [Visão e plano atual](docs/vision.md)
- [Plano técnico inicial](docs/technical-plan.md)
- [Índice da documentação](docs/README.md)
