# ERP Oficina — Instruções para Claude Code

## 1. Fonte da verdade

Antes de alterar código, leia obrigatoriamente:

- `docs/testing/BUSINESS_RULES.md`
- `docs/testing/TEST_MATRIX.md`

Esses arquivos fazem parte da especificação funcional do ERP.

Quando houver conflito entre o comportamento atual do código e uma regra marcada como **DEFINIDA**, a regra de negócio prevalece.

Regras marcadas como **PROVISÓRIA** devem ser tratadas como hipótese de homologação. Não altere o código de produção para impô-las sem registrar a divergência no relatório.

Regras marcadas como **PENDENTE** não devem ser inventadas. Registre o caso como bloqueado por decisão de negócio quando isso impedir um teste conclusivo.

---

## 2. Regra de conclusão

Uma funcionalidade só pode ser considerada concluída quando:

1. respeita a regra de negócio;
2. possui validação no backend;
3. preserva integridade do banco;
4. respeita autenticação e autorização;
5. possui teste automatizado quando tecnicamente viável;
6. passa na suíte de regressão;
7. não quebra casos anteriormente aprovados.

Interface sem proteção no backend não é suficiente.

---

## 3. Regra de bugs

Todo bug corrigido deve gerar um teste de regressão que:

1. falhe antes da correção;
2. passe depois da correção;
3. permaneça na suíte;
4. mantenha referência ao ID da matriz quando houver caso correspondente.

Exemplos de nomes:

- `test_ORC_011_rejeita_preco_negativo`
- `test_OS_004_impede_conversao_duplicada`
- `test_EST_009_impede_saldo_negativo`
- `test_LIB_003_bloqueia_liberacao_sem_pagamento_ou_termo`

---

## 4. Estratégia de testes

### Backend
Priorize testes automatizados para:

- regras de negócio;
- serviços;
- models;
- validações;
- endpoints;
- permissões;
- transações;
- estoque;
- cálculos;
- mudança de estados;
- auditoria;
- idempotência;
- concorrência.

Se o backend for Python e pytest já for compatível com a arquitetura, prefira `pytest`.

### Frontend / E2E
Use testes de navegador para:

- autenticação;
- cadastros;
- orçamento;
- aprovação;
- conversão em OS;
- execução;
- estoque;
- conclusão;
- cobrança;
- liberação;
- garantia;
- permissões percebidas pelo usuário.

Se Playwright for compatível com o frontend, prefira Playwright.

Não introduza outro framework se já existir uma solução equivalente e adequada.

---

## 5. Banco e dados de teste

Nunca execute testes destrutivos contra produção.

Antes de testar gravações:

1. identifique o banco configurado;
2. confirme ambiente de teste/homologação;
3. use banco exclusivo de teste;
4. isole os testes;
5. use fixtures/factories/seeds;
6. garanta repetibilidade;
7. não dependa da ordem dos testes.

Se não for possível confirmar que o banco não é de produção, interrompa os testes destrutivos e registre o bloqueio.

---

## 6. Primeira execução: auditoria, não correção

Na primeira passagem:

- não corrija o código de produção;
- implemente apenas infraestrutura de teste, mocks, fixtures, factories, seeds e testes;
- execute a matriz possível;
- deixe bugs reais falharem;
- registre divergências;
- gere `docs/testing/TEST_REPORT.md`.

Classifique cada caso como:

- `PASSOU`
- `FALHOU`
- `BLOQUEADO`
- `NÃO_IMPLEMENTADO`
- `NÃO_AUTOMATIZÁVEL`
- `PENDENTE_DECISÃO`

---

## 7. Relatório obrigatório

Ao final, gere `docs/testing/TEST_REPORT.md` contendo:

- resumo executivo;
- total de casos;
- casos automatizados;
- aprovados;
- reprovados;
- bloqueados;
- não implementados;
- percentual de cobertura;
- falhas críticas primeiro;
- evidência técnica;
- arquivos/endpoints envolvidos;
- risco operacional;
- sugestão de correção;
- tabela completa por ID;
- próximas ações priorizadas.

Prioridade de correção:

1. integridade de dados;
2. segurança/permissão;
3. risco financeiro;
4. regra de negócio;
5. operação;
6. usabilidade.

---

## 8. Não mascarar falhas

É proibido:

- mudar o resultado esperado apenas para fazer o teste passar;
- remover teste porque ele falhou;
- mockar a própria regra que está sendo testada;
- considerar teste não executado como aprovado;
- considerar botão escondido como autorização suficiente;
- apagar histórico para resolver inconsistência;
- alterar silenciosamente uma regra DEFINIDA.

A matriz representa o comportamento esperado do ERP.
