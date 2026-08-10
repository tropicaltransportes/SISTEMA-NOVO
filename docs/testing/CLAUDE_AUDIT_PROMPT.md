# Prompt de Auditoria Inicial — Claude Code

Leia primeiro:

- `CLAUDE.md`
- `docs/testing/BUSINESS_RULES.md`
- `docs/testing/TEST_MATRIX.md`

## Objetivo

Faça a primeira auditoria de qualidade do ERP **sem corrigir o código de produção**.

### 1. Audite o repositório

Identifique:

- arquitetura;
- backend;
- frontend;
- banco;
- autenticação;
- autorização;
- models/entidades;
- endpoints;
- fluxos;
- migrations;
- seeds;
- infraestrutura de testes;
- comandos para executar backend/frontend;
- dependências de teste existentes.

### 2. Cruze o código com a matriz

Para cada ID de `TEST_MATRIX.md`, classifique:

- IMPLEMENTADO_E_TESTÁVEL
- IMPLEMENTADO_PARCIALMENTE
- NÃO_IMPLEMENTADO
- DIVERGE_DA_REGRA
- BLOQUEADO
- TESTE_JÁ_EXISTENTE
- PENDENTE_DECISÃO

Não altere o resultado esperado para fazer o código atual parecer correto.

### 3. Prepare ambiente de teste seguro

Antes de qualquer escrita:

- confirme que não é produção;
- use banco exclusivo de teste;
- crie fixtures/factories/seeds;
- garanta isolamento;
- garanta repetibilidade.

Se não conseguir confirmar isso, não execute testes destrutivos.

### 4. Implemente os testes possíveis

Pode criar/modificar:

- arquivos de teste;
- fixtures;
- factories;
- mocks;
- seeds;
- config exclusiva de testes;
- infraestrutura de Playwright/pytest se compatível.

Não corrija bugs de produção nesta primeira execução.

Use os IDs da matriz nos nomes dos testes sempre que possível.

### 5. Prioridade de automação

1. casos Críticos;
2. casos Altos;
3. regras de backend;
4. permissões;
5. estoque/transações;
6. cálculos;
7. E2E dos fluxos principais;
8. demais casos.

### 6. Execute a suíte

Registre:

- testes executados;
- testes que passaram;
- testes que falharam;
- bloqueios;
- casos não implementados;
- casos pendentes de decisão.

### 7. Gere o relatório

Preencha/crie:

`docs/testing/TEST_REPORT.md`

Use como base:

`docs/testing/TEST_REPORT_TEMPLATE.md`

Ao final, mostre no terminal:

- total de casos;
- automatizados;
- PASSOU;
- FALHOU;
- BLOQUEADO;
- NÃO_IMPLEMENTADO;
- PENDENTE_DECISÃO;
- lista dos IDs críticos que falharam.

## Regra fundamental

Nesta primeira auditoria, bugs reais devem continuar falhando.

Não faça correções silenciosas no código de produção.
