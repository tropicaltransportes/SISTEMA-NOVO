# Testes de backend (pgTAP) — status: infraestrutura criada, NÃO executada

## Por que não foram executados

O CLAUDE.md deste projeto exige banco exclusivo de teste antes de qualquer
teste destrutivo, e bloqueia a execução se isso não puder ser confirmado.

Nesta auditoria (2026-08-10):

- Não há Docker disponível no ambiente de execução (`docker: command not
  found`), então `supabase start` (banco local, a via padrão de teste do
  próprio projeto — ver `docs/plano-arquitetura.md`, seção final: "testado
  localmente com Supabase local (Docker) antes de subir") não pôde ser usado.
- O único projeto Supabase configurado (`supabase/.temp/project-ref` →
  `jzjbiejmcaygwycvqggm`) é o projeto real de desenvolvimento — já contém
  dados de cliente reais (Tropical Transportes) misturados com dados de teste
  (ver memória do projeto). Não é um "banco exclusivo de teste".
- Não existe segundo projeto Supabase (staging/homologação) configurado em
  lugar nenhum do repositório.

Rodar estes testes pgTAP como estão hoje contra o projeto real criaria e
alteraria orçamentos, OS, estoque, cobranças etc. de verdade — exatamente o
que a Seção 5 do CLAUDE.md proíbe sem banco exclusivo de teste. Por isso a
auditoria ficou limitada a:

1. Leitura completa do código (migrations SQL + frontend) — resultado no
   `docs/testing/TEST_REPORT.md`.
2. Um subconjunto de checagens **comprovadamente não-destrutivas** rodado de
   verdade contra o projeto real, sem nenhuma credencial de usuário (papel
   `anon`, chamadas com UUID falso que nunca alcançam uma gravação real) — ver
   `docs/testing/scripts/safe_anon_rpc_checks.sh` e os resultados em
   `docs/testing/TEST_REPORT.md`.

## Como rodar esta suíte quando houver ambiente seguro

Assim que houver Docker disponível (ou um segundo projeto Supabase dedicado a
teste), rodar:

```bash
cd "SISTEMA NOVO"
supabase start          # sobe Postgres local com as migrations já aplicadas
supabase test db         # executa todos os arquivos .sql deste diretório via pgTAP
```

## O que está coberto aqui

- `010_seguranca_permissao_anon_bypass.sql` — regressão para o achado crítico
  desta auditoria: toda RPC que usa `if current_perfil() not in (...) then
  raise exception` deixa passar um chamador **sem sessão nenhuma** (papel
  `anon`), porque `current_perfil()` retorna `NULL` para esse chamador e
  `NULL NOT IN (...)` avalia como `NULL`, que o `IF` do plpgsql trata como
  falso — a exceção nunca dispara. Confirmado com evidência real (não
  destrutiva) contra o projeto real; ver `docs/testing/TEST_REPORT.md`,
  achado crítico #1. **Hoje, rodando esta suíte, todos os testes deste
  arquivo devem FALHAR** (é a prova automatizada do bug). Depois que o bug for
  corrigido, devem passar a PASSAR — esse é o critério de aceite da correção,
  por isso o teste fica na suíte permanente em vez de ser descartado (regra
  de bugs do CLAUDE.md, seção 3).
- `020_estoque.sql` — EST-002, EST-007, EST-008 (validações anti-negativação
  já implementadas em `rpc_registrar_saida_estoque`/`rpc_confirmar_nf_entrada`).
- `030_orcamento.sql` — ORC-009, ORC-010, ORC-011, ORC-012 (constraints de
  `orcamento_itens` já implementadas via CHECK).
- `040_liberacao.sql` — LIB-001..003 (condição financeira de `rpc_liberar_os`).

Casos que dependem de dois RPCs/sessões concorrentes (EST-013, EST-016,
NFR-001, NFR-002) não foram modelados em pgTAP puro — pgTAP roda em uma única
transação/sessão; concorrência real exige duas conexões simultâneas
(ex.: dois processos `psql` disparados em paralelo por um script externo).
Ficam como `NÃO_AUTOMATIZÁVEL` nesta suíte; ver observação no relatório.
