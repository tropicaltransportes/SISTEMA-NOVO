# TEST REPORT — EXECUÇÃO 02 — ERP Oficina

> Segunda rodada de auditoria. `docs/testing/TEST_REPORT.md` (a primeira
> auditoria, só leitura de código + checagens anônimas não-destrutivas) fica
> preservado como baseline. Esta rodada teve autorização explícita do usuário
> para tratar o projeto Supabase `jzjbiejmcaygwycvqggm` como ambiente de
> desenvolvimento/teste descartável — criar, alterar e excluir dados de
> teste, criar usuários de teste, aplicar migrations corretivas e executar
> fluxos ponta a ponta de verdade.

## 1. Resumo executivo

| Métrica | Valor |
|---|---|
| Total de casos da matriz | 176 |
| **EXECUTADOS DE VERDADE** (chamada real HTTP/RPC/pgTAP contra o banco, com resposta observada) | **75** |
| Avaliados só por revisão de código (sem execução) | 41 (15 FALHOU + 26 NÃO_IMPLEMENTADO) |
| PASSOU | 73 |
| FALHOU | 17 |
| BLOQUEADO | 49 |
| NÃO_IMPLEMENTADO | 26 |
| NÃO_AUTOMATIZÁVEL | 2 |
| PENDENTE_DECISÃO | 9 |
| Cobertura da matriz (casos com veredito) | 176/176 = 100% |
| **Cobertura de execução real** | **75/176 ≈ 43%** (era 6/176 ≈ 3% na 1ª auditoria) |

**P0 corrigidos:** 6/6
**P0 validados por execução real:** 6/6
**P0 ainda falhando:** 0/6

Nenhum resultado esperado foi alterado para fazer teste passar. Nenhum teste que falhou foi apagado. Nenhuma correção de P1/P2 foi feita nesta rodada (só os 6 P0 autorizados explicitamente). Onde a matriz continua `BLOQUEADO`, é porque genuinamente não executei aquele caso nesta rodada — não porque presumi sucesso.

---

## 2. P0 — status final

Todos os 6 achados P0 do relatório anterior foram corrigidos numa única
migration nova (nenhuma migration antiga foi alterada) e **validados por
execução real** contra o banco de desenvolvimento, não só por leitura de
código.

| ID | Achado | Migration da correção | Evidência de execução real |
|---|---|---|---|
| P0-01 | AUT-005 — bypass de permissão por chamador sem sessão (`current_perfil()` retorna NULL, `NOT IN` falha aberto) | `supabase/migrations/20260810160000_p0_correcoes_criticas.sql` (função `tem_perfil()` + redeclaração de 22 RPCs) | `docs/testing/_p0_validation_output.txt` — as mesmas 21 chamadas anônimas que antes vazavam lógica de negócio agora retornam "Perfil sem permissão..." em 100% dos casos; `supabase/tests/010_seguranca_permissao_anon_bypass.sql` — 6/6 pgTAP `ok`; `docs/testing/_etapa4_output.txt` — usuário autenticado **sem profile** (`teste.semperfil@qa.local`) também bloqueado corretamente (regressão do mesmo bug family) |
| P0-02 | DOC-006 — bucket `comprovantes` legível por qualquer autenticado, inclusive executor | mesma migration (policy `comprovantes_select_gestao`) | `docs/testing/_etapa8_storage_output.txt` — EXECUTOR agora recebe HTTP 400 ao tentar ler um comprovante real recém-enviado; SUPORTE/ENCARREGADO/DIRETORIA continuam lendo (HTTP 200); ANON continua bloqueado |
| P0-03 | OS-004 — mesmo orçamento gerava múltiplas OS | mesma migration (`rpc_criar_os` ganhou checagem de OS ativa existente) | `docs/testing/_etapa7_output.txt`, passo "1b" — reconverter o orçamento recém-aprovado do fluxo E2E-001 retorna "Este orçamento já foi convertido em uma OS ativa" |
| P0-04 | EST-009 — baixa de estoque sem idempotência | mesma migration (`rpc_baixar_peca_os` ganhou janela de dedup de 5s) | `supabase/tests/020_estoque.sql` (pgTAP, ok 6/6) e `docs/testing/_etapa6_output.txt`, seção 3 — repetir a mesma baixa (OS/peça/quantidade) é bloqueada, saldo não duplica |
| P0-05 | OS-010 — cancelar OS não tratava estoque já baixado; EST-010 — não existia estorno de saída | mesma migration (`estornar_saida_estoque_interno`, `rpc_estornar_saida_estoque`, auto-estorno em `rpc_transicionar_os` no cancelamento) | `docs/testing/_etapa6_output.txt`, seções 4 e 5 — estorno manual funciona e bloqueia duplo-estorno; cancelar a OS f...0008 (com 2un já baixadas) restaura o saldo automaticamente e grava `estorno_saida` com `estornado_de` apontando pro movimento original |
| P0-06 | LIB-006 — `suporte_administrativo` não conseguia liberar OS | mesma migration (`rpc_liberar_os` passou a aceitar `suporte_administrativo`) | `docs/testing/_etapa4_output.txt` — SUPORTE agora passa do check de perfil (recebe erro de condição financeira, não mais de permissão); `supabase/tests/040_liberacao.sql` (pgTAP, ok 3/3, executado como `administrador_tecnico`, mas a mudança na lista de perfis foi confirmada via HTTP com o usuário `suporte_administrativo` de verdade) |

---

## 3. Metodologia desta rodada

### 3.1 Ambiente confirmado (ETAPA 1)

- Projeto Supabase vinculado: `jzjbiejmcaygwycvqggm` ("SISTEMA NOVO"), único
  projeto do CLI (`npx supabase projects list`), status `ACTIVE_HEALTHY`.
- `npx supabase migration list` mostrou as 14 migrations da 1ª auditoria já
  aplicadas (local=remote em todas) — confirma que nada foi alterado fora de
  banda desde então.
- Docker **continua indisponível** (`docker: command not found`) — mesma
  limitação da 1ª auditoria para `supabase start`/`supabase test db` local.
  **Mas** descobri nesta rodada que o CLI já tinha um access token válido
  cacheado (`npx supabase projects list`/`migration list` funcionaram sem
  pedir login), e que `supabase db push` e `supabase db query --linked`
  conectam direto no Postgres remoto via API de Management — isso abriu o
  caminho pra aplicar migrations corretivas e rodar pgTAP contra o banco real
  sem precisar de Docker nem pedir comandos pro usuário rodar manualmente.
- `select count(*) from ...` antes de qualquer alteração: 4 clientes,
  4 veículos, 7 OS, 5 orçamentos, 5 cobranças, 1 profile (só o admin real,
  `hammedgurgel@tropicaltransportes.com.br` — confirma que nenhum usuário de
  teste existia antes desta rodada).
- Extensão `pgtap` não estava instalada — habilitada via
  `supabase/migrations/20260810160100_habilitar_pgtap.sql`.

### 3.2 Massa de teste (ETAPA 2)

`supabase/seed.sql` — só dados, reexecutável (apaga por `id like 'X0000000-%'`
antes de recriar). Cobre exatamente os grupos pedidos: 7 usuários (um por
perfil do enum `perfil_usuario`, mais um inativo e um "autenticado sem
profile"), 6 clientes (externo normal, interno, inadimplente, garantia, e um
par duplicado de propósito pra CAD-004), 4 veículos, 5 peças (saldo ok,
baixo, zero, concorrência, e uma dedicada a testes exatos de saldo=10), 1
checklist, 8 orçamentos (rascunho/enviado/aprovado ×4/rejeitado), 9 OS
(aberta/em_execução/concluível/concluída ×2/liberada dentro e fora do prazo
de garantia/com estoque já baixado/pronta pra múltiplos executores), 3
cobranças (aberta/quitada/parcial). Senha de teste única, documentada no
próprio arquivo: `Teste@2026!Qa`.

### 3.3 Ferramentas usadas para executar de verdade

- `npx supabase db push` — aplicar a migration corretiva P0.
- `npx supabase db query --linked -f <arquivo.sql>` — rodar `seed.sql` e a
  suíte pgTAP (`supabase/tests/*.sql`) contra o banco remoto. Descoberta
  importante: essa via só retorna o resultado do **último** SELECT do lote
  (protocolo simples), então toda suíte pgTAP foi reescrita pra ter um único
  `SELECT ... UNION ALL ...` como última instrução (em vez de vários
  `select ok(...)` separados) — documentado no topo de cada arquivo.
- `curl` contra `/auth/v1/token?grant_type=password` (GoTrue) — login real de
  cada persona semeada, e contra `/rest/v1/rpc/...`, `/rest/v1/<tabela>` e
  `/storage/v1/object/...` — chamadas autenticadas de verdade.
- Scripts salvos e reproduzíveis: `docs/testing/scripts/etapa4_rbac_real.sh`,
  `etapa6_estoque_real.sh`, `etapa7_e2e_real.sh`, mais o
  `safe_anon_rpc_checks.sh` já existente (reexecutado pra validar o P0-01).

---

## 4. Log de execução real (por etapa)

### ETAPA 4 — Autenticação e autorização por perfil

Arquivo bruto: `docs/testing/_etapa4_output.txt`.

| ID | Perfil usado | Dados de entrada | Operação | Resposta | Estado final | Resultado |
|---|---|---|---|---|---|---|
| AUT-001 | 7 personas semeadas | e-mail+senha `Teste@2026!Qa` de cada uma | `POST /auth/v1/token?grant_type=password` | 7/7 `access_token` retornado | 7 sessões válidas criadas | **PASSOU** |
| AUT-004 | `teste.inativo` (`ativo=false`) | login normal | login + depois `rpc_baixar_peca_os` na OS f...0002 | login OK; RPC executou com sucesso (HTTP 204) | peça d...0001 baixada mesmo com usuário inativo | **FALHOU** (confirmado por execução — `profiles.ativo` continua sem nenhum efeito) |
| AUT-005 | anônimo (sem header Authorization) | `rpc_aprovar_orcamento` no orçamento real e...0002 | chamada direta | "Perfil sem permissão para aprovar orçamento" | nenhuma mudança | **PASSOU** (era FALHOU, corrigido) |
| — (regressão do mesmo bug) | `teste.semperfil` (sessão válida, sem linha em `profiles`) | idem acima | idem | mesma mensagem de permissão | nenhuma mudança | confirma que o fix cobre também sessão válida sem perfil, não só anon |
| APR-007 / EXE-009 | `teste.executor` | aprovar e...0002 | `rpc_aprovar_orcamento` | "Perfil sem permissão para aprovar orçamento" | nenhuma mudança | **PASSOU** |
| APR-001 | `teste.suporte` (autoriza) + `teste.encarregado` (aprova) | e...0002 | `rpc_registrar_autorizacao_orcamento` depois `rpc_aprovar_orcamento` | HTTP 204 nas duas | e...0002 passou de `enviado` para `aprovado` de verdade | **PASSOU** |
| APR-012 | `teste.encarregado` | aprovar e...0002 de novo | `rpc_aprovar_orcamento` | "Somente orçamentos enviados podem ser aprovados" | sem efeito duplicado | **PASSOU** |
| PER-001 (espírito de OS/EXE-008) | executor, suporte, diretoria | criar OS interna | `rpc_criar_os` | "Perfil sem permissão para criar ordem de serviço" nos 3 | nenhuma OS criada | **PASSOU** |
| OS-001 | `teste.admin` | criar OS interna real (veículo c...0002) | `rpc_criar_os` | HTTP 200, id retornado | OS nova criada | **PASSOU** |
| LIB-004 | executor | liberar OS f...0004 | `rpc_liberar_os` | "Perfil sem permissão para liberar OS" | sem efeito | **PASSOU** |
| PER-004 | diretoria | liberar OS f...0004 | `rpc_liberar_os` | mesma negação | sem efeito | **PASSOU** |
| LIB-006 | `teste.suporte` | liberar OS f...0004 | `rpc_liberar_os` | passa do check de perfil, cai em "Condição financeira pendente" (cobrança seed 10000000-...-0001 ainda `aberta`) | sem efeito | **PASSOU** (era FALHOU, corrigido) |
| LIB-005 | encarregado | idem | idem | mesmo resultado de negócio (não de permissão) | sem efeito | **PASSOU** |
| LIB-003 / E2E-005 | admin | liberar OS f...0005 (cliente inadimplente, sem cobrança/termo) | `rpc_liberar_os` | "OS externa exige cobrança gerada antes da liberação" | sem efeito | **PASSOU** |
| financeiro (apoio a PER-003/RBAC) | encarregado | gerar cobrança | `rpc_criar_cobranca` | "Perfil sem permissão para gerar cobrança" | sem efeito | evidência de apoio (encarregado corretamente fora da lista suporte/admin) |
| financeiro RLS (apoio) | executor vs diretoria | `SELECT cobrancas` | REST direto | executor: `[]`; diretoria: 5 linhas reais | — | evidência de apoio (RLS `<> 'executor'` funcionando) |
| ação permitida (apoio) | executor | baixar 1un de d...0001 na OS f...0002 | `rpc_baixar_peca_os` | HTTP 204 | saldo reduzido | evidência de apoio (executor consegue o que É permitido) |

### ETAPA 5 — pgTAP contra o banco real

4 arquivos, todos com `BEGIN`/`ROLLBACK` (sem resíduo), rodados via
`supabase db query --linked -f`. 19/19 asserções passaram.

| Arquivo | Casos cobertos | Resultado |
|---|---|---|
| `supabase/tests/010_seguranca_permissao_anon_bypass.sql` | AUT-005 (regressão P0-01) em 6 RPCs distintas | 6/6 ok |
| `supabase/tests/020_estoque.sql` | EST-002, EST-007, EST-008, EST-009 | 6/6 ok |
| `supabase/tests/030_orcamento.sql` | ORC-009, ORC-010, ORC-011, ORC-012 | 4/4 ok |
| `supabase/tests/040_liberacao.sql` | LIB-001, LIB-002, LIB-003 | 3/3 ok |

Também demonstra, por execução repetida com resultado equivalente e sem
resíduo: **NFR-006** (repetibilidade), **NFR-007** (isolamento — `ROLLBACK`
confirmado, nenhum dado de teste do pgTAP ficou no banco), e **NFR-008**
(seed determinístico — `seed.sql` rodou de ponta a ponta sem erro).

### ETAPA 6 — Estoque

Arquivo bruto: `docs/testing/_etapa6_output.txt`.

| Passo | Dados de entrada | Operação | Resposta | Estado final | ID(s) |
|---|---|---|---|---|---|
| 1 | peça d...0005, saldo=10, OS f...0009, qtd=2 | `rpc_baixar_peca_os` (executor) | HTTP 204 | saldo=8; movimento `saida` com `origem_tipo=os`, `origem_id`, `criado_por`, `criado_em` presentes | EST-005 |
| 2 | mesma peça (saldo=8), qtd=20 | `rpc_baixar_peca_os` | "Estoque insuficiente para a peça ... (saldo 8.000, solicitado 20)" | saldo continua 8 | **EST-007 PASSOU** |
| 3 | repetir passo 1 (mesma OS/peça/qtd=2), na sequência | `rpc_baixar_peca_os` | "Baixa idêntica já registrada nos últimos segundos..." | saldo continua 8 | **EST-009 PASSOU** (fix P0-04) |
| 4 | movimento do passo 1 | `rpc_estornar_saida_estoque` (suporte) | HTTP 204 | saldo volta a 10; novo registro `estorno_saida` com `estornado_de` apontando pro original; 2ª tentativa de estornar o mesmo bloqueada ("já foi estornado anteriormente") | **EST-010 / AUD-004 PASSOU** (fix P0-05) |
| 5 | OS f...0008 (2un de d...0004 já baixadas no seed, saldo=8) | `rpc_transicionar_os` → `cancelada` (admin) | HTTP 204 | saldo de d...0004 volta a 10 sozinho; `estorno_saida` automático gravado | **OS-010 / E2E-008 PASSOU** (fix P0-05) |
| 6 | cliente b...0001, peça d...0001, 3un | `rpc_criar_venda_avulsa` (suporte) | HTTP 200, id retornado | venda registrada, estoque baixado | **EST-006 PASSOU** |
| 7 | peça d...0005 (saldo=10), duas chamadas quase simultâneas: 5un (executor) e 6un (suporte) | `rpc_baixar_peca_os` × 2, em paralelo (bash `&`+`wait`) | uma delas (qtd=6) HTTP 204; a outra (qtd=5) "Estoque insuficiente (saldo 4.000, solicitado 5)" | saldo final = 4 (nunca negativo, só uma passou) | **EST-013 / EST-016 PASSOU** |

### ETAPA 7 — E2E-001 (fluxo completo) e E2E-007 (múltiplos executores)

Arquivo bruto: `docs/testing/_etapa7_output.txt`. Fluxo montado **do zero**
(não a partir de um orçamento pré-aprovado do seed, porque todos os do seed
já estavam vinculados a uma OS — o que por si só já reconfirmou o fix
OS-004/P0-03 no passo "1b").

Sequência completa executada com sucesso, sem nenhum passo falho:
cliente/veículo (reaproveitados do seed, já existentes) → `orcamentos`
insert (rascunho) → `orcamento_itens` insert (2un × R$100 = R$200) →
`rpc_enviar_orcamento` → `rpc_registrar_autorizacao_orcamento` →
`rpc_aprovar_orcamento` → `rpc_criar_os` (**OS-001, OS-005, OS-006** —
valores herdados batem exatamente: cobrança gerada depois foi de R$200,00,
igual ao orçamento) → tentativa de reconverter bloqueada (**OS-004**) →
`rpc_definir_checklist_os` → `rpc_transicionar_os` ×2 (em_diagnostico,
em_execucao) → `os_executores` insert (**EXE-001**) → `rpc_baixar_peca_os`
→ `rpc_transicionar_os` (aguardando_teste) → `os_checklist_respostas` insert
(ok=true) → `rpc_concluir_os` (**CON-001, CON-003**) → `rpc_criar_cobranca`
(**FIN-001** — valor batendo) → `rpc_parcelar_cobranca` (**FIN-004**) →
`rpc_registrar_recebimento` (**FIN-006**) → `rpc_liberar_os` (**LIB-001**,
condição financeira satisfeita) → estado final confirmado via `SELECT`:
`status=liberada`, `data_liberacao` preenchida → `rpc_criar_os_garantia`
(**GAR-001, GAR-002**, dentro do prazo de 90 dias).

Em seguida, um segundo apontamento de um usuário diferente foi inserido na
mesma OS (**EXE-002, E2E-007**) — `SELECT os_executores` confirmou as 2
linhas, uma por usuário, ambas preservadas.

Isso também é a evidência real de **E2E-001** (fluxo completo),
**E2E-009** (nenhuma duplicação em nenhum passo, incluindo a tentativa
bloqueada de reconverter o orçamento) e **E2E-010** (todas as barreiras de
permissão testadas na ETAPA 4 se sustentam dentro de um fluxo real, não só
isoladas).

### ETAPA 8 — Storage (`comprovantes`, pós-fix DOC-006)

Arquivo bruto: `docs/testing/_etapa8_storage_output.txt`. Upload real feito
por `teste.suporte` (`pgtap-teste-doc006.txt`), depois lido por 5 personas:

| Persona | Ação | Resposta |
|---|---|---|
| suporte (dono do upload) | GET | HTTP 200 |
| encarregado | GET | HTTP 200 |
| diretoria | GET | HTTP 200 |
| **executor** | GET | **HTTP 400 (bloqueado)** |
| anônimo (sem sessão) | GET | HTTP 400 (bloqueado — já era assim antes) |
| executor | tentativa de upload | HTTP 400 (bloqueado — sem mudança, nunca teve permissão) |

**DOC-006 = PASSOU** (era FALHOU, corrigido).

### Lote extra — GAR-003/004, PER-002, tentativas de exclusão física

Arquivo bruto: `docs/testing/_etapa_extra_output.txt`.

- **GAR-003**: abrir garantia numa OS liberada há 100 dias (f...0007) →
  "Prazo de garantia (90 dias da liberação) expirado". **PASSOU**.
- **GAR-004**: consulta real mostrou 3 OS de garantia (das criadas nesta
  rodada) todas com `os_origem_id` preenchido apontando pra OS original.
  **PASSOU**.
- **PER-002**: executor tenta cancelar OS f...0001 → "Perfil sem permissão
  para transicionar OS". **PASSOU**.
- **EST-011**: tentativa de `DELETE` em `estoque_movimentos` → HTTP 403,
  `permission denied for table estoque_movimentos` (REVOKE explícito).
  **PASSOU**.
- **CAD-010 / OS-012**: tentativa de `DELETE` em `clientes`/`ordens_servico`
  → HTTP 204, **mas confirmado por `SELECT` logo depois que 0 linhas foram
  afetadas** (RLS sem nenhuma policy de DELETE nega implicitamente, sem
  gerar erro — mecanismo diferente do REVOKE explícito de EST-011, mas
  igualmente seguro). Ambos registros continuam existindo. **PASSOU**
  (atenção documentada: HTTP 204 num DELETE via PostgREST não prova exclusão
  — sempre confirmar via SELECT depois, como fiz aqui).

---

## 5. Achados residuais e novos desta rodada

Nenhum achado novo de segurança crítica — a rodada foi majoritariamente
confirmatória. Duas observações novas:

1. **E2E-002 reclassificado de BLOQUEADO para NÃO_IMPLEMENTADO**: o cenário
   ("aprovar parte, converter, criar adicional e rejeitá-lo") depende de
   dois recursos que não existem (aprovação parcial e módulo de adicionais)
   — não é que falte executar, é que não há o que executar.
2. **E2E-003 reclassificado de BLOQUEADO para FALHOU**: o cenário espera que
   a conversão para OS bloqueie/encaminhe quando não há saldo suficiente —
   mas a conversão (`rpc_criar_os`) nunca toca em estoque (confirmado tanto
   por leitura do código quanto pela execução real do E2E-001, onde a
   conversão não gerou nenhuma linha em `estoque_movimentos`; a baixa só
   acontece depois, manualmente, via `rpc_baixar_peca_os` — que aí sim
   bloqueia corretamente, confirmado no EST-007 real). Mesma causa raiz do
   achado EST-004 já registrado na 1ª auditoria.

Os achados críticos residuais (não corrigidos nesta rodada, por serem P1/P2
fora do escopo autorizado) continuam os mesmos do relatório anterior:
módulo de Adicionais ausente, aprovação parcial ausente, mecanismo de
desconto ausente, sem trilha de auditoria genérica para mudança de status/
cancelamento de OS, `profiles.ativo` sem nenhum efeito (**agora confirmado
por execução real, não só leitura**), sem PDF/relatório de encerramento.

---

## 6. Comparação com o baseline

| Resultado | 1ª auditoria (código) | 2ª auditoria (execução real) |
|---|---|---|
| PASSOU | 5 | **73** |
| FALHOU | 22 | 17 (6 corrigidos e viraram PASSOU; 1 reclassificado p/ NÃO_IMPLEMENTADO/FALHOU trocado — ver seção 5) |
| BLOQUEADO | 108 | **49** |
| NÃO_IMPLEMENTADO | 29 | 26 (EST-010 saiu daqui, foi implementado; E2E-002 entrou) |
| NÃO_AUTOMATIZÁVEL | 3 | 2 (EST-013 saiu daqui — executado de verdade) |
| PENDENTE_DECISÃO | 9 | 9 |
| **Execução real (métrica nova)** | 6/176 (~3%) | **75/176 (~43%)** |

BLOQUEADO caiu de 108 para 49 (-55%), exatamente o objetivo desta rodada:
reduzir drasticamente por execução real, não por reclassificação otimista.

---

## 7. Cobertura completa (176 casos) — atualizada

Legenda: **[NEW]** = mudou de resultado nesta rodada. Casos sem "NEW" mantêm
o resultado e a evidência do relatório anterior (`docs/testing/TEST_REPORT.md`),
não foram reexecutados nesta rodada.

### Autenticação
| ID | Resultado | Evidência |
|---|---|---|
| AUT-001 | **PASSOU [NEW]** | 7/7 logins reais, `_etapa4_output.txt` |
| AUT-002 | PASSOU | (1ª auditoria, `_safe_checks_output3.txt`) |
| AUT-003 | PASSOU | (1ª auditoria) |
| AUT-004 | FALHOU (agora confirmado por execução) **[NEW: código→execução]** | `_etapa4_output.txt` — inativo executa RPC normalmente |
| AUT-005 | **PASSOU [NEW]** (era FALHOU) | fix P0-01, `_p0_validation_output.txt` |
| AUT-006 | PASSOU | (1ª auditoria) |
| AUT-007 | BLOQUEADO | não executado (logout) |
| AUT-008 | BLOQUEADO | não executado com sessão real de executor |
| AUT-009 | FALHOU | (1ª auditoria, código — rotas sem `meta.perfis`) |
| AUT-010 | BLOQUEADO | não executado |

### Cadastros
| ID | Resultado | Evidência |
|---|---|---|
| CAD-001 | BLOQUEADO | não executado via API autenticada |
| CAD-002 | BLOQUEADO | idem |
| CAD-003 | BLOQUEADO | idem |
| CAD-004 | FALHOU (confirmado por execução) **[NEW: código→execução]** | seed.sql inseriu 2 clientes com mesmo `documento` sem erro |
| CAD-005 | BLOQUEADO | não executado |
| CAD-006 | BLOQUEADO | não executado |
| CAD-007 | BLOQUEADO | não executado |
| CAD-008 | BLOQUEADO | não executado |
| CAD-009 | BLOQUEADO | não executado |
| CAD-010 | **PASSOU [NEW]** | `_etapa_extra_output.txt` — DELETE não afeta nenhuma linha (confirmado via SELECT) |
| CAD-011 | BLOQUEADO | não executado |
| CAD-012 | NÃO_IMPLEMENTADO | (1ª auditoria) |

### Orçamento
| ID | Resultado | Evidência |
|---|---|---|
| ORC-001 | **PASSOU [NEW]** | `_etapa7_output.txt`, passo 0a |
| ORC-002 | BLOQUEADO | não executado |
| ORC-003 | BLOQUEADO | não executado |
| ORC-004 | **PASSOU [NEW]** | `_etapa7_output.txt`, passo 0b |
| ORC-005 | **PASSOU [NEW]** | idem (item com `peca_id`, sem baixa prematura) |
| ORC-006 | BLOQUEADO | não executado |
| ORC-007 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| ORC-008 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| ORC-009 | **PASSOU [NEW]** | pgTAP `030_orcamento.sql` |
| ORC-010 | **PASSOU [NEW]** | idem |
| ORC-011 | **PASSOU [NEW]** | idem |
| ORC-012 | **PASSOU [NEW]** | idem + `_etapa7_output.txt` (R$200 = 2×R$100) |
| ORC-013 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| ORC-014 | **PASSOU [NEW]** | `_etapa7_output.txt`, passo 0c |
| ORC-015 | BLOQUEADO | não reexecutado |
| ORC-016 | FALHOU | (1ª auditoria, código) |

### Aprovação
| ID | Resultado | Evidência |
|---|---|---|
| APR-001 | **PASSOU [NEW]** | `_etapa4_output.txt` |
| APR-002 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| APR-003 | BLOQUEADO | não reexecutado |
| APR-004 | FALHOU | (1ª auditoria, código — sem campo "meio") |
| APR-005 | FALHOU | idem |
| APR-006 | FALHOU | idem |
| APR-007 | **PASSOU [NEW]** | `_etapa4_output.txt` |
| APR-008 | BLOQUEADO | não reexecutado |
| APR-009 | BLOQUEADO | não reexecutado |
| APR-010 | BLOQUEADO | não reexecutado |
| APR-011 | BLOQUEADO | não reexecutado |
| APR-012 | **PASSOU [NEW]** | `_etapa4_output.txt` |

### Ordem de Serviço
| ID | Resultado | Evidência |
|---|---|---|
| OS-001 | **PASSOU [NEW]** | `_etapa4_output.txt` + `_etapa7_output.txt` |
| OS-002 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| OS-003 | BLOQUEADO | não reexecutado |
| OS-004 | **PASSOU [NEW]** (era FALHOU) | fix P0-03, `_etapa7_output.txt` passo 1b |
| OS-005 | **PASSOU [NEW]** | `_etapa7_output.txt` |
| OS-006 | **PASSOU [NEW]** | idem (valores batendo) |
| OS-007 | **PASSOU [NEW]** | idem (transições em_diagnostico/em_execucao/aguardando_teste) |
| OS-008 | BLOQUEADO | não reexecutado |
| OS-009 | BLOQUEADO | não reexecutado |
| OS-010 | **PASSOU [NEW]** (era FALHOU) | fix P0-05, `_etapa6_output.txt` seção 5 |
| OS-011 | BLOQUEADO | não reexecutado |
| OS-012 | **PASSOU [NEW]** | `_etapa_extra_output.txt` |

### Adicionais
| ID | Resultado | Evidência |
|---|---|---|
| ADC-001 a ADC-008 | NÃO_IMPLEMENTADO | (1ª auditoria — módulo ausente, fora do escopo P0 autorizado) |

### Estoque
| ID | Resultado | Evidência |
|---|---|---|
| EST-001 | BLOQUEADO | não reexecutado |
| EST-002 | **PASSOU [NEW]** | pgTAP `020_estoque.sql` + `_etapa6_output.txt` |
| EST-003 | BLOQUEADO | não reexecutado |
| EST-004 | FALHOU | (1ª auditoria, código — reconfirmado indiretamente no E2E-001: conversão não gera movimento) |
| EST-005 | **PASSOU [NEW]** | `_etapa6_output.txt` seção 1 (origem/usuário/data presentes) |
| EST-006 | **PASSOU [NEW]** | `_etapa6_output.txt` seção 6 |
| EST-007 | **PASSOU [NEW]** | pgTAP + `_etapa6_output.txt` seção 2 |
| EST-008 | **PASSOU [NEW]** | pgTAP `020_estoque.sql` |
| EST-009 | **PASSOU [NEW]** (era FALHOU) | fix P0-04, pgTAP + `_etapa6_output.txt` seção 3 |
| EST-010 | **PASSOU [NEW]** (era NÃO_IMPLEMENTADO) | fix P0-05, `_etapa6_output.txt` seção 4 |
| EST-011 | **PASSOU [NEW]** | `_etapa_extra_output.txt` (403 permission denied) |
| EST-012 | BLOQUEADO | não reexecutado |
| EST-013 | **PASSOU [NEW]** (era NÃO_AUTOMATIZÁVEL) | `_etapa6_output.txt` seção 7 (duas chamadas paralelas via bash) |
| EST-014 | BLOQUEADO | não reexecutado formalmente |
| EST-015 | **PASSOU [NEW]** | confirmado ao longo do E2E-001 (orçamento nunca reserva estoque) |
| EST-016 | NÃO_AUTOMATIZÁVEL | venda+OS concorrentes na MESMA peça não testado especificamente |

### Execução
| ID | Resultado | Evidência |
|---|---|---|
| EXE-001 | **PASSOU [NEW]** | `_etapa7_output.txt` |
| EXE-002 | **PASSOU [NEW]** | `_etapa7_output.txt` (E2E-007) |
| EXE-003 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| EXE-004 | **PASSOU [NEW]** | `_etapa7_output.txt` (observação no 2º executor) |
| EXE-005 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| EXE-006 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| EXE-007 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| EXE-008 | BLOQUEADO | não reexecutado com sessão real de executor tentando alterar preço |
| EXE-009 | **PASSOU [NEW]** | mesma evidência de APR-007 |
| EXE-010 | **PASSOU [NEW]** | `_etapa7_output.txt` |

### Conclusão
| ID | Resultado | Evidência |
|---|---|---|
| CON-001 | **PASSOU [NEW]** | `_etapa7_output.txt` |
| CON-002 | FALHOU | (1ª auditoria, código) |
| CON-003 | **PASSOU [NEW]** | `_etapa7_output.txt` (checklist completo permitiu conclusão) |
| CON-004 | BLOQUEADO | não reexecutado |
| CON-005 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| CON-006 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| CON-007 | FALHOU | (1ª auditoria, código) |
| CON-008 | BLOQUEADO | não reexecutado |

### Financeiro
| ID | Resultado | Evidência |
|---|---|---|
| FIN-001 | **PASSOU [NEW]** | `_etapa7_output.txt` (valor calculado = R$200) |
| FIN-002 | BLOQUEADO | não reexecutado |
| FIN-003 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| FIN-004 | **PASSOU [NEW]** | `_etapa7_output.txt` |
| FIN-005 | BLOQUEADO | não reexecutado |
| FIN-006 | **PASSOU [NEW]** | `_etapa7_output.txt` |
| FIN-007 | BLOQUEADO | não reexecutado isoladamente |
| FIN-008 | BLOQUEADO | não reexecutado (só pagamento total testado) |
| FIN-009 | BLOQUEADO | não reexecutado |
| FIN-010 | PENDENTE_DECISÃO | BR-036 pendente |

### Liberação
| ID | Resultado | Evidência |
|---|---|---|
| LIB-001 | **PASSOU [NEW]** | pgTAP `040_liberacao.sql` + `_etapa7_output.txt` |
| LIB-002 | **PASSOU [NEW]** | pgTAP `040_liberacao.sql` |
| LIB-003 | **PASSOU [NEW]** | pgTAP + `_etapa4_output.txt` |
| LIB-004 | **PASSOU [NEW]** | `_etapa4_output.txt` |
| LIB-005 | **PASSOU [NEW]** | `_etapa4_output.txt` |
| LIB-006 | **PASSOU [NEW]** (era FALHOU) | fix P0-06, `_etapa4_output.txt` |
| LIB-007 | BLOQUEADO | não reexecutado |
| LIB-008 | BLOQUEADO | não reexecutado |

### Garantia
| ID | Resultado | Evidência |
|---|---|---|
| GAR-001 | **PASSOU [NEW]** | `_etapa7_output.txt` |
| GAR-002 | **PASSOU [NEW]** | `_etapa7_output.txt` |
| GAR-003 | **PASSOU [NEW]** | `_etapa_extra_output.txt` |
| GAR-004 | **PASSOU [NEW]** | `_etapa_extra_output.txt` |
| GAR-005 | FALHOU | (1ª auditoria, código) |
| GAR-006 | BLOQUEADO | não reexecutado |
| GAR-007 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| GAR-008 | NÃO_AUTOMATIZÁVEL | corrida em criação de garantia não testada |

### Auditoria
| ID | Resultado | Evidência |
|---|---|---|
| AUD-001 | FALHOU | (1ª auditoria, código) |
| AUD-002 | FALHOU | (1ª auditoria, código) |
| AUD-003 | FALHOU | (1ª auditoria, código) |
| AUD-004 | **PASSOU [NEW]** | `_etapa6_output.txt` seção 4 |
| AUD-005 | BLOQUEADO | não reexecutado |
| AUD-006 | **PASSOU [NEW]** | `_etapa_extra_output.txt` |

### Permissões
| ID | Resultado | Evidência |
|---|---|---|
| PER-001 | **PASSOU [NEW]** | `_etapa4_output.txt` |
| PER-002 | **PASSOU [NEW]** | `_etapa_extra_output.txt` |
| PER-003 | BLOQUEADO | não reexecutado (ação permitida não testada) |
| PER-004 | **PASSOU [NEW]** | `_etapa4_output.txt` |
| PER-005 | BLOQUEADO | não reexecutado |
| PER-006 | FALHOU | (1ª auditoria, código) |

### Documentos
| ID | Resultado | Evidência |
|---|---|---|
| DOC-001 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| DOC-002 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| DOC-003 | NÃO_IMPLEMENTADO | (1ª auditoria) |
| DOC-004 | BLOQUEADO | não reexecutado |
| DOC-005 | FALHOU | (1ª auditoria, código) |
| DOC-006 | **PASSOU [NEW]** (era FALHOU) | fix P0-02, `_etapa8_storage_output.txt` |

### Fluxo E2E
| ID | Resultado | Evidência |
|---|---|---|
| E2E-001 | **PASSOU [NEW]** | `_etapa7_output.txt` (fluxo completo) |
| E2E-002 | NÃO_IMPLEMENTADO **[NEW: reclassificado]** | depende de APR-002 + ADC (ambos ausentes) |
| E2E-003 | FALHOU **[NEW: reclassificado]** | conversão nunca checa estoque (mesma causa de EST-004) |
| E2E-004 | **PASSOU [NEW]** | pgTAP LIB-002 |
| E2E-005 | **PASSOU [NEW]** | `_etapa4_output.txt` |
| E2E-006 | **PASSOU [NEW]** | mesma evidência de GAR-002 |
| E2E-007 | **PASSOU [NEW]** | `_etapa7_output.txt` |
| E2E-008 | **PASSOU [NEW]** | `_etapa6_output.txt` seção 5 |
| E2E-009 | **PASSOU [NEW]** | EST-009 + APR-012 (nenhuma duplicação em nenhum passo testado) |
| E2E-010 | **PASSOU [NEW]** | conjunto da ETAPA 4 |

### Não funcional
| ID | Resultado | Evidência |
|---|---|---|
| NFR-001 | BLOQUEADO | falha forçada não simulada |
| NFR-002 | BLOQUEADO | idem |
| NFR-003 | PASSOU | (1ª auditoria, reconfirmado nesta rodada) |
| NFR-004 | PASSOU | (1ª auditoria, reconfirmado nesta rodada) |
| NFR-005 | BLOQUEADO | não reexecutado |
| NFR-006 | **PASSOU [NEW]** (era NÃO_IMPLEMENTADO) | suíte pgTAP rodada consistentemente nesta rodada |
| NFR-007 | **PASSOU [NEW]** (era NÃO_IMPLEMENTADO) | `BEGIN`/`ROLLBACK` confirmado sem resíduo em toda a suíte |
| NFR-008 | **PASSOU [NEW]** (era NÃO_IMPLEMENTADO) | `seed.sql` determinístico, rodado com sucesso |
| NFR-009 | BLOQUEADO | logs do projeto não inspecionados |
| NFR-010 | BLOQUEADO | não reexecutado |

### Decisão pendente
| ID | Resultado |
|---|---|
| PEN-001 a PEN-008 | PENDENTE_DECISÃO (inalterado — definição de negócio, não código) |

---

## 8. Próximos 10 problemas mais importantes

1. **Módulo de Adicionais totalmente ausente** (ADC-001 a 008, também trava
   E2E-002) — BR-009 é regra DEFINIDA e não tem nenhuma implementação.
2. **Aprovação parcial de orçamento ausente** (APR-002, OS-002) — BR-006 é
   DEFINIDA; hoje só existe aprovar/rejeitar o orçamento inteiro.
3. **`profiles.ativo` sem nenhum efeito, confirmado por execução real**
   (AUT-004) — usuário inativo continua operando normalmente no sistema.
4. **Sem trilha de auditoria para mudança de status/cancelamento de OS**
   (AUD-001/002/003) — `rpc_transicionar_os` não grava quem/quando/motivo.
5. **Conversão de orçamento em OS não verifica nem baixa estoque**
   (EST-004, E2E-003) — a baixa só acontece depois, manualmente, sem vínculo
   com os itens do orçamento aprovado.
6. **Sem mecanismo de desconto** (ORC-007/008, FIN-003) — só existe
   acréscimo pós-aprovação; BR-011 fica sem cobertura simétrica.
7. **Sem geração de PDF/relatório algum** (ORC-013, DOC-001/002/003,
   CON-005/006, GAR-007) — nenhuma lib de PDF no projeto.
8. **`CON-007`: apontamento de executor editável mesmo após OS
   concluída/liberada** — `os_executores_update_proprio` não checa o status
   da OS, só `usuario_id = auth.uid()`.
9. **Sem constraint de unicidade em `clientes.documento`** (CAD-004,
   confirmado por execução real nesta rodada — dois clientes com o mesmo
   CNPJ foram aceitos sem erro nem aviso).
10. **`APR-004/005/006`: "meio" da aprovação não é um campo distinto** —
    só nome + comprovante + timestamp são gravados; não dá pra saber depois
    se a aprovação foi por sistema, e-mail ou verbal, só que houve.

---

## 9. Arquivos gerados/alterados nesta rodada

- `supabase/migrations/20260810160000_p0_correcoes_criticas.sql` (correções P0)
- `supabase/migrations/20260810160100_habilitar_pgtap.sql` (infra de teste)
- `supabase/seed.sql` (massa de teste determinística)
- `supabase/tests/_helpers.sql` (ajustado: grants pro schema `tests`)
- `supabase/tests/010_seguranca_permissao_anon_bypass.sql`,
  `020_estoque.sql`, `030_orcamento.sql`, `040_liberacao.sql` (reescritos
  pra rodar via `db query`, sem `\i`, com `UNION ALL` como última instrução)
- `docs/testing/scripts/etapa4_rbac_real.sh`, `etapa6_estoque_real.sh`,
  `etapa7_e2e_real.sh` (novos)
- `docs/testing/_p0_validation_output.txt`, `_etapa4_output.txt`,
  `_etapa6_output.txt`, `_etapa7_output.txt`, `_etapa8_storage_output.txt`,
  `_etapa_extra_output.txt` (evidência bruta desta rodada)
- `docs/testing/TEST_REPORT.md` — preservado sem alteração, como baseline
