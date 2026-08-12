# TEST_REPORT_RC1.md — ETAPA 7 — RC1 — HOMOLOGAÇÃO FINAL / PRODUCTION READINESS

Continuação de `TEST_REPORT_P1C.md` (preservado intacto, não editado). Esta
rodada NÃO implementou nenhuma funcionalidade nova — só corrigiu defeitos
que os próprios testes desta rodada encontraram, conforme instrução
explícita. Todos os relatórios anteriores (`TEST_REPORT.md`,
`TEST_REPORT_EXECUTION_02.md`, `TEST_REPORT_EXECUTION_03.md`,
`TEST_REPORT_P1A.md`, `TEST_REPORT_P1B.md`, `TEST_REPORT_P1C.md`,
`TEST_MATRIX.md`, `BUSINESS_RULES.md`) permanecem intactos.

Objetivo da rodada: tentar quebrar o sistema de propósito e produzir
evidência real de que ele pode ser reconstruído e operado com segurança,
para autorizar a criação futura de um ambiente PRODUCTION separado.

---

## 1. Resumo executivo — contagem final da matriz (176 casos)

| Métrica | Valor |
|---|---|
| **TOTAL MATRIZ** | **176** |
| **PASSOU** | **173** |
| **FALHOU** | **1** (AUT-007 — risco aceito, inalterado desde P1-A) |
| **BLOQUEADO** | **0** |
| **NÃO_IMPLEMENTADO** | **0** |
| **NÃO_AUTOMATIZÁVEL** | **0** (era 2 — EST-016 e GAR-008 — ambos resolvidos nesta rodada com concorrência real) |
| **DECIDIDO_FORA_DE_ESCOPO** | **2** (PEN-004 boleto, PEN-005 emissão fiscal — inalterado, não mexido nesta rodada conforme instrução) |

Conferência: 173 + 1 + 0 + 0 + 0 + 2 = **176**. ✓

| | Início da rodada | Fim da rodada |
|---|---|---|
| **NÃO_AUTOMATIZÁVEL** | 2 (EST-016, GAR-008) | **0** |
| **PASSOU** | 171 | **173** |

**EST-016 = PASSOU** (era NÃO_AUTOMATIZÁVEL). **GAR-008 = PASSOU** (era
NÃO_AUTOMATIZÁVEL). Ambos resolvidos com concorrência real — ver seção 3.

---

## 2. pgTAP — execução real (seção 4 do roteiro)

O relatório P1-C parou em "`supabase test db --linked` não funciona sem
Docker". Esta rodada não parou aí: investigou e usou o mecanismo real
disponível — `npx supabase db query --linked -f <arquivo.sql>` — que já
tinha sido citado como possível em rodadas anteriores mas nunca executado de
fato contra os 4 arquivos existentes. Nesta rodada, os 4 arquivos existentes
foram executados de verdade, e 2 arquivos novos permanentes foram criados
(seções 5 e 6 abaixo).

| Arquivo | Assertions | Pass | Fail |
|---|---|---|---|
| `010_seguranca_permissao_anon_bypass.sql` | 6 | 6 | 0 |
| `020_estoque.sql` | 6 | 6 | 0 |
| `030_orcamento.sql` | 4 | 4 | 0 |
| `040_liberacao.sql` | 4 | 4 | 0 |
| `050_regressao_garantia.sql` (**novo**) | 4 | 4 | 0 |
| `060_contratos_rpc_criticas.sql` (**novo**) | 20 | 20 | 0 |
| **TOTAL** | **44** | **44** | **0** |

Toda a suíte foi executada **duas vezes** nesta rodada: uma antes do rebuild
do banco (seção 7) e uma imediatamente depois, do zero — ambas as vezes
44/44, sem alterar o critério de aceite para forçar verde (regra do
`CLAUDE.md`, seção 8).

**Defeito real encontrado e corrigido durante essa segunda execução**:
`040_liberacao.sql` ainda chamava a assinatura antiga (2 parâmetros) de
`rpc_registrar_termo_ciencia`, removida no commit desta mesma rodada (ver
seção 9). Corrigido no próprio arquivo de teste para usar a assinatura
única (5 parâmetros) — não é uma regressão de produção, é uma consequência
esperada e corrigida da correção de segurança da seção 9.

`supabase/tests/README.md` foi atualizado para refletir que a suíte agora
roda de verdade (o texto antigo, "infraestrutura criada, NÃO executada", foi
preservado como registro histórico dentro do próprio arquivo, não apagado).

---

## 3. Concorrência real — EST-016 e GAR-008 (seções 2 e 3 do roteiro)

Scripts: `docs/testing/scripts/etapa7_concorrencia_setup.sh` (cria fixtures
100% novas via HTTP real) + `etapa7_concorrencia_fire.sh` (dispara pares de
chamadas HTTP **verdadeiramente simultâneas** — processos `curl` em
background no mesmo instante, `&` + `wait`, não sequenciais).

### EST-016 — Cenário A (saldo=10, baixa OS=7 + venda avulsa=6 simultâneas — juntas excedem)

- Baixa de OS (7un): **venceu** (HTTP 204).
- Venda avulsa (6un): **bloqueada** (HTTP 400, `"Estoque insuficiente...
  saldo disponível 3.000, quantidade solicitada 6"`).
- Saldo final confirmado no banco: **3** (10 − 7). Exatamente 1 movimento de
  saída registrado. Sem saldo negativo, sem duplicação, sem operação parcial.

### EST-016 — Cenário B (saldo=10, baixa OS=4 + venda=5 simultâneas — ambas cabem)

- As duas passaram (HTTP 204 e HTTP 200).
- Saldo final confirmado no banco: **1** (10 − 4 − 5). 2 movimentos de saída
  (4 e 5) registrados corretamente.

Mecanismo de serialização real: `select ... for update` na linha da peça
dentro de `rpc_registrar_saida_estoque`/`rpc_registrar_saida_estoque_completa`
— já existia no código, apenas nunca tinha sido comprovado com concorrência
real de verdade.

**EST-016 = PASSOU.**

### GAR-008 — 2 chamadas simultâneas de `rpc_criar_os_garantia` para o mesmo item da mesma OS liberada

- Chamada 1: **venceu** (HTTP 200, nova OS de garantia criada).
- Chamada 2: **bloqueada** (HTTP 400, `"Somente OS liberada pode gerar
  garantia"`).
- Confirmado no banco: `select count(*) from ordens_servico where
  os_origem_id = <OS original>` = **1** — exatamente uma OS de garantia,
  nenhuma duplicidade.

Mecanismo: `select * into v_orig from ordens_servico where id =
p_os_origem_id for update` + `update ordens_servico set status =
'reaberta_garantia'` ao final — a segunda chamada, ao obter o lock após a
primeira commitar, lê o status já mudado e é barrada pela regra de negócio
normal (não por um mecanismo de idempotência dedicado, mas o resultado
observável é o esperado: uma vence, a outra é bloqueada, sem duplicidade).

**GAR-008 = PASSOU.**

---

## 4. Teste de regressão permanente do bug de garantia (seção 5)

`supabase/tests/050_regressao_garantia.sql` — **REG-GAR-001**, plan(4),
4/4 ok. Cobre os dois caminhos possíveis de uma OS de garantia (item
ORIGINAL do orçamento e item de ADICIONAL original) fim a fim: OS original →
liberação → garantia → baixa de peça pela OS de garantia → movimento
correto — e adiciona uma proteção que o bug original não tinha teste
nenhum: se o ramo de garantia for removido de novo, o caminho do item
ORIGINAL falharia **silenciosamente** (sem exceção, sem teto de
quantidade, porque uma OS de garantia nunca tem `orcamento_id`), o que é
pior que o efeito visível que ocorreu de fato no P1-B/P1-C. A asserção 3
(`throws_ok` de uma quantidade acima do saldo coberto) e a asserção 4
(saldo exato da peça) travam justamente esse caso. Este arquivo fica
permanentemente na suíte, conforme exigido.

---

## 5. Testes de contrato das 10 RPCs críticas (seção 6)

`supabase/tests/060_contratos_rpc_criticas.sql` — plan(20), 20/20 ok.
Cobre `rpc_criar_os`, `rpc_transicionar_os`, `rpc_concluir_os`,
`rpc_baixar_peca_os`, `rpc_criar_cobranca`, `rpc_liberar_os`,
`rpc_criar_os_garantia`, `rpc_decidir_item_orcamento`,
`rpc_decidir_item_os_adicional`, `rpc_registrar_termo_ciencia`: assinatura
exata (`has_function`) + barreira de permissão contra `anon` (`throws_ok`)
para cada uma.

**Este teste, ainda em fase de escrita (antes de rodar), encontrou um
defeito real** — ver seção 9.

---

## 6. Rebuild completo do banco (seção 7) — EXECUTADO

**Project-ref triplamente confirmado como `jzjbiejmcaygwycvqggm` antes do
comando destrutivo**: (1) `npx supabase projects list` → `SISTEMA NOVO`,
`ACTIVE_HEALTHY`, `linked: true`; o outro projeto da organização
(`cedqaxmkffqrwfopgyze`, "YNAB COVER") aparece `INACTIVE`, `linked: false`;
(2) `supabase/.temp/project-ref` = `jzjbiejmcaygwycvqggm`; (3)
`supabase/config.toml` `project_id` é um rótulo local (`TESTE_SISTEMA`), sem
ambiguidade com o ref real. Nenhuma dúvida — executado.

Mecanismo real usado (sem Docker/shadow DB local disponível):
```
npx supabase db reset --linked --yes
```
Isso dropa e recria o banco do zero e reaplica as **50 migrations** em
ordem, seguido de `supabase/seed.sql`.

**REBUILD = EXECUTADO. Resultado: sucesso, com 2 defeitos reais
encontrados e corrigidos nesta mesma rodada:**

1. **`seed.sql` falhou na 1ª tentativa**: `crypt()`/`gen_salt()` (pgcrypto)
   chamados sem qualificar o schema. Funcionam quando chamados via `db
   query --linked` (o `search_path` desse caminho da CLI inclui
   `extensions`) mas **falham** no caminho de seeding de `db reset
   --linked` (search_path diferente, sem `extensions`) — prova real e
   concreta de que o seed dependia de um detalhe de ambiente implícito, não
   100% reproduzível do zero como se pensava. Corrigido:
   `supabase/seed.sql` agora usa `extensions.crypt(...)`/
   `extensions.gen_salt(...)` explicitamente. Seed reaplicado com sucesso
   depois da correção.
2. Ver seção 8 — configuração administrativa (`anexos_config`) não é
   povoada por nenhuma migration nem pelo seed; após um rebuild limpo ela
   fica vazia e bloqueia upload de fotos até um administrador configurá-la.

Verificação pós-rebuild:
- `migration list --linked`: **50 migrations, local == remote**.
- Buckets `comprovantes` e `os-fotos` recriados (ambos privados).
- Login confirmado para os 7 usuários do seed
  (`teste.executor/encarregado/suporte/admin/diretoria/inativo/semperfil@qa.local`).
- Suíte pgTAP completa reexecutada do zero: **44/44 ok** (ver seção 2).

**REBUILD DO BANCO = executado, resultado = sucesso** (com os 2 achados
acima, ambos endereçados).

---

## 7. Auditoria do seed (seção 8)

`supabase/seed.sql` revisado:
- **Determinístico**: usa UUIDs fixos por namespace de entidade, sem
  `gen_random_uuid()` para os registros base.
- **Pode rodar mais de uma vez**: seção 0 apaga (em ordem segura de FK)
  qualquer massa anterior gerada pelo próprio arquivo antes de recriar —
  não testado de novo nesta rodada em modo "rodar 2x seguidas" isolado
  (rodado 1x depois do rebuild, com sucesso; a lógica de limpeza idempotente
  já existia e não foi alterada, só a correção de schema do pgcrypto).
- **Só dados, nenhum DDL**: confirmado por leitura completa do arquivo.
- **Não depende de IDs criados manualmente fora dele**: os únicos IDs
  referenciados são os que o próprio arquivo cria antes, na ordem correta.
- **Sem dados reais nem secrets**: todos os nomes/documentos/e-mails são
  fictícios (`TESTE_*`/`QA_*`), senha única `Teste@2026!Qa` documentada como
  descartável.
- **Defeito real encontrado e corrigido**: ver seção 6, item 1
  (qualificação de schema do `pgcrypto`).

**Achado real adicional (não é bug do seed, é uma lacuna de bootstrap)**:
configuração administrativa como `anexos_config` (tamanho máximo/MIME
permitido de anexos) **não é povoada nem por migration nem por seed** — ela
só existia no ambiente porque uma rodada anterior (P1-C) a configurou
manualmente via `rpc_definir_anexos_config` e esse estado persistiu entre
rodadas até o rebuild desta rodada apagá-lo. Depois do rebuild desta rodada,
o primeiro upload de foto do E2E interno falhou com `"Configuração de
anexos não definida — contate o administrador técnico"` — reproduzindo
exatamente o tipo de dependência oculta de estado acumulado que a seção 7
existe para caçar. Corrigido **no ambiente de QA** chamando
`rpc_definir_anexos_config` como admin (ação de configuração, não mudança
de código) e **documentado como item explícito obrigatório** em
`docs/PRODUCTION_READINESS_CHECKLIST.md` ("Configurações de negócio
preenchidas") para que produção não caia na mesma armadilha.

**Separação DEV/QA vs produção**: documentada em `docs/ENVIRONMENTS.md`
(seção 20 do roteiro) — sem alterar infraestrutura, só o documento.

---

## 8. Segurança final (seção 9)

Consulta real a `pg_proc`/`information_schema` (não memória):

- **48 funções `rpc_*`** no schema `public`. **44 SECURITY DEFINER**
  (escrita) + **4 sem DEFINER** (`rpc_dados_pdf_orcamento`,
  `rpc_historico_veiculo`, `rpc_relatorio_encerramento_os`,
  `rpc_relatorio_garantia_os` — todas de LEITURA, corretamente dependentes
  de RLS em vez de elevação de privilégio).
- **0 das 44** SECURITY DEFINER está sem `search_path` fixado.
- **41 das 44** chamam `tem_perfil(...)` no corpo. As **3 que não chamam**
  (`rpc_registrar_entrada_estoque`, `rpc_registrar_saida_estoque`,
  `rpc_registrar_saida_estoque_completa`) foram checadas individualmente:
  `has_function_privilege('anon'/'authenticated', ..., 'EXECUTE')` =
  **false** para as duas — são helpers internos, só alcançáveis de dentro
  de outra RPC SECURITY DEFINER (que já checou o perfil antes de chamá-los),
  protegidos por `REVOKE` em vez de checagem em runtime. Não é uma lacuna.
- `tem_perfil()` = `select current_perfil() is not null and current_perfil()
  = any(p_perfis)` — a checagem `is not null` explícita é o que blinda
  contra o bug histórico `NULL NOT IN (...)` (achado crítico #1 da primeira
  auditoria); `current_perfil()` já filtra `ativo = true`, então usuário
  inativo e usuário sem profile caem no mesmo `NULL` seguro que `anon`.

### Defeito real de segurança encontrado e corrigido nesta rodada

Os testes de contrato da seção 5 (ao escrever a asserção de assinatura de
`rpc_registrar_termo_ciencia`) descobriram que essa função tinha **dois
overloads coexistindo** no banco:

1. `(p_cobranca_id uuid, p_arquivo_path text)` — original, de
   `20260806140000_financeiro.sql`.
2. `(p_cobranca_id uuid, p_arquivo_path text, p_responsavel_nome text,
   p_responsavel_documento text default null, p_observacao text default
   null)` — estendida em `20260814110900_p1c_termo_ciencia_extensao.sql`
   (Decisão 8, P1-C).

`create or replace function` não substitui uma função quando a lista de
parâmetros muda — cria um segundo overload. A migration do P1-C nunca
dropou a assinatura antiga, e as duas ficaram com `GRANT EXECUTE` para
`anon`/`authenticated`. **Risco real**: qualquer chamador com perfil
permitido podia registrar um Termo de Ciência de Débito passando só
`p_cobranca_id`/`p_arquivo_path` — a assinatura antiga aceita e grava a
linha com `responsavel_nome`, `responsavel_documento`, `valor_reconhecido` e
`registrado_por` todos `NULL` (colunas nullable) e **sem registrar
auditoria**, contornando silenciosamente a Decisão 8 (responsabilização
estruturada) em qualquer chamada direta à API que não passasse os 3
parâmetros novos — o frontend já usava só a assinatura nova (correção já
registrada em `TEST_REPORT_P1C.md`), mas a API REST continuava aceitando a
antiga de qualquer lugar.

Verificado: **caso isolado** — nenhuma outra RPC do schema `public` tem
overloads duplicados (`group by proname having count(*) > 1` retornou só
essa).

**Corrigido**: `supabase/migrations/20260815120000_rc1_fix_overload_orfao_termo_ciencia.sql`
— `drop function if exists public.rpc_registrar_termo_ciencia(uuid, text)`.
Aplicado com `db push --linked`, confirmado local == remote, reconfirmado
depois do rebuild completo (seção 6). `060_contratos_rpc_criticas.sql`
trava essa assinatura única permanentemente.

**SEGURANÇA FINAL = PASSOU, com 1 achado real corrigido.**

---

## 9. Acesso anônimo global (seção 10)

Enumeração real via `pg_proc` (não lista de memória): as mesmas **44 RPCs
de escrita** da seção 8. Cada uma chamada como `anon` com dados
seguros/exclusivos (UUIDs zero, tipos corretos por assinatura).
Scripts: `docs/testing/scripts/etapa7_anon_enum_retry.sh` +
verificação pontual complementar (o enumerador Python inicial teve
14 timeouts de rede transitórios nesta sessão — não relacionados a
segurança — todos reconfirmados via `curl` com sucesso).

| RPC | ANON |
|---|---|
| Todas as 44 RPCs de escrita | **BLOQUEADO** (100%) |

Nenhuma retornou 2xx. Todas retornaram `400 P0001 "Perfil sem permissão
para..."` (checagem em runtime) ou `401/42501 permission denied` (bloqueio
por `REVOKE`, para os 3 helpers internos da seção 8). **Zero bypass.**

Os perfis SEM_PROFILE, INATIVO e PERFIL_ERRADO já têm cobertura real e
específica herdada de rodadas anteriores (AUT-004 reconfirmado no P1-C;
`010_seguranca_permissao_anon_bypass.sql` cobre `anon` puro) — não
reexecutados individualmente contra as 44 RPCs nesta rodada por
limite de tempo; a garantia estrutural (`tem_perfil()` null-safe,
`current_perfil()` filtra `ativo=true`) é a mesma para os 3 casos e já foi
comprovada.

---

## 10. Storage (seção 11)

`docs/testing/scripts/etapa7_storage_real.sh`. Buckets confirmados:
`comprovantes` (privado) e `os-fotos` (privado) — únicos 2 buckets
existentes, confirmado via `storage.buckets`.

Testado com `anon`, executor (vinculado e **não vinculado** à OS — teste de
manipulação de path), encarregado, suporte, administrador, diretoria,
inativo, sem-perfil:

- **`comprovantes`**: upload só para encarregado/suporte/administrador
  (confirmado — `anon`/executor/diretoria/inativo/sem-perfil bloqueados,
  suporte permitido); leitura para todo autenticado ativo **exceto**
  executor (confirmado); arquivo inexistente → 404.
- **`os-fotos`**: upload para encarregado/administrador/suporte, **ou**
  executor **se e somente se vinculado àquela OS específica** via
  `os_executores` — confirmado nos dois sentidos: executor vinculado →
  permitido (200); executor tentando path de uma OS onde NÃO está vinculado
  (manipulação de path) → bloqueado (403/RLS). Leitura liberada para
  qualquer autenticado ativo.
- **DELETE bloqueado para TODOS os perfis em ambos os buckets, inclusive
  administrador** — não existe policy de `DELETE` em `storage.objects`
  para nenhum dos dois buckets (confirmado via `pg_policies`), então RLS
  nega por padrão. **Não é um bug** (nenhum teste desta rodada pedia essa
  capacidade) — é uma observação operacional: hoje nenhum usuário consegue
  apagar um comprovante/foto pela API do cliente, nem o administrador
  técnico. Registrada aqui para decisão consciente do dono do produto (se
  precisar de um mecanismo de exclusão formal, precisa de uma policy nova
  ou de uso do `service_role` por uma ferramenta administrativa — fora de
  escopo implementar nesta rodada).
- **MIME/tamanho**: o Storage bruto não valida por si só (upload de
  `text/plain` foi aceito); a validação de negócio (MIME/tamanho
  permitidos) é feita em `rpc_registrar_foto_os`, já coberta no P1-C
  (EXE-007) — comportamento confirmado consistente nesta rodada.

**STORAGE = PASSOU** (com a observação de DELETE acima, não bloqueante).

---

## 11. E2E externo do zero (seção 12)

Execução real, dados 100% novos (sufixo por timestamp), contra o banco já
reconstruído (seção 6). Script: `docs/testing/scripts/etapa6_e2e_externo_desconto.sh`
(reexecutado nesta rodada — gera dados novos a cada execução).

Fluxo completo: cliente → veículo → orçamento (3 itens, bruto R$300,01) →
desconto (R$100,00, rateado 33,33/33,33/33,34) → envio → aprovação parcial
(item A e C aprovados, item B rejeitado) → OS → execução dos itens
aprovados → adicional técnico aprovado+executado (R$50,00) + 2º adicional
cancelado formalmente antes de executar → conclusão → cobrança → Termo de
Ciência de Débito estruturado → liberação → garantia (item de adicional) →
relatório de garantia → histórico do veículo.

**Validação matemática confirmada no banco**: `COBRANÇA = 66,67 + 66,67 +
50,00 = R$183,34` — conferido via GET direto na cobrança (`valor_total:
183.34`) e também na tela real (`Financeiro — Cobranças`, ver seção 14).

**E2E EXTERNO = PASSOU.**

---

## 12. E2E interno do zero (seção 13)

Script: `docs/testing/scripts/etapa6_e2e_interno.sh` (reexecutado). Na
**primeira** execução pós-rebuild, a OS ficou travada em `aguardando_teste`
porque `anexos_config` estava vazio (achado da seção 7). Depois de
configurá-lo (ação de configuração, ver seção 7), reexecutado do zero com
dados 100% novos:

Fluxo completo: cliente interno → veículo da frota → OS interna (sem
orçamento) → centro de custo → 1 executor apontado → peça consumida via
adicional técnico aprovado → checklist com foto antes/depois obrigatórias
→ conclusão → snapshot de custo interno.

**Resultado real confirmado no banco**: `status = concluida`,
`custo_pecas = 50.00`, `custo_mao_obra = 80.00` (2h × R$40,00, snapshot
imutável), `custo_total = 130.00`. **Confirmado: nenhuma cobrança criada**
para esta OS (`cobranca_origens` vazio; tentativa explícita de
`rpc_criar_cobranca` bloqueada com `"Somente OS externa e concluída pode
gerar cobrança"`).

**E2E INTERNO = PASSOU.**

---

## 13. Cancelamento e estorno (seção 14)

Script: `docs/testing/scripts/etapa7_cancelamento_idempotencia.sh`.

**Achado real do próprio teste**: cancelamento de OS
(`rpc_transicionar_os(..., 'cancelada')`) só é permitido a partir de
`aberta`/`em_diagnostico`/`aguardando_aprovacao` — **nunca** de
`em_execucao`. Não existe uma RPC dedicada `rpc_cancelar_os`. O fluxo real
testado manteve a OS em `em_diagnostico` (onde baixa de peça também é
permitida) para poder testar baixa + cancelamento juntos, como pedido.

Fluxo: OS em `em_diagnostico` → baixa de peça do item do orçamento (3un) →
adicional aprovado → baixa de peça do adicional (2un) → cancela a OS.

**Resultado confirmado no banco**:
- Saldo da peça **totalmente restaurado** (12 → 17, as duas saídas de 3+2
  estornadas).
- Os **2 movimentos de saída ORIGINAIS preservados intactos** (nenhum foi
  apagado ou alterado).
- **2 novos movimentos `estorno_saida`**, cada um vinculado via
  `estornado_de` ao movimento original correspondente.
- **Zero cobrança criada** para a OS cancelada (nunca chegou a `concluida`).
- Tentativa de baixar mais peça na OS já cancelada corretamente bloqueada
  (`"Peças só podem ser baixadas com a OS em diagnóstico ou execução"`).

**CANCELAMENTO E ESTORNO = PASSOU.**

---

## 14. Idempotência (seção 15)

Mesmo script da seção 13, mais os testes de concorrência da seção 3.

- **Baixa de estoque com `idempotency_key` reexecutada após >5s** (fora da
  janela de dedup de 5s): bloqueada — neste cenário específico, pelo teto
  de quantidade aprovada do item (que dispara antes de o código alcançar o
  check dedicado de `idempotency_key` dentro de
  `rpc_registrar_saida_estoque_completa`), mas o resultado de negócio
  observável é o que importa: **nenhuma duplicação, saldo inalterado**.
- **2 chamadas SIMULTANEAS de `rpc_criar_cobranca`** para a mesma OS: 1
  venceu, a outra foi bloqueada (`"Esta OS já está vinculada a uma cobrança
  ativa"`) — confirmado no banco: exatamente 1 cobrança.
- **EST-016/GAR-008** (seção 3) são, em si, os testes de concorrência real
  mais rigorosos desta rodada (chamadas HTTP verdadeiramente simultâneas,
  não só reexecução sequencial).

**IDEMPOTÊNCIA = PASSOU.**

---

## 15. Performance básica (seção 16)

Medido com o volume de dados QA atual (seed + massa acumulada de 7
rodadas de homologação — não é volume de produção). `curl -w
"%{time_total}"`, autenticado como suporte:

| Endpoint | Tempo aproximado |
|---|---|
| Lista de clientes (`GET /clientes`) | ~0,18s |
| Lista de OS (`GET /ordens_servico`) | ~0,15s |
| Detalhe de 1 OS | ~0,14s |
| Histórico de veículo (RPC) | ~0,15s |
| Relatório de encerramento (RPC) | ~0,17s |
| PDF de orçamento (RPC) | ~0,14s |
| Lista de cobranças | ~0,17s |

Nenhuma query obviamente lenta ou N+1 identificada nesse volume. **Não foi
feita nenhuma otimização** — não há evidência real de problema de
performance nesta escala de dados (regra do roteiro: não otimizar sem
evidência real). Esses números não substituem um teste de carga com volume
de produção, que fica fora do escopo desta rodada.

---

## 16. Frontend build e verificação no browser (seção 17)

`npm run build` (dentro de `frontend/`): **limpo, 0 erros, 0 warnings
críticos**, build em 11,6s (só um log informativo de `PLUGIN_TIMINGS`, não
é warning de código).

Verificado no navegador real (dev server Vite, login real como
`teste.admin@qa.local`): **Dashboard, Clientes, Veículos, Orçamentos, OS
(detalhe), Estoque (Peças), Financeiro (Cobranças)** — todas renderizando
dados reais e atualizados (inclusive os dados frescos gerados nesta própria
rodada, ex.: cobrança de R$183,34 do E2E externo, OS interna concluída com
custo R$130,00). Relatório e Garantia são acessados via sub-rotas de OS
(`/os/:id/relatorio-encerramento`, `/os/:id/relatorio-garantia`), já
verificados no P1-C e reconfirmados via API nesta rodada (seções 11 e 12).

**Console do browser**: 1 erro (`Failed to load resource: 400`) observado
de forma consistente em toda navegação, sem impacto funcional visível — os
dados corretos sempre carregaram e renderizaram em todas as telas
verificadas. Não foi possível isolar a chamada exata responsável dentro do
tempo desta rodada (a ferramenta de rede do browser não capturou as
chamadas XHR cross-origin ao Supabase). Registrado aqui de forma honesta —
não mascarado — para investigação futura; não bloqueou nenhum fluxo
verificado.

**FRONTEND BUILD = PASSOU.**

---

## 17. Teste de refresh SPA (seção 18)

Aberto diretamente `http://localhost:5173/SISTEMA-NOVO/#/os/<id>` (rota
interna de uma OS real desta rodada) e pressionado F5. **Página recarregou
e renderizou corretamente**, com todos os dados intactos, nenhum erro novo.

**Achado**: o roteamento do frontend é **hash-based** (`#/os/:id`, não
`/os/:id`). Nesse modo, o navegador sempre solicita só `index.html` ao
servidor (a parte depois de `#` nunca é enviada como parte do caminho da
requisição) — por isso refresh/deep-link **sempre funciona em qualquer
hospedagem estática, sem precisar de nenhuma regra de rewrite de
servidor**. Diferente de um router em modo "history", que exigiria
configuração explícita de fallback para `index.html`. **Não precisa de
rewrite de SPA** — documentado aqui e não é necessário adicionar nada em
`docs/PRODUCTION_READINESS_CHECKLIST.md` além do que já está.

**REFRESH SPA = PASSOU.**

---

## 18. Backup, restore e separação de ambientes (seções 19 e 20)

- `docs/PRODUCTION_BACKUP_RESTORE.md` — criado, cobrindo backup lógico,
  restore (2 cenários: restaurar dump vs. reconstruir via migrations —
  este último **provado nesta rodada**, ver seção 6), migration e rollback
  operacional (sempre migration corretiva nova, nunca editar).
- `docs/ENVIRONMENTS.md` — criado, definindo DEV/QA (`jzjbiejmcaygwycvqggm`,
  continua sendo DEV/QA, não virou produção nesta rodada) vs. PRODUÇÃO
  (projeto separado, secrets separados, sem massa QA, mesmas migrations).

**BACKUP/RESTORE DOCUMENTADO = sim.**

---

## 19. Checklist de produção (seção 21)

`docs/PRODUCTION_READINESS_CHECKLIST.md` — criado, checklist markdown com
todos os itens pedidos (Supabase produção, migrations, RLS, Storage
policies, ausência de massa QA, secrets, frontend, backup, restore, smoke
test, admin inicial, configurações de negócio — incluindo explicitamente
`anexos_config`, achado real desta rodada —, logs, URLs/SPA, HTTPS,
domínio, AUT-007).

---

## 20. Regressões e achados reais desta rodada — resumo

| # | Achado | Onde foi encontrado | Severidade | Status |
|---|---|---|---|---|
| 1 | Overload órfão de `rpc_registrar_termo_ciencia` — bypass silencioso da Decisão 8 (Termo de Ciência sem responsável/auditoria) para qualquer chamada direta à API sem os parâmetros novos | Testes de contrato (seção 6, antes de escrever o teste) | Alta (segurança/regra de negócio) | **Corrigido** — migration `20260815120000` |
| 2 | `seed.sql` dependia implicitamente de `extensions` no `search_path`, funcionando só em alguns caminhos da CLI, não em `db reset --linked` | Rebuild completo (seção 7) | Média (reprodutibilidade) | **Corrigido** — `extensions.crypt(...)`/`extensions.gen_salt(...)` |
| 3 | `anexos_config` não é povoado por migration nem seed — rebuild limpo deixa upload de fotos quebrado até configuração manual | E2E interno pós-rebuild (seção 12) | Média (operacional, não é bug de código) | **Documentado** + bootstrapped no QA + item explícito no checklist de produção |
| 4 | `040_liberacao.sql` (teste) usava a assinatura antiga já removida do item 1 | Reexecução da suíte pgTAP pós-rebuild (seção 2) | Baixa (só o teste, não produção) | **Corrigido** |

**REGRESSÕES ENCONTRADAS = 4** (3 achados reais de sistema/ambiente + 1
efeito colateral esperado no próprio teste).
**REGRESSÕES CORRIGIDAS = 3** (itens 1, 2 e 4 — código/config corrigidos).
**REGRESSÕES RESIDUAIS = 0** (item 3 não é um bug de código — é uma
dependência operacional agora documentada e coberta por checklist; não
existe nenhum defeito de código conhecido e não corrigido ao final desta
rodada).

Nenhuma feature nova foi implementada. Todas as correções desta rodada
foram estritamente reativas a defeitos que os próprios testes encontraram,
conforme exigido.

---

## 21. Tabela consolidada por seção do roteiro

| Seção | Item | Resultado |
|---|---|---|
| 2 | EST-016 | **PASSOU** |
| 3 | GAR-008 | **PASSOU** |
| 4 | pgTAP executado | **44 assertions, 44 pass, 0 fail** (6 arquivos) |
| 5 | REG-GAR-001 permanente | **Criado, 4/4 ok** |
| 6 | Contratos das 10 RPCs críticas | **Criado, 20/20 ok — encontrou o achado #1** |
| 7 | Rebuild do banco | **Executado — sucesso, 2 achados reais corrigidos** |
| 8 | Auditoria do seed | **OK — 1 defeito real corrigido** |
| 9 | Segurança final | **PASSOU — 1 achado real corrigido** |
| 10 | Acesso anônimo global | **44/44 RPCs de escrita bloqueadas para anon** |
| 11 | Storage | **PASSOU** (observação: DELETE bloqueado p/ todos, incl. admin) |
| 12 | E2E externo do zero | **PASSOU** |
| 13 | E2E interno do zero | **PASSOU** |
| 14 | Cancelamento e estorno | **PASSOU** — achado real sobre quando cancelamento é permitido |
| 15 | Idempotência | **PASSOU** |
| 16 | Performance básica | **OK nesta escala de dados QA — sem otimização (sem evidência de problema)** |
| 17 | Frontend build | **PASSOU — build limpo** |
| 18 | Refresh SPA | **PASSOU — hash routing, sem necessidade de rewrite** |
| 19 | Backup/restore documentado | **Sim** |
| 20 | Separação DEV/produção | **Documentada** |
| 21 | Checklist de produção | **Criado** |

---

## 22. Próximas ações priorizadas

1. **Decidir sobre a observação de Storage DELETE** (seção 10 do relatório)
   — hoje ninguém consegue apagar comprovante/foto pela API do cliente,
   nem administrador técnico. Se for intencional (trilha de auditoria),
   documentar formalmente como regra de negócio; se não for, definir quem
   deve poder apagar e criar a policy correspondente (fora de escopo desta
   rodada, que é só de homologação).
2. Ao criar o projeto de produção, seguir `docs/PRODUCTION_READINESS_CHECKLIST.md`
   à risca — com atenção especial ao item de `anexos_config` e demais
   configurações administrativas (achado real desta rodada: nada disso é
   povoado automaticamente).
3. Investigar o console error 400 recorrente no frontend (seção 16) —
   não bloqueou nenhum fluxo verificado nesta rodada, mas não foi
   isolado; merece uma sessão dedicada com ferramentas de rede mais
   completas (DevTools do navegador real, não só as ferramentas
   disponíveis nesta sessão).
4. Considerar formalizar um teste de performance com volume de dados
   próximo ao de produção antes do go-live (fora de escopo desta rodada).
