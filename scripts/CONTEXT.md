# Contexto de scripts

- `build-app.sh` cria e assina `dist/PromptViz.app`.
- `build-app.sh` copia `Assets/PromptVizLogo.svg` para os recursos do bundle.
- `run-prompt-viz.sh` fecha instâncias antigas, recompila e abre a app.

Scripts nesta pasta podem alterar processos locais ou gerar artefactos em `dist/`; não são parte do domínio da aplicação.
