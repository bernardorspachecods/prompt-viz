# Plano de refatoração da estrutura Swift

Estado: concluído em 2026-09-16.

## Objetivo

Reduzir a concentração de responsabilidades nos ficheiros Swift, tornar as
fronteiras técnicas navegáveis e permitir testar a coordenação da aplicação com
dependências falsas, preservando o comportamento observável atual.

A arquitetura atualmente implementada está descrita em
[`docs/tecnico/arquitetura_atual.md`](docs/tecnico/arquitetura_atual.md). Este
documento descreve apenas a mudança proposta.

## Diagnóstico

- `Sources/PromptWiz/PromptWizApp.swift` concentra cerca de 2.587 linhas e
  reúne automação do Terminal, estado da app, lifecycle, persistência, atalhos,
  clipboard e várias views.
- `Sources/PromptWizCore/Domain.swift` concentra cerca de 615 linhas com
  parser, tokens, modelos e três stores de domínio.
- A UI acede diretamente a `snippetLibrary`, `promptHistory`, `skillCatalog` e
  à automação através do `PromptWizModel`, apesar de a arquitetura pretender
  que as views recebam estado e enviem comandos através de uma fronteira
  pequena.
- `PromptWizModel` é singleton e instancia dependências concretas, o que torna
  os fluxos de coordenação difíceis de testar sem Terminal.app, clipboard ou
  persistência real.

O problema é concentração e acoplamento, não a contagem absoluta de linhas de
uma app macOS pequena.

## Scope

### 1. Separar a aplicação macOS por responsabilidade

Extrair de `PromptWizApp.swift`, mantendo os nomes e contratos públicos sempre
que possível:

- entrada da app e configuração da cena;
- `AppDelegate` e `MainWindowController`;
- `PromptWizModel`;
- automação do Terminal e erros associados;
- logging, atalhos, clipboard e persistência local;
- `ContentView`, `AppSettingsView` e `SnippetEditorSheet`;
- `PromptEditorArea`, `PromptTextEditor` e o coordinator AppKit.

Os ficheiros podem ficar no mesmo target sem criar novos packages. A divisão
deve seguir motivos de mudança; não é objetivo criar um ficheiro para cada
struct pequena.

### 2. Separar o domínio puro por coesão

Dividir `Domain.swift` em grupos independentes, por exemplo:

- parser de input do Terminal;
- tokens e referências do editor;
- modelos partilhados;
- `WorkspaceStore`;
- `SnippetLibrary`;
- `PromptHistoryStore`.

O domínio continua sem AppKit, permissões, janelas, processos reais ou
ficheiros temporários.

### 3. Fechar a fronteira da UI

- Views usam as projeções publicadas pelo modelo e métodos de intenção, em vez
  de lerem stores internos diretamente.
- Operações como pesquisa de histórico, favoritos, movimento de snippets e
  abertura das definições de permissões passam pelo modelo ou por uma fachada
  específica.
- `TerminalAutomation`, persistências e catálogo de skills deixam de ser
  dependências que as views conhecem diretamente.

### 4. Introduzir dependências substituíveis

Criar interfaces mínimas para os efeitos externos usados pelo modelo:

- automação do Terminal;
- persistência de snippets;
- persistência do histórico;
- descoberta de skills, quando necessário para testar a coordenação.

As implementações atuais continuam a ser as implementações por defeito do
arranque normal. O singleton pode continuar a existir como composição da app,
mas o modelo deve ter uma inicialização utilizável por testes com fakes.

Não abstrair APIs SwiftUI ou AppKit sem uma necessidade concreta de teste.

### 5. Verificar e manter o contexto

- Preservar os fluxos observáveis: captura, troca e remoção de workspaces,
  envio, snippets, histórico, imagens, atalhos e definições.
- Acrescentar verificações para os seams novos e manter o
  `PromptWizContractRunner` como verificação do domínio puro.
- Atualizar os `CONTEXT.md` apenas onde os caminhos ou fronteiras documentadas
  deixarem de corresponder ao código.
- Não alterar requisitos, nomenclatura de produto ou comportamento funcional.

## Sequência de execução

1. Registar o estado inicial e executar as verificações existentes.
2. Extrair ficheiros por responsabilidade sem mudar comportamento.
3. Introduzir as fachadas e dependências substituíveis no modelo.
4. Alterar as views para usarem apenas essas fachadas.
5. Dividir o domínio puro e ajustar imports/referências.
6. Adicionar ou ajustar testes dos seams e dos contratos.
7. Rever o diff, atualizar contexto necessário, reconstruir e abrir a app para
   teste manual.

## Critérios de conclusão

- Nenhum ficheiro combina lifecycle, UI, domínio e integração de sistema.
- As views não acedem diretamente aos stores ou adaptadores internos.
- `PromptWizModel` pode ser instanciado com fakes para testar coordenação sem
  Terminal.app real.
- O `PromptWizContractRunner` passa.
- O build conclui sem warnings novos relevantes.
- `./scripts/run-prompt-wiz.sh` conclui o build e abre a versão atualizada.
- O teste manual cobre captura, troca de workspaces, envio, snippets,
  histórico, imagem e definições.

## Fora de scope

- Alterar funcionalidades ou fluxos de produto.
- Redesenhar a UI.
- Criar novos packages Swift.
- Reescrever a automação do Terminal.
- Refatorar ficheiros não relacionados.

## Riscos e decisões

- A separação pode expor dependências implícitas que hoje ficam escondidas no
  ficheiro monolítico; cada extração deve compilar antes da seguinte.
- Protocolos demasiado amplos recriariam o mesmo acoplamento com outro nome;
  as interfaces devem conter apenas operações necessárias ao consumidor.
- A automação do Terminal e o editor AppKit mantêm complexidade própria mesmo
  depois da divisão. O objetivo é isolar essa complexidade, não eliminá-la.

## Resultado

- `PromptWizApp.swift` ficou reservado à entrada da app; lifecycle, modelo,
  automação, suporte e views foram separados por responsabilidade.
- `Domain.swift` foi substituído por ficheiros de parser, tokens, modelos e
  stores coesos.
- As views usam as projeções e intenções do `PromptWizModel`; os stores e
  adaptadores externos ficaram privados do modelo.
- O modelo aceita implementações substituíveis de automação, persistência,
  catálogo de skills, clipboard, login e atalhos.
- O `PromptWizContractRunner` passou os 45 contratos.
- `swift build` passou sem warnings novos relevantes.
- `./scripts/run-prompt-wiz.sh` concluiu o build de produção e abriu a app.
