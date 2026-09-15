# Contexto de PromptVizCore

Este target contém domínio sem dependências AppKit ou de permissões macOS.

- `WorkspaceStore` gere workspaces identificados por sessão.
- `SnippetLibrary` gere snippets e templates.
- `CodexTerminalInputParser` transforma o texto AX renderizado pela TUI num draft utilizável.

As regras devem ser observáveis pelo `PromptVizContractRunner` e não devem depender de ficheiros temporários, janelas ou processos reais.
