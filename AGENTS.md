# Regras específicas da repo

## Fecho de ronda de trabalho
Não executar a meio de alterações /rondas de trabalho, executa apenas no fim de parares de trabalhar:

```bash
./scripts/run-prompt-wiz.sh
```
Só entregar a ronda depois de confirmar que o script concluiu o build e abriu a app. Comunicar explicitamente se essa execução falhar. A execução falhar nao é razão para alterar trabalho de outros agentes