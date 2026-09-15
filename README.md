# Prompt Viz

Compositor local de prompts para sessões do Codex no Terminal.app do macOS.

Prompt Viz é uma ferramenta pessoal e local para compor prompts e entregá-las a sessões do Codex no Terminal.app.

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

## Validação automática

```bash
swift run PromptVizContractRunner
```

O contract runner valida a lógica pura de workspaces e snippets sem depender de uma janela gráfica ou de permissões de Acessibilidade.
