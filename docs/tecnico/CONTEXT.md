# Contexto técnico

Esta pasta descreve como a aplicação atual está organizada e quais são as suas
fronteiras técnicas.

- [`arquitetura_atual.md`](arquitetura_atual.md): módulos, integrações,
  invariantes e limites da implementação.

As regras de domínio puras estão nos ficheiros de `Sources/PromptVizCore/`,
separados por coesão; o `PromptVizContractRunner` executa os contratos
correspondentes.
