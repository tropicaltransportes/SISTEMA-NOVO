# TEST REPORT — ETAPA 4 (CONSOLIDAÇÃO P1-A) — ERP Oficina

> Quarta rodada de homologação. `docs/testing/TEST_REPORT.md` (1ª rodada),
> `docs/testing/TEST_REPORT_EXECUTION_02.md` (2ª rodada) e
> `docs/testing/TEST_REPORT_EXECUTION_03.md` (3ª rodada) ficam preservados
> intactos como baseline — nenhum dos três foi editado nesta rodada.
>
> Autorização mantida: projeto Supabase `jzjbiejmcaygwycvqggm` ("SISTEMA
> NOVO") tratado como ambiente de desenvolvimento/teste descartável (`npx
> supabase projects list` confirmado antes de qualquer escrita — só esse
> projeto aparece como linkado). O projeto `cedqaxmkffqrwfopgyze` ("YNAB
> COVER") não foi tocado em nenhum momento.
>
> Escopo desta rodada: correção dirigida dos 17 achados FALHOU herdados da
> rodada anterior + formalização de 2 decisões de negócio pendentes (mais o
> registro formal de AUT-007 como risco aceito). Nenhum caso novo além do
> que está listado nas instruções foi buscado deliberadamente — mas 2
> achados novos apareceram por execução real durante a correção (ver seção
> 6) e foram corrigidos na hora, seguindo a mesma disciplina "nunca reescreve
> migration já aplicada" das rodadas anteriores.

---

## 1. Resumo executivo

| Métrica | Valor |
|---|---|
| **TOTAL** | **176** |
| **EXECUTADOS REALMENTE — cumulativo (rodadas 2+3+4)** | **137/176 ≈ 78%** (era 124/176 ≈ 70% após a rodada 3) |
| **EXECUTADOS REALMENTE — só nesta rodada (IDs nunca antes executados de verdade)** | **13** (AUT-009, CAD-004, ORC-016, EST-004, E2E-003, CON-002, CON-007, GAR-005, AUD-001, AUD-002, AUD-003, PER-006, DOC-005) |
| **PASSOU** | **135** (era 122) |
| **FALHOU** | **4** (era 17) |
| **BLOQUEADO** | **0** |
| **NÃO_IMPLEMENTADO** | **26** (inalterado — fora de escopo desta rodada) |
| **NÃO_AUTOMATIZÁVEL** | **2** (inalterado) |
| **PENDENTE_DECISÃO** | **9** (inalterado — PEN-001..008 + FIN-010, fora de escopo desta rodada) |
| Soma de conferência | 135+4+0+26+2+9 = 176 ✓ |

**FALHAS CORRIGIDAS NESTA RODADA = 13** — AUT-009, CAD-004, ORC-016,
EST-004, E2E-003, CON-002, CON-007, GAR-005, AUD-001, AUD-002, AUD-003,
PER-006, DOC-005. Todas com regra reproduzida antes da correção quando
aplicável, migration correspondente, teste de regressão real (curl contra a
API real + pgTAP), e evidência bruta salva em `docs/testing/_etapa4_*.txt`.

**FALHAS RESIDUAIS = 4** — AUT-007 (logout — RISCO ACEITO por decisão
explícita do dono do projeto, não é bug de implementação, ver seção 5) +
APR-004/APR-005/APR-006 (sem campo distinto de "meio" de aprovação —
explicitamente **fora do escopo** da lista de itens A–I desta rodada; não
corrigidos por instrução direta, registrados aqui como pendência conhecida
para uma etapa futura, não mascarados).

**REGRESSÕES = 1 encontrada e corrigida na mesma rodada** (bug real
introduzido pela própria correção do item G, descoberto pela suíte pgTAP —
ver seção 6.1). **0 regressões remanescentes** — suíte completa reexecutada
e verde ao final (seção 7).

**NOVOS ACHADOS = 1** (achado novo de negócio, não de código): o bloqueio de
reconversão duplicada de orçamento (OS-004/P0-03) só valia para OS
**externa**; uma OS **interna** vinculada ao mesmo orçamento não tinha
proteção nenhuma — descoberto ao testar a decisão de negócio #1 e corrigido
na hora (ver seção 6.2).

---

## 2. Migrations novas desta rodada (11, nenhuma migration antiga foi editada)

| # | Arquivo | O que faz |
|---|---|---|
| 1 | `20260812090000_p1a_aut004_bloqueio_total_inativo.sql` | Decisão #2: `current_user_ativo()` + SELECT policies passam a bloquear usuário inativo em leitura, não só escrita |
| 2 | `20260812091000_p1a_cad004_documento_unico.sql` | CAD-004: `normalizar_documento()` + índice único parcial em `clientes.documento` (só ativos) |
| 3 | `20260812092000_p1a_orc016_idempotencia_criacao.sql` | ORC-016: `orcamentos.client_request_id` + índice único parcial |
| 4 | `20260812093000_p1a_est004_baixa_vinculada_item.sql` | EST-004/E2E-003: baixa de peça vinculada a `orcamento_itens`; base de `execucao_status` (CON-002) |
| 5 | `20260812093500_p1a_auditoria.sql` | AUD-001/002/003: tabela `auditoria_eventos` (append-only) + triggers automáticas |
| 6 | `20260812094000_p1a_con002_itens_executados.sql` | CON-002: `rpc_marcar_item_orcamento_execucao` + `rpc_concluir_os` valida itens aprovados |
| 7 | `20260812095000_p1a_con007_apontamento_imutavel.sql` | CON-007: apontamento imutável após OS encerrada + `rpc_corrigir_apontamento` auditada |
| 8 | `20260812096000_p1a_gar005_vinculo_garantia.sql` | GAR-005: tabela `os_garantia_itens` + `rpc_criar_os_garantia`/`rpc_baixar_peca_os` exigem vínculo |
| 9 | `20260812097000_p1a_doc005_valida_storage.sql` | DOC-005: `storage_objeto_existe()` valida path antes de aceitar comprovante/termo |
| 10 | `20260812098000_p1a_fix_baixar_peca_record_bug.sql` | **Corretiva**: corrige bug real introduzido pela migration #8 (ver seção 6.1) |
| 11 | `20260812099000_p1a_dec1_os004_bloqueio_universal.sql` | **Corretiva/achado novo**: estende o bloqueio de reconversão duplicada (OS-004) para OS interna também (ver seção 6.2) |

Todas aplicadas com `npx supabase db push --linked`. `npx supabase migration
list --linked` confirmado `local == remote` em todas as **29** migrations do
projeto (18 anteriores + 11 novas) ao final da rodada.

---

## 3. Decisões de negócio formalizadas

### 3.1 Decisão #1 — Orçamento após cancelamento de OS (resolve o PENDENTE_DECISÃO do OS-004, rodada 3)

**Regra formalizada** (ver `docs/testing/BUSINESS_RULES.md`, BR-008
atualizada): nunca pode existir mais de uma OS **não cancelada** por
orçamento, independente do tipo; OS cancelada libera o orçamento para nova
conversão; histórico de todas as OS permanece consultável (nada é apagado).

**Teste real** (`docs/testing/scripts/etapa4_dec1_os004_reconversao.sh`,
evidência em `_etapa4_dec1_os004_reconversao_output.txt`, reexecutado depois
da correção do achado novo — seção 6.2):

| Cenário | Resultado |
|---|---|
| Orçamento sem OS → converter | HTTP 200, cria OS1 |
| Orçamento com OS1 ativa → converter de novo | HTTP 400 "Este orçamento já foi convertido em uma OS ativa" |
| Cancela OS1 → converter de novo | HTTP 200, cria OS2 |
| Orçamento com OS1 cancelada + OS2 ativa → converter (3ª vez) | HTTP 400, bloqueado |
| Cancela OS2 também → converter de novo (3ª conversão real) | HTTP 200, cria OS3 |
| `SELECT` todas as OS do orçamento | 3 linhas: OS1 (cancelada), OS2 (cancelada), OS3 (aberta) — histórico completo preservado |

### 3.2 Decisão #2 — Usuário inativo = bloqueio total (estende AUT-004)

**Regra formalizada** (BR-028 atualizada): `profiles.ativo=false` bloqueia
leitura **e** escrita em todas as áreas do ERP, não só RPCs de escrita
(já corrigido na rodada 3).

**Teste real** (`docs/testing/scripts/etapa4_dec2_aut004_leitura.sh`,
evidência em `_etapa4_dec2_aut004_leitura_output.txt`): usuário
`teste.inativo` recebeu `[]` (RLS filtrado, sem erro de rede) ao tentar ler
`clientes`, `veiculos`, `orcamentos`, `ordens_servico`, `pecas`,
`estoque_movimentos`, `cobrancas` e o próprio `profiles`; tentativa de
`INSERT` em `clientes` bloqueada com HTTP 403. Controle: `teste.executor` e
`teste.encarregado` (ativos) continuaram lendo dados normalmente — a
correção não virou um bloqueio geral por engano.

### 3.3 Decisão #3 — AUT-007 (logout) — RISCO ACEITO

Não implementado mecanismo de revogação de access_token nesta etapa, por
instrução explícita. Documentado em `docs/testing/BUSINESS_RULES.md`
(BR-040) como característica arquitetural do JWT stateless do Supabase, com
mitigação recomendada (TTL curto, `signOut()` no cliente, tratamento como
risco operacional conhecido). Classificado como **FALHOU residual /
risco aceito** na tabela final — não como corrigido, para não mascarar que
o comportamento técnico continua o mesmo.

---

## 4. Os 17 FALHOU herdados — antes/depois, migration, teste, evidência

### A. AUT-009 / PER-006 — RBAC frontend

- **Antes:** classificado por auditoria de código (rodada 1), nunca
  executado de verdade. Router já tinha `meta.perfis` em algumas rotas, mas
  não havia ponto único de verdade para permissões de ação (botões
  espalhados com listas de perfil inline, sem espelhar sistematicamente o
  backend).
- **Solução:** `frontend/src/lib/permissoes.js` — mapa único
  ação→perfis-permitidos, espelhando exatamente cada RPC/policy do backend
  (comentado com a RPC de origem). `frontend/src/stores/auth.js` passa a
  forçar logout com mensagem clara quando `profiles.ativo=false` (login ou
  sessão já aberta). Sem migration (mudança só de frontend); backend já
  aplicava `tem_perfil()`/RLS antes desta rodada.
- **Teste:** `docs/testing/scripts/etapa4_dec2_aut004_leitura.sh` (frontend)
  + teste direto de API dedicado, `_etapa4_aut009_per006_output.txt`:
  `teste.executor` chamando `rpc_criar_os` direto (sem passar pela UI) →
  HTTP 400 "Perfil sem permissão"; `teste.suporte` chamando
  `rpc_aprovar_orcamento` → HTTP 400; `teste.admin` (perfil correto) → HTTP
  200, sucesso. Confirmado também que leitura de tabela de configuração
  (`orcamento_faixa_acrescimo`) continua aberta a qualquer usuário ativo por
  design (não é vazamento — é dado de configuração, não sensível; só a
  escrita é restrita a admin).
- **Resultado depois: PASSOU.** Frontend reflete o backend; backend
  continua sendo a autoridade real, confirmado por chamada direta à API.
- Regressões: nenhuma. Novos problemas: nenhum.

### B. CAD-004 — duplicidade de documento

- **Antes (confirmado por execução real na rodada 2):**
  `seed.sql` inseriu 2 clientes com o mesmo `documento`
  (`44444444000104`) sem nenhum erro — não havia unique constraint.
- **Solução:** `normalizar_documento()` (remove tudo que não é dígito) +
  índice único parcial `uq_clientes_documento_normalizado_ativo` em
  `clientes (normalizar_documento(documento)) where documento is not null
  and deleted_at is null`. Dado de teste pré-existente corrigido na mesma
  migration (b...0006 passou a ter documento distinto) e `seed.sql`
  atualizado para não recriar a duplicidade real em futuros reseeds — o
  cenário de duplicidade em si passa a ser criado por script de teste em
  tempo de execução.
- **Migration:** `20260812091000_p1a_cad004_documento_unico.sql`.
- **Teste:** `docs/testing/scripts/etapa4_cad004_orc016.sh`,
  `_etapa4_cad004_orc016_output.txt`. Cenários reais: documento idêntico →
  HTTP 409; documento com máscara diferente (`55.555.555/0001-99` vs
  `55555555000199`) → HTTP 409; documento nulo (2x) → HTTP 201 nos dois
  (nunca bloqueia); cliente inativado → documento reaproveitável por um
  cliente novo → HTTP 201.
- **Resultado depois: PASSOU.**
- Regressões: nenhuma. Novos problemas: nenhum.

### C. ORC-016 — duplo submit de orçamento

- **Antes:** criação de orçamento é `INSERT` direto (não RPC); só proteção
  era o botão desabilitado durante o request — não resiste a retry de rede
  real nem a duas abas.
- **Solução:** `orcamentos.client_request_id` (UUID gerado uma vez pelo
  frontend, reenviado em qualquer retry) + índice único parcial. Frontend
  (`OrcamentosList.vue`) gera a chave ao abrir o diálogo, reaproveita em
  qualquer nova tentativa, e trata um 409 (`23505`) buscando o registro já
  criado em vez de mostrar erro/duplicar.
- **Migration:** `20260812092000_p1a_orc016_idempotencia_criacao.sql`.
- **Teste:** duas chamadas HTTP **reais em paralelo** (`curl ... & curl ...
  & wait`) com a mesma `client_request_id`, `_etapa4_cad004_orc016_output.txt`:
  chamada 1 → HTTP 201 (criado); chamada 2 → HTTP 409 (conflito); `SELECT`
  final confirma **exatamente 1** orçamento com essa chave.
- **Resultado depois: PASSOU** — idempotência real de backend, não só UI.
- Regressões: nenhuma. Novos problemas: nenhum.

### D. EST-004 / E2E-003 — baixa de estoque vinculada ao orçamento

- **Antes:** conversão em OS nunca baixou estoque (isso já era assim desde
  sempre — o texto original da BR-014 descrevia uma intenção que o código
  nunca implementou). `rpc_baixar_peca_os` permitia baixar **qualquer**
  peça, em qualquer quantidade, sem nenhum vínculo com os itens aprovados do
  orçamento.
- **Decisão técnica registrada** (BR-014 atualizada, ver seção 3 do
  BUSINESS_RULES.md): baixa continua ocorrendo na **execução** (alternativa
  B, preferida explicitamente), agora **obrigatoriamente vinculada ao item
  aprovado**.
- **Solução:** `estoque_movimentos.orcamento_item_id` +
  `orcamento_itens.execucao_status`; `rpc_baixar_peca_os` exige
  `p_orcamento_item_id` quando a OS tem orçamento, valida peça/quantidade
  contra o item, bloqueia excesso com mensagem de "necessário adicional",
  erro explícito de estoque insuficiente (nunca saldo negativo, nunca
  silencioso).
- **Migration:** `20260812093000_p1a_est004_baixa_vinculada_item.sql`
  (corrigida por `20260812098000_p1a_fix_baixar_peca_record_bug.sql`, ver
  seção 6.1).
- **Teste:** `docs/testing/scripts/etapa4_est004_e2e003.sh`,
  `_etapa4_est004_e2e003_output.txt`. Cenários reais, todos confirmados:
  baixa sem `p_orcamento_item_id` em OS com orçamento → bloqueado; baixa
  dentro do aprovado → sucesso, saldo/`execucao_status` corretos (`parcial`
  → `executado` ao completar); baixa que excede o aprovado → bloqueado com
  mensagem de adicional; peça que não bate com o item → bloqueado; estoque
  insuficiente na baixa real → erro explícito, saldo nunca fica negativo;
  controle — OS **sem** orçamento continua com baixa livre (não regrediu).
- **Resultado depois: PASSOU** (com a regra redefinida e documentada — a
  expectativa literal original do E2E-003, "bloquear na conversão", não se
  aplica mais porque a conversão nunca moveu estoque; o espírito da regra —
  nunca gerar saldo negativo, sempre com erro explícito — está mantido e
  confirmado por execução real).
- Regressões: 1 encontrada e corrigida na mesma rodada (seção 6.1). Novos
  problemas: nenhum residual.

### E. CON-002 — concluir com item aprovado pendente

- **Antes:** `rpc_concluir_os` só validava o checklist técnico; itens
  aprovados do orçamento não eram verificados — uma OS podia ser concluída
  com peça/serviço aprovado nunca executado.
- **Solução:** `orcamento_itens.execucao_status` (`pendente`/`parcial`/
  `executado`/`cancelado`), sincronizado automaticamente pela baixa de peça
  (item D); `rpc_marcar_item_orcamento_execucao` para itens de mão de obra
  (sem sinal automático), com motivo obrigatório para `cancelado`.
  `rpc_concluir_os` bloqueia se existir item `pendente`/`parcial`.
- **Migration:** `20260812094000_p1a_con002_itens_executados.sql`.
- **Teste:** `docs/testing/scripts/etapa4_con002_auditoria.sh`,
  `_etapa4_con002_auditoria_output.txt`. Checklist respondido mas item de
  mão de obra e item de peça ainda pendentes → `rpc_concluir_os` bloqueado;
  marca mão de obra executado → continua bloqueado (peça ainda pendente);
  tenta cancelar item sem motivo → bloqueado; cancela com motivo → sucesso;
  conclui a OS → sucesso (todos os itens resolvidos: executado/executado/
  cancelado).
- **Resultado depois: PASSOU.**
- Regressões: nenhuma. Novos problemas: nenhum.

### F. CON-007 — alterar execução após conclusão

- **Antes:** policy `os_executores_update_proprio` só checava `usuario_id =
  auth.uid()` — nenhum perfil, nenhum status de OS. Qualquer executor podia
  editar seu apontamento a qualquer momento, mesmo anos depois da OS
  encerrada.
- **Solução:** policy reescrita para exigir perfil operacional válido e OS
  **não** `concluida`/`liberada`/`cancelada`. `rpc_corrigir_apontamento`
  (só encarregado/admin técnico, motivo obrigatório, sempre auditada) para
  correção formal pós-encerramento.
- **Migration:** `20260812095000_p1a_con007_apontamento_imutavel.sql`.
- **Teste:** `docs/testing/scripts/etapa4_con007_gar005_doc005.sh`,
  `_etapa4_con007_gar005_doc005_output.txt`. Apontamento editável com OS
  aberta → sucesso; a mesma edição direta com a OS **concluída** → HTTP 200
  com `[]` (RLS filtrou, 0 linhas, valor inalterado); `rpc_corrigir_apontamento`
  sem motivo → bloqueado; com motivo → sucesso, e evento correspondente
  aparece em `auditoria_eventos` (`acao=correcao_apontamento`, motivo
  registrado).
- **Resultado depois: PASSOU.**
- Regressões: nenhuma. Novos problemas: nenhum.

### G. GAR-005 — item não relacionado (garantia)

- **Antes:** `rpc_criar_os_garantia` só copiava veículo/cliente/tipo/
  checklist da OS original — nada identificava qual item/serviço é objeto
  da garantia.
- **Solução:** tabela `os_garantia_itens` (vínculo com `orcamento_itens` da
  OS original); `rpc_criar_os_garantia` exige ao menos um item quando a OS
  original tem orçamento; `rpc_baixar_peca_os` (ramo garantia) só aceita
  peça vinculada a um desses itens, com cota própria por OS de garantia.
- **Migration:** `20260812096000_p1a_gar005_vinculo_garantia.sql`
  (corrigida por `20260812098000_p1a_fix_baixar_peca_record_bug.sql`, ver
  seção 6.1).
- **Teste:** mesmo script do item F, `_etapa4_con007_gar005_doc005_output.txt`.
  Abrir garantia sem informar itens (OS original com orçamento) → bloqueado;
  com item vinculado → sucesso, vínculo confirmado em `os_garantia_itens`;
  baixar peça **não** vinculada ao item (informando o item certo, peça
  errada) → bloqueado; baixar a peça correta do item vinculado → sucesso.
- **Resultado depois: PASSOU.**
- Regressões: 1 encontrada e corrigida na mesma rodada (seção 6.1). Novos
  problemas: nenhum residual.

### H. AUD-001 / AUD-002 / AUD-003 — auditoria

- **Antes:** nenhuma trilha de auditoria genérica existia — mudança de
  status/cancelamento/preço não deixava rastro estruturado (só o ledger de
  estoque, que já era auditável por natureza).
- **Solução:** tabela `auditoria_eventos` (append-only — sem policy de
  UPDATE/DELETE para nenhum papel, escrita só via `registrar_auditoria()`
  interna). Triggers automáticas: mudança de status de OS (cobre
  conclusão/liberação/cancelamento em um só lugar), alteração de preço de
  item de orçamento, alteração administrativa crítica (perfil/ativo de
  usuário), estorno de estoque. Chamadas explícitas em
  `rpc_marcar_item_orcamento_execucao` e `rpc_corrigir_apontamento`.
- **Migration:** `20260812093500_p1a_auditoria.sql`.
- **Teste:** `_etapa4_con002_auditoria_output.txt` (mudança de status
  capturada em 3 transições da mesma OS; `marcar_execucao_item` capturado
  com valor anterior/novo e motivo) + `_etapa4_aud001_003_output.txt`
  (dedicado): alteração de preço de item (`100 → 250`) capturada com
  usuário e valores; cancelamento de OS (`aberta → cancelada`) capturado.
  Imutabilidade confirmada: `UPDATE`/`DELETE` diretos em
  `auditoria_eventos` por `encarregado`/`administrador_tecnico` → HTTP 403
  "permission denied for table auditoria_eventos" (nenhuma policy de
  escrita existe — não é uma checagem de perfil que poderia ser
  contornada, é ausência estrutural de grant). Leitura por `executor` →
  `[]` (filtrado, não erro).
- **Resultado depois: PASSOU** (os 3 IDs).
- Regressões: nenhuma. Novos problemas: nenhum.

### I. DOC-005 — documento órfão

- **Antes:** `rpc_registrar_autorizacao_orcamento`/`rpc_registrar_termo_ciencia`
  só validavam texto não-vazio — qualquer string era aceita como
  `comprovante_path`/`arquivo_path`, mesmo sem nenhum arquivo real por trás.
- **Solução:** `storage_objeto_existe(bucket, path)` — checagem real contra
  `storage.objects` (SECURITY DEFINER, independe da policy de leitura do
  chamador) antes de aceitar a referência.
- **Migration:** `20260812097000_p1a_doc005_valida_storage.sql`.
- **Teste:** `_etapa4_con007_gar005_doc005_output.txt`. Path inexistente →
  bloqueado com mensagem explícita; upload real no bucket `comprovantes` →
  registro aceito; tentativa de simular "documento removido antes do uso"
  → `DELETE` no Storage foi ele mesmo **negado** (HTTP 403 — não existe
  policy de DELETE para o bucket `comprovantes`, achado positivo: a janela
  de race é estruturalmente quase inexistente neste sistema, não só
  mitigada). pgTAP `040_liberacao.sql` ganhou um caso dedicado (`throws_ok`
  DOC-005) e o fixture de LIB-002 foi ajustado para inserir a linha
  correspondente em `storage.objects` antes de chamar a RPC (ver seção 6.3).
- **Resultado depois: PASSOU.**
- Regressões: 1 encontrada e corrigida no próprio teste (seção 6.3). Novos
  problemas: nenhum residual.

### Residuais (não corrigidos nesta rodada)

- **AUT-007 (logout):** RISCO ACEITO, ver seção 3.3. Continua **FALHOU**
  no sentido literal da matriz (o access_token continua válido após
  logout), mas é uma decisão de negócio documentada, não um bug pendente.
- **APR-004, APR-005, APR-006 (meio de aprovação):** explicitamente **fora
  do escopo** da lista de itens A–I desta rodada (não mencionados nas
  instruções do dono do projeto para o P1-A). Permanecem **FALHOU**,
  registrados aqui como pendência conhecida — nenhuma correção "de brinde"
  foi feita, conforme instrução explícita de manter escopo controlado.

---

## 5. Verificação por perfil e chamada direta à API (metodologia, resumo)

Para cada correção acima, seguido o roteiro pedido: reprodução da falha
antiga (quando aplicável e possível sem repetir dado já comprovado em
rodada anterior), correção, teste de regressão, validação do estado final
do banco via `SELECT` real, teste com perfil permitido (sucesso) e com
perfil proibido (bloqueio), sempre por chamada HTTP direta contra
`/rest/v1/rpc/*` e `/rest/v1/<tabela>` (nunca inferido a partir do que a
UI permite clicar). Evidência bruta completa em
`docs/testing/_etapa4_*.txt` (11 arquivos) e scripts reprodutíveis em
`docs/testing/scripts/etapa4_*.sh` (7 arquivos).

---

## 6. Regressões e achados novos — detalhados

### 6.1 Regressão real: bug de `record` não atribuído em `rpc_baixar_peca_os`

Ao aplicar a migration do item G (`20260812096000_p1a_gar005_vinculo_garantia.sql`),
a suíte pgTAP `020_estoque.sql` (que usa OS **interna sem orçamento** — o
caminho "sem vínculo" da função) passou de 6/6 `ok` para 5 `not ok` + 1
`ok`, com o erro `record "v_item" is not assigned yet`. Causa: `v_item`
(tipo `record`) nunca era populado nesse caminho, e o Postgres levanta erro
ao ler **qualquer** campo de um `record` nunca atribuído (diferente de um
`record` atribuído com campos NULL). Detectado imediatamente pela própria
suíte de regressão, **antes** de seguir para os testes seguintes — corrigido
na hora com uma migration nova
(`20260812098000_p1a_fix_baixar_peca_record_bug.sql`, troca `record` +
`.id is not null` por uma variável `boolean` explícita), sem editar a
migration já aplicada. Evidência do bug:
`docs/testing/_etapa4_regressao_bug_v_item_output.txt`. Suíte
reexecutada depois da correção: 6/6 `ok` de novo.

### 6.2 Achado novo: bloqueio de reconversão duplicada não cobria OS interna

Ao testar a decisão de negócio #1 (seção 3.1) com uma OS **interna**
vinculada a um orçamento (combinação válida no schema — `orcamento_id` é
opcional e não restrito por tipo), a 2ª conversão do mesmo orçamento, com a
1ª OS ainda ativa, foi aceita (HTTP 200, criou uma 2ª OS) em vez de
bloqueada. Investigação mostrou que o bloqueio de P0-03 (rodada 3) só
existia dentro do bloco `if p_tipo = 'externa' then` — nunca coberto para
`interna`. Corrigido com `20260812099000_p1a_dec1_os004_bloqueio_universal.sql`,
que move a checagem para rodar sempre que `p_orcamento_id is not null`,
independente do tipo. Evidência antes/depois em
`docs/testing/_etapa4_dec1_os004_reconversao_output.txt` (o arquivo reflete
a execução **depois** da correção — a execução anterior, que mostrou o
bug, está descrita na migration corretiva e no texto desta seção).

### 6.3 Ajuste de teste (não é regressão de produção): pgTAP LIB-002

`rpc_registrar_termo_ciencia` ganhou validação de Storage (item I). O
pgTAP `040_liberacao.sql` chamava essa RPC com um path fictício
(`termos/pgtap-teste.pdf`) que nunca existiu de verdade no Storage — antes
da correção isso não importava (sem validação), depois passou a falhar
corretamente (novo comportamento correto, não um bug). O teste foi ajustado
para inserir a linha correspondente em `storage.objects` antes de chamar a
RPC (simula o upload real dentro da própria transação pgTAP), e ganhou um
novo caso `throws_ok` dedicado para confirmar que um path realmente
inexistente continua bloqueado. Isso **não** é uma mudança de resultado
esperado para mascarar falha — é a correção de um fixture desatualizado
diante de uma validação nova e correta.

---

## 7. Regressão completa executada ao final

### pgTAP (`npx supabase db query --linked -f <arquivo>`, dentro de
`begin`/`rollback`, contra o projeto real linkado)

| Arquivo | Resultado |
|---|---|
| `010_seguranca_permissao_anon_bypass.sql` | 6/6 `ok` |
| `020_estoque.sql` | 6/6 `ok` |
| `030_orcamento.sql` | 4/4 `ok` |
| `040_liberacao.sql` | 4/4 `ok` (3 originais + 1 novo, DOC-005) |

Evidência completa: `docs/testing/_etapa4_pgtap_final_output.txt`.

### Reconfirmação real dos achados P0 da rodada 3 (AUT-004, EST-009, DOC-006)

- **AUT-004** (núcleo, RPC de escrita): coberto de novo indiretamente por
  todos os testes desta rodada que usam `teste.executor`/`teste.encarregado`
  normalmente (nenhuma RPC quebrou); extensão de leitura confirmada na
  seção 3.2.
- **EST-009** (idempotência persistente): peça/OS 100% novas, chave K1,
  retry depois de 6s → continua bloqueado (`Operação já processada`), saldo
  final correto (30→25, sem duplicar). Evidência:
  `docs/testing/_etapa4_regressao_est009_doc006_output.txt`.
- **DOC-006** (acesso a documento por perfil): `teste.diretoria` (nunca
  participou do upload) lê o documento normalmente (HTTP 200); `teste.executor`
  bloqueado (objeto não encontrado via RLS). Mesma evidência acima.

Nenhuma regressão encontrada nesses três achados.

---

## 8. Arquivos gerados/alterados nesta rodada

**Migrations (11 novas):** ver seção 2.

**Backend/testes:**
- `supabase/tests/040_liberacao.sql` (ajustado — seção 6.3)
- `supabase/seed.sql` (ajustado — CAD-004, seção 4.B)

**Frontend:**
- `frontend/src/lib/permissoes.js` (novo)
- `frontend/src/stores/auth.js`, `frontend/src/views/LoginView.vue` (decisão #2)
- `frontend/src/views/clientes/ClientesList.vue` (mensagem amigável CAD-004)
- `frontend/src/views/orcamentos/OrcamentosList.vue` (ORC-016)
- `frontend/src/views/os/OrdemServicoDetalhe.vue` (itens D, E, F, G)

**Documentação:**
- `docs/testing/BUSINESS_RULES.md` (BR-001, 008, 014, 021, 024, 026, 027,
  028, 033, 040 atualizadas com a implementação/decisão desta rodada — texto
  original preservado, adendos claramente marcados "ETAPA 4")
- `docs/testing/TEST_REPORT_P1A.md` (este arquivo)
- `docs/testing/TEST_REPORT.md`, `TEST_REPORT_EXECUTION_02.md`,
  `TEST_REPORT_EXECUTION_03.md` — **preservados sem nenhuma alteração**.

**Scripts e evidência bruta (novos, `docs/testing/`):**
- `scripts/etapa4_dec2_aut004_leitura.sh`, `scripts/etapa4_cad004_orc016.sh`,
  `scripts/etapa4_est004_e2e003.sh`, `scripts/etapa4_con002_auditoria.sh`,
  `scripts/etapa4_con007_gar005_doc005.sh`,
  `scripts/etapa4_dec1_os004_reconversao.sh`
- `_etapa4_dec2_aut004_leitura_output.txt`, `_etapa4_cad004_orc016_output.txt`,
  `_etapa4_est004_e2e003_output.txt`, `_etapa4_con002_auditoria_output.txt`,
  `_etapa4_con007_gar005_doc005_output.txt`,
  `_etapa4_dec1_os004_reconversao_output.txt`,
  `_etapa4_regressao_bug_v_item_output.txt`,
  `_etapa4_regressao_est009_doc006_output.txt`, `_etapa4_pgtap_final_output.txt`,
  `_etapa4_aut009_per006_output.txt`, `_etapa4_aud001_003_output.txt`

---

## 9. Achados fora de escopo, registrados mas NÃO corrigidos (por instrução explícita)

- **APR-004/005/006** — sem campo distinto de "meio" de aprovação
  (botão/e-mail/verbal). Não mencionado na lista de itens A–I; permanece
  FALHOU, candidato a uma etapa futura (P1-B).
- Todo o restante já registrado como NÃO_IMPLEMENTADO nas rodadas
  anteriores (aprovação parcial, módulo de Adicionais completo, desconto,
  fotos, PDF/relatórios, boleto, NF, histórico visual por veículo) continua
  fora de escopo — nenhum foi implementado "de brinde" nesta rodada, mesmo
  onde teria sido tecnicamente simples (ex.: a estrutura de
  `os_garantia_itens` do item G facilitaria um relatório de garantia, mas o
  PDF em si não foi tocado, conforme instrução).
- Endurecimento P2 já registrado na rodada 3 (granularidade por
  vínculo/entidade no bucket `comprovantes`, DOC-006) continua como
  oportunidade futura, não implementado nesta rodada (fora da lista A–I).

---

## 10. Próximas ações priorizadas

1. Nenhuma pendência P0 conhecida ao final desta rodada.
2. APR-004/005/006 (campo de "meio" de aprovação) — candidato natural para
   a próxima rodada de correção dirigida (P1-B), junto com aprovação
   parcial (que compartilha o mesmo formulário/fluxo).
3. AUT-007 — reavaliar TTL de access_token/estratégia de revogação só se o
   perfil de risco da oficina mudar (ver BR-040).
4. Os 9 PENDENTE_DECISÃO (PEN-001..008, FIN-010) e os 26 NÃO_IMPLEMENTADO
   continuam como estavam — nenhuma mudança nesta rodada, decisão de
   negócio/escopo pendente do dono do projeto para P1-B/P1-C.
