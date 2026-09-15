# Requisitos atuais

## Responsabilidade

Este documento descreve as capacidades e os limites que a aplicação suporta
atualmente. A implementação técnica está em
[`../tecnico/arquitetura_atual.md`](../tecnico/arquitetura_atual.md).

## Aplicação

Prompt Viz é uma aplicação nativa para macOS que abre um compositor de texto e
o liga à sessão ativa do Codex no Terminal.app.

## Sessões e rascunhos

- Cada sessão do Terminal.app aberta no compositor tem um workspace próprio.
- A sessão é identificada pelo TTY; o título serve para apresentação.
- Cada workspace mantém o seu rascunho enquanto existir na aplicação.
- A app pode alternar entre workspaces e selecionar a sessão correspondente no
  Terminal.app.
- O workspace é removido quando a sessão do Terminal desaparece de forma
  confirmada ou quando a janela correspondente da app é fechada.

## Prompts

- A app lê o texto renderizado do compositor do Codex através da Acessibilidade.
- O rascunho capturado pode conter várias linhas e wraps visuais.
- O texto do prompt é editável no compositor da app.
- O envio substitui o campo do Codex, cola o texto e submete-o com `Return`.
- Depois de um envio bem-sucedido, o editor fica vazio.

## Snippets e templates

- A biblioteca de snippets é local à app.
- Um snippet tem título, conteúdo e estado de favorito.
- Snippets podem ser pesquisados, inseridos, criados, editados e apagados.
- Conteúdos com campos `{{nome}}` são apresentados num formulário antes da
  inserção.
- Snippets favoritos têm uma área própria e atalhos de teclado.

## Skills

- A app encontra `SKILL.md` nas pastas locais configuradas para skills.
- Ao escrever uma referência iniciada por `$`, o editor apresenta skills
  pesquisáveis.
- Escolher uma skill insere o seu nome no prompt.

## Dados e limites

- Snippets são guardados localmente em `UserDefaults`.
- Workspaces e rascunhos existem apenas em memória durante a execução da app.
- A app não mantém histórico de prompts enviados.
- A integração atual é exclusivamente com o Terminal.app.
- A app trabalha com o texto renderizado da TUI; não lê o estado interno, o
  histórico ou a disponibilidade semântica do Codex.
