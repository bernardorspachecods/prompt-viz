# Contexto de PromptVizCore

Este target contém domínio sem dependências AppKit ou de permissões macOS.

- `CodexTerminalInputParser.swift` transforma o texto AX renderizado pela TUI
  num draft utilizável.
- `SkillManifestParser.swift` interpreta os metadados das skills.
- `PromptEditorTokens.swift` gere tokens e referências do editor.
- `DomainModels.swift` contém os modelos partilhados.
- `WorkspaceStore.swift`, `SnippetLibrary.swift` e `PromptHistoryStore.swift`
  gerem o estado puro correspondente.

As regras devem ser observáveis pelo `PromptVizContractRunner` e não devem depender de ficheiros temporários, janelas ou processos reais.
