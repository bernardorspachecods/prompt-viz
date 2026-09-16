# Contexto de PromptViz

Este target contém a aplicação macOS SwiftUI e as integrações AppKit.

- `PromptVizApp.swift` contém apenas a entrada SwiftUI da aplicação.
- `PromptVizModel.swift` coordena o estado da app e expõe a fachada usada pelas
  views.
- `TerminalAutomation.swift` encapsula as integrações AppKit/Acessibilidade com
  o Terminal.app; os contratos substituíveis estão em
  `PromptVizDependencies.swift`.
- As views, o editor AppKit, a shell de janelas e os serviços de suporte vivem
  em ficheiros separados dentro deste target.

Consulte [`../../docs/tecnico/arquitetura_atual.md`](../../docs/tecnico/arquitetura_atual.md)
para as fronteiras técnicas e [`../../docs/produto/fluxos.md`](../../docs/produto/fluxos.md)
para os fluxos observáveis.
