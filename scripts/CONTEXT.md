# Contexto de scripts

- `build-app.sh` cria e assina `dist/PromptWiz.app`.
- `build-app.sh` copia `Assets/PromptWizLogo.svg` para os recursos do bundle.
- `run-prompt-wiz.sh` fecha instâncias antigas, recompila e abre a app.
- `run-prompt-wiz-tests.sh` compila e executa os testes de coordenação com
  dependências falsas, sem abrir a app nem depender do Terminal.app.

Scripts nesta pasta podem alterar processos locais ou gerar artefactos em `dist/`; não são parte do domínio da aplicação.
