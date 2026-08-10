# TEST REPORT — ERP Oficina

> Primeira auditoria de qualidade, executada pelo Claude Code conforme
> `CLAUDE.md` e `docs/testing/CLAUDE_AUDIT_PROMPT.md`. Nenhum código de
> produção foi corrigido nesta passagem — bugs reais foram deixados
> falhando, conforme exigido pela regra fundamental do prompt de auditoria.

## 1. Resumo executivo

- **Data/hora:** 2026-08-10 (UTC, ver timestamps nas evidências abaixo)
- **Branch/commit:** repositório local sem `git init` (não é repositório Git — ver observação em "Ambiente")
- **Ambiente:** único projeto Supabase configurado, real/de desenvolvimento (`jzjbiejmcaygwycvqggm`) — **não há banco exclusivo de teste**
- **Banco utilizado:** nenhuma escrita real foi feita neste banco durante a auditoria; as únicas chamadas ao vivo foram comprovadamente não-destrutivas (papel `anon`, sem sessão, IDs inexistentes) — ver seção 9 e seção 10
- **Total de casos da matriz:** 176
- **Casos com funcionalidade implementada no código (mesmo que com falhas):** 138
- **Casos automatizados (executados ao vivo OU com teste pronto para execução nesta auditoria):** 37 (6 executados ao vivo contra o projeto real + 22 avaliados por leitura exaustiva de código, incluída aqui como "achado determinístico" e não como execução; 9 têm pgTAP pronto em `supabase/tests/` aguardando ambiente seguro para rodar)
- **PASSOU:** 5
- **FALHOU:** 22
- **BLOQUEADO:** 108
- **NÃO_IMPLEMENTADO:** 29
- **NÃO_AUTOMATIZÁVEL:** 3
- **PENDENTE_DECISÃO:** 9
- **Cobertura da matriz (casos com veredito atribuído):** 176/176 = 100%
- **Cobertura automatizada real (execução ao vivo comprovada):** 6/176 ≈ 3%

### Por que a cobertura de execução é tão baixa — leia antes dos números

Este projeto **não tem banco de dados exclusivo de teste** e **não há Docker
disponível** neste ambiente de execução (`docker: command not found`), então
não foi possível rodar `supabase start` (a via de teste local que o próprio
`docs/plano-arquitetura.md` descreve como padrão do projeto). O único projeto
Supabase configurado é o projeto real de desenvolvimento, que já contém dados
de cliente reais misturados com dados de teste (ver `supabase/tests/README.md`
para o detalhamento). Por instrução explícita do `CLAUDE.md` (seção 5): *"Se
não for possível confirmar que o banco não é de produção, interrompa os
testes destrutivos e registre o bloqueio."*

Por isso, a esmagadora maioria dos 176 casos está classificada como
`BLOQUEADO` — não porque o código pareça errado, mas porque executar o teste
de verdade exigiria uma escrita real (criar cliente, aprovar orçamento, baixar
estoque, liberar OS...) no único banco existente, com dados reais misturados.
Para cada um desses casos, deixei pronta a infraestrutura de teste (pgTAP em
`supabase/tests/`, ver README ali) para ser executada assim que houver um
ambiente seguro.

Dentro dessa limitação, **duas coisas foram feitas de verdade nesta
auditoria**, e ambas produziram evidência real, não hipotética:

1. **Um lote de checagens 100% não-destrutivas foi executado ao vivo contra o
   projeto real**, sem nenhuma credencial de usuário (papel `anon`, chamadas
   com UUID falso que nunca alcançam uma gravação). Isso revelou o achado
   crítico #1 abaixo.
2. **Leitura completa e exaustiva de 100% do código de backend** (2.186
   linhas em 14 migrations SQL — toda RPC, toda policy RLS, toda constraint)
   **e do frontend relevante** (router, store de auth, todas as 17 telas em
   `views/`) — o suficiente para afirmar com certeza, sem precisar executar,
   quando uma funcionalidade **não existe no código** (`NÃO_IMPLEMENTADO`) ou
   quando o código **definitivamente não cobre** o que a regra pede (`FALHOU`
   por leitura determinística — sempre com citação de arquivo/linha).

---

## 2. Achados críticos (leia isto primeiro)

### 🔴 Achado crítico #1 — Toda checagem de permissão do backend pode ser ignorada por um chamador sem login nenhum

**Confirmado por execução real, não-destrutiva, contra o projeto de produção.**

Praticamente toda RPC de escrita do sistema começa com o padrão:

```sql
if current_perfil() not in ('encarregado', 'administrador_tecnico') then
  raise exception 'Perfil sem permissão para ...';
end if;
```

`current_perfil()` (`supabase/migrations/20260806120000_profiles.sql:23-31`) é:

```sql
select perfil from profiles where id = auth.uid()
```

Para um chamador **sem sessão nenhuma** (papel `anon` do PostgREST — ou seja,
qualquer pessoa com a `anon key`, que é pública por design e já vem embutida
em qualquer build do frontend), `auth.uid()` é `NULL`, então
`current_perfil()` retorna `NULL`. E `NULL NOT IN (lista)` avalia para
`NULL` em SQL — que o `IF` do plpgsql trata como **falso**. Ou seja: **a
exceção nunca dispara, e a função continua executando como se a permissão
tivesse passado.**

Testei isso ao vivo, sem usar nenhuma credencial, chamando 21 RPCs diferentes
com UUIDs inexistentes (`00000000-0000-0000-0000-000000000000`) — escolhidos
para nunca alcançar uma gravação real (a própria RPC sempre encontra "não
encontrado(a)" ou erro de validação antes de qualquer `INSERT`/`UPDATE`).
**Todas as 21 RPCs testadas pularam o check de permissão**: a resposta foi
sempre a mensagem de negócio ("Orçamento não encontrado", "Ordem de serviço
não encontrada" etc.) em vez de "Perfil sem permissão...". Script completo e
reprodutível em [`docs/testing/scripts/safe_anon_rpc_checks.sh`](scripts/safe_anon_rpc_checks.sh);
saída bruta das duas baterias em `docs/testing/_safe_checks_output.txt` e
`docs/testing/_safe_checks_output2.txt`.

RPCs confirmadas vulneráveis (lista completa testada): `rpc_criar_os`,
`rpc_enviar_orcamento`, `rpc_aprovar_orcamento`, `rpc_rejeitar_orcamento`,
`rpc_registrar_autorizacao_orcamento`, `rpc_criar_versao_orcamento`,
`rpc_registrar_acrescimo`, `rpc_transicionar_os`, `rpc_concluir_os`,
`rpc_liberar_os`, `rpc_criar_os_garantia`, `rpc_definir_checklist_os`,
`rpc_baixar_peca_os`, `rpc_criar_cobranca`, `rpc_parcelar_cobranca`,
`rpc_registrar_recebimento`, `rpc_registrar_termo_ciencia`,
`rpc_cancelar_cobranca`, `rpc_confirmar_nf_entrada`, `rpc_estornar_nf_entrada`,
`rpc_criar_venda_avulsa`.

**Por que isso não é só um problema teórico:** todas essas funções são
`security definer` — dentro delas, RLS não se aplica mais (rodam com
privilégio do dono da função). O único portão de segurança para um chamador
anônimo é exatamente esse `if current_perfil() not in (...)` que está
quebrado. Como as próprias RPCs validam existência de IDs (então não dá pra
"criar dado do nada" com um UUID aleatório), **o risco concreto é: qualquer
pessoa que descubra um UUID real** (de um orçamento, OS, peça, cobrança — nada
disso é segredo, aparece em URLs, listas, relatórios) **pode aprovar um
orçamento, liberar uma OS, registrar um "recebimento" financeiro falso,
cancelar uma cobrança, dar baixa em estoque etc., sem fazer login — só com a
`anon key` pública.**

Não testei com um UUID real (isso executaria a mutação de verdade, proibido
pela seção 5 do CLAUDE.md) — a prova acima (mensagem de "não encontrado" em
vez de "sem permissão") já é suficiente e é 100% conclusiva sobre o
comportamento do `IF`.

**Correção sugerida (não aplicada nesta auditoria):** trocar todo
`current_perfil() not in (lista)` por
`coalesce(current_perfil()::text, '') not in (lista)` (ou
`current_perfil() is null or current_perfil() not in (lista)`) em **toda**
RPC do projeto — são pelo menos as 21 listadas acima. Teste de regressão já
pronto (hoje deve falhar; depois da correção deve passar) em
[`supabase/tests/010_seguranca_permissao_anon_bypass.sql`](../../supabase/tests/010_seguranca_permissao_anon_bypass.sql).

Mapeado na matriz como **AUT-005 = FALHOU** (é o caso que descreve
exatamente esse cenário — "chamar endpoint protegido sem credencial").
Os demais casos de permissão da matriz (APR-007, EXE-008/009, LIB-004,
PER-001 a 005 etc.) pressupõem um **usuário autenticado com perfil errado**
(não um chamador sem sessão) — esse é um cenário diferente, que a matemática
do `NOT IN` trata corretamente (`'executor' NOT IN (...)` é um booleano
concreto, não `NULL`), mas que **não foi executado** nesta auditoria por
falta de credenciais de teste por perfil — ficam `BLOQUEADO`, não `PASSOU`.

### 🟠 Achado crítico #2 — Bucket de Storage `comprovantes` é legível por qualquer usuário autenticado, sem checar dono/vínculo

`supabase/migrations/20260806130400_storage_comprovantes.sql:8-11`:
```sql
create policy "comprovantes_select_autenticado" on storage.objects
  for select to authenticated
  using (bucket_id = 'comprovantes');
```
Não há filtro por cliente, OS ou usuário — qualquer perfil autenticado
(inclusive `executor`, que segundo `docs/plano-arquitetura.md` não deveria
ter acesso ao módulo financeiro) pode ler o comprovante de autorização de
orçamento ou o Termo de Ciência de Débito de **qualquer** cliente, bastando
adivinhar/enumerar o nome do arquivo. Mapeado como **DOC-006 = FALHOU**.

### 🟡 Achado crítico #3 — `suporte_administrativo` não consegue liberar OS, apesar de BR-022 permitir

As três versões de `rpc_liberar_os` (a mais recente em
`supabase/migrations/20260806150000_garantia.sql:57-103`) só permitem
`current_perfil() in ('encarregado', 'administrador_tecnico')`.
`docs/plano-arquitetura.md` (matriz RBAC, seção 4) e BR-022 ("liberação pode
ser feita pelo administrativo ou encarregado") esperam que
`suporte_administrativo` também libere. Mapeado como **LIB-006 = FALHOU**.

### Outros achados estruturais relevantes (detalhados na tabela da seção 7)

- **Módulo "Adicionais" inteiro não existe** (ADC-001 a ADC-008) — nenhuma
  tabela, RPC ou lógica de frontend para itens adicionais pendentes de
  aprovação durante a execução da OS. O único vestígio é um rótulo de botão
  ("Enviar p/ Aprovação (orçamento adicional)") que apenas transiciona o
  status da OS, sem capturar item/valor/aprovação nenhum
  (`frontend/src/views/os/OrdemServicoDetalhe.vue:110-122`).
- **Aprovação parcial de orçamento não existe** (BR-006, DEFINIDA) — só há
  aprovação/rejeição do orçamento inteiro. Afeta APR-002 e OS-002.
- **Mecanismo de desconto não existe** — só existe "acréscimo" pós-aprovação
  (`orcamento_acrescimos`); não há campo/RPC de desconto em nenhum nível.
  Afeta ORC-007, ORC-008, FIN-003.
- **Não existe trilha de auditoria genérica** (BR-027, DEFINIDA) — mudanças
  de status de OS (`rpc_transicionar_os`) e cancelamentos não gravam
  quem/quando em lugar nenhum (`ordens_servico` não tem coluna
  `atualizado_por`/`atualizado_em`). Afeta AUD-001, AUD-002, AUD-003.
- **`profiles.ativo` nunca é lido em nenhuma policy RLS, RPC ou guarda de
  rota** — inativar um usuário não bloqueia login nem chamadas de API.
  Confirmado por grep exaustivo em todo o repositório. Afeta AUT-004.
- **Sem constraint de unicidade em `clientes.documento`** — CAD-004.
- **`rpc_criar_os` não impede reconverter o mesmo orçamento aprovado em uma
  segunda OS** — nenhuma coluna/flag marca o orçamento como "já usado" (achado
  também confirmado numa sessão anterior de testes manuais, registrado na
  memória do projeto). Afeta OS-004.
- **Baixa de estoque não acontece na conversão orçamento→OS** (como BR-014
  sugere), e sim manualmente depois, item a item, sem nenhuma validação de
  que a peça baixada corresponde a um item do orçamento aprovado. Afeta
  EST-004.
- **Nenhuma tela/rotina existe para "número de casos" de fotos antes/depois
  da OS, geração de PDF de orçamento, relatório de encerramento** —
  `frontend/package.json` não tem nenhuma dependência de geração de PDF.
  Afeta EXE-005/006/007, ORC-013, CON-005/006, DOC-001/002/003, GAR-007.

---

## 3. Falhas críticas

| ID | Módulo | Esperado | Encontrado | Evidência | Risco | Arquivo/endpoint |
|---|---|---|---|---|---|---|
| AUT-005 | Autenticação | 401/403 sem credencial | RPC executa lógica de negócio sem sessão (checks de perfil pulados) | Execução real, `docs/testing/scripts/safe_anon_rpc_checks.sh` | Escrita/mutação não autenticada em praticamente todo o sistema | Todas as RPCs `security definer` (ver Achado crítico #1) |
| OS-004 | Ordem de Serviço | Segunda OS não é criada a partir do mesmo orçamento | Nada impede reconverter | Leitura de `rpc_criar_os`, sem coluna/flag de "já convertido" | OS duplicada, cobrança duplicada | `supabase/migrations/20260806130200_ordens_servico.sql:182-243` |
| OS-010 | Ordem de Serviço | Cancelamento com estoque exige tratamento/estorno | `rpc_transicionar_os` cancela sem tocar em `estoque_movimentos` | Leitura de `rpc_transicionar_os` | Estoque comprometido (baixado) sem OS ativa correspondente | `supabase/migrations/20260806130200_ordens_servico.sql:275-315` |
| EST-004 | Estoque | Baixa ocorre na conversão orçamento→OS | Baixa só ocorre depois, manual, item a item, sem vínculo com itens do orçamento | Leitura de `rpc_criar_os` (não chama nenhuma RPC de estoque) | Divergência entre o que foi orçado e o que foi baixado; peça errada pode ser baixada | `supabase/migrations/20260806130200_ordens_servico.sql:182-243` |
| EST-009 | Estoque | Dupla baixa da mesma origem não duplica | `rpc_baixar_peca_os`/`rpc_registrar_saida_estoque` não checam idempotência por `origem_id` | Leitura completa de ambas as funções | Duplo clique reduz estoque em dobro | `supabase/migrations/20260806120200_estoque.sql:294-333`, `20260806130200_ordens_servico.sql:392-417` |
| AUD-001 | Auditoria | Alteração de preço registra antes/depois/usuário/data | Só há trilha para preço de item de orçamento (via versionamento); peças/cadastros não têm log algum | Leitura completa do schema — nenhuma tabela de auditoria genérica existe | Alteração de preço de peça (`PecasList.vue`) sem rastro | `supabase/migrations/20260806120200_estoque.sql` (tabela `pecas`, sem histórico) |

## 4. Falhas altas

| ID | Módulo | Esperado | Encontrado | Evidência | Risco | Arquivo/endpoint |
|---|---|---|---|---|---|---|
| AUT-004 | Autenticação | Usuário inativo tem acesso bloqueado | `profiles.ativo` nunca é lido em RLS/RPC/rota | Grep exaustivo em todo o repositório (0 ocorrências fora de campos homônimos não relacionados) | Ex-funcionário mantém acesso total até a senha ser trocada manualmente no Auth | `supabase/migrations/*.sql` (ausência); `frontend/src/stores/auth.js:32-41` (busca `ativo` mas nunca usa) |
| AUT-009 | Autenticação | UI e API negam acesso a rota administrativa | 8 de 15 rotas protegidas não têm `meta.perfis` (acessíveis a qualquer perfil autenticado) | Leitura completa de `router/index.js` | Executor navega e vê/edita clientes, veículos, orçamentos, OS | `frontend/src/router/index.js:14-109` |
| CAD-004 | Cadastros | Duplicidade de documento impedida/sinalizada | Nenhuma constraint de unicidade em `clientes.documento` | Leitura completa da tabela `clientes` | Cliente duplicado, histórico fragmentado | `supabase/migrations/20260806120100_clientes_veiculos.sql:4-12` |
| ORC-016 | Orçamento | Duplo clique não duplica | Criação do rascunho (`insert` direto) não tem proteção contra duplo-submit | Leitura de `OrcamentosList.vue` (insert sem debounce/disable) | Orçamento rascunho duplicado | `frontend/src/views/orcamentos/OrcamentosList.vue:87-96` |
| APR-004 | Aprovação | Usuário, data/hora e **meio** da aprovação registrados | Só nome+data/hora+comprovante do cliente são gravados; não existe campo "meio" (sistema/e-mail/verbal) nem identidade do aprovador interno | Leitura completa de `orcamentos` (colunas `autorizado_por_nome`, `autorizado_em`, `comprovante_path`) | Auditoria incompleta de quem aprovou internamente | `supabase/migrations/20260806130100_orcamentos.sql:6-20` |
| APR-005 | Aprovação | Idem, para aprovação por e-mail | Mesmo campo genérico, sem distinção de canal | idem | idem | idem |
| APR-006 | Aprovação | Idem, para aprovação verbal | Mesmo campo genérico, sem distinção de canal | idem | idem | idem |
| CON-002 | Conclusão | Bloqueia conclusão com item aprovado pendente de execução | `rpc_concluir_os` só valida checklist, não existe conceito de "item executado" por item de orçamento | Leitura completa de `rpc_concluir_os` | OS concluída sem todos os serviços/peças efetivamente executados | `supabase/migrations/20260806130200_ordens_servico.sql:319-360` |
| CON-007 | Conclusão | Bloqueio ou reabertura auditada ao alterar execução após conclusão | `os_executores_update_proprio` permite ao executor encerrar/editar apontamento mesmo com OS `concluida`/`liberada` (só checa `usuario_id = auth.uid()`, não o status da OS) | Leitura completa das policies de `os_executores` | Histórico de execução alterável após encerramento | `supabase/migrations/20260806130200_ordens_servico.sql:130-133` |
| LIB-006 | Liberação | Administrativo (suporte_administrativo) pode liberar | `rpc_liberar_os` só aceita `encarregado`/`administrador_tecnico` | Leitura das 3 versões de `rpc_liberar_os` | Fluxo operacional real (BR-022/plano-arquitetura) bloqueado para o perfil que deveria liberar | `supabase/migrations/20260806150000_garantia.sql:57-103` |
| GAR-005 | Garantia | Sistema não trata item não relacionado automaticamente como garantia | `rpc_criar_os_garantia` cria OS vazia, sem copiar/restringir itens da OS original; `rpc_baixar_peca_os` não valida vínculo | Leitura completa de ambas as funções | Qualquer serviço pode ser lançado "de garantia" sem relação com o defeito original | `supabase/migrations/20260806150000_garantia.sql:15-51` |
| AUD-002 | Auditoria | Mudança de status é auditada | `ordens_servico` não tem coluna de quem/quando mudou o status (exceto `data_liberacao`) | Leitura completa da tabela `ordens_servico` e de `rpc_transicionar_os` | Impossível saber quem colocou a OS em cada estado | `supabase/migrations/20260806130200_ordens_servico.sql:26-39` |
| AUD-003 | Auditoria | Cancelamento preserva motivo/responsável | `rpc_transicionar_os` cancela sem capturar motivo em lugar nenhum | idem | Cancelamento sem justificativa rastreável | `supabase/migrations/20260806130200_ordens_servico.sql:275-315` |
| PER-006 | Permissões | UI não oferece ação **e** API bloqueia | UI **oferece** a ação (sem check de perfil) em várias telas; só a API bloqueia | Leitura completa de `VeiculosList.vue`, `ClientesList.vue` (sem `useAuthStore`) | UX confusa/enganosa; risco caso a proteção de backend falhe (ver achado crítico #1) | `frontend/src/views/veiculos/VeiculosList.vue`, `frontend/src/views/clientes/ClientesList.vue` |
| DOC-006 | Documentos | Acesso a anexo por usuário indevido é negado | Bucket `comprovantes` liberado a qualquer autenticado, sem filtro por dono/OS | Leitura completa da policy de Storage (Achado crítico #2) | Vazamento de comprovantes financeiros entre clientes/perfis | `supabase/migrations/20260806130400_storage_comprovantes.sql:8-11` |

## 5. Demais falhas

| ID | Módulo | Resultado | Observação |
|---|---|---|---|
| DOC-005 | Documentos | FALHOU (Média) | Nenhuma RPC (`rpc_registrar_autorizacao_orcamento`, `rpc_registrar_termo_ciencia`) confere se o `path` informado realmente existe no Storage antes de aceitar — aceita qualquer string. |

## 6. Casos não implementados

| ID | Funcionalidade ausente | Dependência |
|---|---|---|
| ADC-001 a ADC-008 (8 casos) | Módulo "Adicionais" inteiro (item adicional pendente de aprovação durante execução da OS) | Nenhuma — funcionalidade nunca foi modelada (nem tabela, nem RPC, nem UI) |
| APR-002 | Aprovação parcial de orçamento (BR-006, DEFINIDA) | Exigiria coluna de status por item + RPC de aprovação seletiva |
| OS-002 | Conversão de aprovação parcial em OS | Depende de APR-002 |
| ORC-007, ORC-008 | Mecanismo de desconto (rastreável, com valor/usuário/motivo) | Só existe "acréscimo"; desconto não tem campo/RPC equivalente |
| FIN-003 | Desconto final autorizado no fechamento | Depende do mecanismo de desconto acima |
| ORC-013 | Geração de PDF de orçamento | Nenhuma lib de PDF no projeto (`frontend/package.json`) |
| DOC-001, DOC-002 | PDF de orçamento por versão | idem |
| CON-005, CON-006 | Relatório de encerramento de OS | Nenhuma tela/rotina de relatório encontrada |
| DOC-003 | Relatório de encerramento (documento) | idem |
| GAR-007 | Relatório de garantia | Depende de CON-005 |
| EXE-005, EXE-006 | Foto antes/depois da OS | Nenhuma tabela/coluna/upload de foto de OS em nenhuma migration |
| EXE-007 | Validação de upload inválido (tipo/tamanho) | Nenhuma validação de arquivo em nenhum upload; e o próprio módulo de foto não existe |
| EXE-003 | "Remover executor" como ação distinta | Só existe "encerrar apontamento" (`fim = now()`); não há remoção |
| EST-010 | Estorno de baixa (saída) de estoque | Só existe estorno de **entrada** (`rpc_estornar_nf_entrada`); o enum tem `estorno_saida` mas nenhuma função o grava |
| CAD-012 | Tela dedicada de histórico por veículo | `ClienteDetalhe.vue` filtra OS por `cliente_id`, não por `veiculo_id` |
| NFR-006, NFR-007, NFR-008 | Infraestrutura de teste (suíte repetível, isolada, com seed determinístico) | Não existia nenhuma antes desta auditoria; `supabase/config.toml` referencia `./seed.sql`, que não existe no repositório |

## 7. Casos pendentes de decisão

| ID | Decisão necessária | Impacto |
|---|---|---|
| FIN-010 | BR-036 (cliente interno): cobrança, centro de custo, hora interna? | Fechamento de OS interna hoje não gera nenhuma cobrança nem registro de custo — comportamento "seguro" mas não formalizado |
| PEN-001 | Cobrança de cliente interno | idem |
| PEN-002 | Cálculo de hora interna | Nenhum critério existe no código |
| PEN-003 | Faixas de prazo por valor de orçamento (BR-029) | Nenhum campo de prazo existe em `orcamentos`/`ordens_servico` |
| PEN-004 | Integração de boleto (BR-037) | Fora de escopo, corretamente não implementado |
| PEN-005 | Emissão fiscal (BR-039) | Fora de escopo, corretamente não implementado |
| PEN-006 | Obrigatoriedade de fotos por tipo de serviço (BR-019) | Módulo de foto nem existe (ver seção 6) |
| PEN-007 | Limite/teto de desconto (BR-011) | Mecanismo de desconto nem existe (ver seção 6) — a única faixa configurável hoje é de **acréscimo** |
| PEN-008 | Campos obrigatórios do Termo de Ciência de Débito (BR-023) | Hoje só exige `arquivo_path` não vazio; nenhum outro campo estruturado |

## 8. Cobertura completa

Legenda de evidência: **[EXEC]** = executado ao vivo contra o projeto real
nesta auditoria (não-destrutivo, ver seção 9). **[CÓDIGO]** = achado por
leitura exaustiva do código (determinístico — ausência ou presença de
constraint/policy/coluna, não uma suposição). **[BLOQ]** = funcionalidade
existe no código mas não foi executada por falta de ambiente de teste seguro
(ver seção 10); onde há teste pgTAP pronto, o arquivo é citado.

### Autenticação

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| AUT-001 | Sim | BLOQUEADO | — | Login é Supabase Auth padrão; não executado (precisa credencial real) |
| AUT-002 | Sim | PASSOU | `docs/testing/_safe_checks_output3.txt` | **[EXEC]** senha errada → `invalid_credentials` genérico, sem sessão criada |
| AUT-003 | Sim | PASSOU | `docs/testing/_safe_checks_output3.txt` | **[EXEC]** usuário inexistente → mesma mensagem genérica, sem vazamento |
| AUT-004 | Sim | FALHOU | — | **[CÓDIGO]** `profiles.ativo` nunca lido (grep exaustivo); `stores/auth.js:32-41` busca mas não usa |
| AUT-005 | Sim | FALHOU | `docs/testing/scripts/safe_anon_rpc_checks.sh` | **[EXEC]** Achado crítico #1 |
| AUT-006 | Sim | PASSOU | `docs/testing/_safe_checks_output.txt` | **[EXEC]** JWT malformado → 401 `PGRST301` |
| AUT-007 | Sim | BLOQUEADO | — | Precisa sessão real |
| AUT-008 | Sim | BLOQUEADO | — | RLS parece correta por leitura (`profiles_update_proprio_nome` compara `perfil` novo ao atual); não executado |
| AUT-009 | Sim | FALHOU | — | **[CÓDIGO]** `router/index.js:14-109`, 8/15 rotas sem `meta.perfis` |
| AUT-010 | Parcial | BLOQUEADO | — | Precisa sessão real + inspeção de logs |

### Cadastros

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| CAD-001 | Sim | BLOQUEADO | — | RLS de insert existe; não executado |
| CAD-002 | Sim | BLOQUEADO | — | idem |
| CAD-003 | Sim | BLOQUEADO | — | `clientes.nome not null`; não executado |
| CAD-004 | Sim | FALHOU | — | **[CÓDIGO]** sem unique em `documento` — `clientes_veiculos.sql:4-12` |
| CAD-005 | Sim | BLOQUEADO | — | não executado |
| CAD-006 | Sim | BLOQUEADO | — | unique index `uq_veiculos_placa_ativo` existe; não executado |
| CAD-007 | Sim | BLOQUEADO | — | FK not null; não executado |
| CAD-008 | Sim | BLOQUEADO | — | não executado |
| CAD-009 | Sim | BLOQUEADO | — | soft delete via `deleted_at`; não executado |
| CAD-010 | Sim | BLOQUEADO | — | sem policy DELETE; não executado |
| CAD-011 | Sim | BLOQUEADO | — | não executado |
| CAD-012 | Sim | NÃO_IMPLEMENTADO | — | **[CÓDIGO]** sem tela de histórico por veículo |

### Orçamento

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| ORC-001 | Sim | BLOQUEADO | — | não executado |
| ORC-002 | Sim | BLOQUEADO | — | FK not null; não executado |
| ORC-003 | Sim | BLOQUEADO | — | FK not null; não executado |
| ORC-004 | Sim | BLOQUEADO | — | não executado |
| ORC-005 | Sim | BLOQUEADO | — | não executado |
| ORC-006 | Sim | BLOQUEADO | — | trigger de recálculo existe; não executado |
| ORC-007 | Sim | NÃO_IMPLEMENTADO | — | **[CÓDIGO]** sem mecanismo de desconto |
| ORC-008 | Sim | NÃO_IMPLEMENTADO | — | idem |
| ORC-009 | Sim | BLOQUEADO | `supabase/tests/030_orcamento.sql` | CHECK `quantidade > 0` existe; teste pronto, não executado |
| ORC-010 | Sim | BLOQUEADO | `supabase/tests/030_orcamento.sql` | idem |
| ORC-011 | Sim | BLOQUEADO | `supabase/tests/030_orcamento.sql` | CHECK `valor_unitario >= 0`; teste pronto |
| ORC-012 | Sim | BLOQUEADO | `supabase/tests/030_orcamento.sql` | coluna gerada + trigger; teste pronto |
| ORC-013 | Parcial | NÃO_IMPLEMENTADO | — | **[CÓDIGO]** sem lib de PDF |
| ORC-014 | Sim | BLOQUEADO | — | não executado |
| ORC-015 | Sim | BLOQUEADO | — | RLS bloqueia edição pós-envio; versionamento existe; não executado |
| ORC-016 | Sim | FALHOU | — | **[CÓDIGO]** criação de rascunho sem proteção contra duplo-submit |

### Aprovação

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| APR-001 | Sim | BLOQUEADO | — | não executado |
| APR-002 | Sim | NÃO_IMPLEMENTADO | — | **[CÓDIGO]** sem aprovação por item |
| APR-003 | Sim | BLOQUEADO | — | `rpc_rejeitar_orcamento` existe; não executado |
| APR-004 | Sim | FALHOU | — | **[CÓDIGO]** sem campo "meio"; ver Falhas altas |
| APR-005 | Parcial | FALHOU | — | idem |
| APR-006 | Parcial | FALHOU | — | idem |
| APR-007 | Sim | BLOQUEADO | — | cenário "executor autenticado" não testado (distinto do achado crítico #1) |
| APR-008 | Sim | BLOQUEADO | — | RLS bloqueia edição de item pós-envio; não executado |
| APR-009 | Sim | BLOQUEADO | — | idem |
| APR-010 | Sim | BLOQUEADO | — | via nova versão (não item isolado); não executado |
| APR-011 | Sim | BLOQUEADO | — | sem policy DELETE; não executado |
| APR-012 | Sim | BLOQUEADO | — | check de status bloqueia reaprovação; não executado |

### Ordem de Serviço

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| OS-001 | Sim | BLOQUEADO | — | não executado |
| OS-002 | Sim | NÃO_IMPLEMENTADO | — | depende de APR-002 |
| OS-003 | Sim | BLOQUEADO | — | `rpc_criar_os` checa status aprovado; não executado |
| OS-004 | Sim | FALHOU | — | **[CÓDIGO]** ver Falhas críticas |
| OS-005 | Sim | BLOQUEADO | — | não executado |
| OS-006 | Sim | BLOQUEADO | — | não executado |
| OS-007 | Sim | BLOQUEADO | — | não executado |
| OS-008 | Sim | BLOQUEADO | — | máquina de estados explícita em `rpc_transicionar_os`; não executado |
| OS-009 | Sim | BLOQUEADO | — | transições de saída de `concluida`/`liberada`/`cancelada` não estão na lista permitida; não executado |
| OS-010 | Sim | FALHOU | — | **[CÓDIGO]** ver Falhas críticas |
| OS-011 | Sim | BLOQUEADO | — | não executado |
| OS-012 | Sim | BLOQUEADO | — | sem policy DELETE/UPDATE direta; não executado |

### Adicionais

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| ADC-001 a ADC-008 | Sim | NÃO_IMPLEMENTADO | — | **[CÓDIGO]** grep exaustivo (backend + frontend) — módulo inteiro ausente, ver Achados críticos |

### Estoque

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| EST-001 | Sim | BLOQUEADO | — | não executado |
| EST-002 | Sim | BLOQUEADO | `supabase/tests/020_estoque.sql` | CHECK em `nf_entrada_itens.quantidade`; teste pronto |
| EST-003 | Sim | BLOQUEADO | — | CHECK `valor_unitario >= 0`; não executado |
| EST-004 | Sim | FALHOU | — | **[CÓDIGO]** ver Falhas críticas |
| EST-005 | Sim | BLOQUEADO | — | `origem_id` não é validado contra existência real; não executado |
| EST-006 | Sim | BLOQUEADO | — | não executado |
| EST-007 | Sim | BLOQUEADO | `supabase/tests/020_estoque.sql` | anti-negativação em `rpc_registrar_saida_estoque`; teste pronto |
| EST-008 | Sim | BLOQUEADO | `supabase/tests/020_estoque.sql` | idem; teste pronto |
| EST-009 | Sim | FALHOU | — | **[CÓDIGO]** ver Falhas críticas |
| EST-010 | Sim | NÃO_IMPLEMENTADO | — | **[CÓDIGO]** sem RPC de estorno de saída |
| EST-011 | Sim | BLOQUEADO | — | `revoke insert, update, delete` em `estoque_movimentos`; não executado |
| EST-012 | Sim | BLOQUEADO | — | sem policy UPDATE em `estoque_movimentos`; não executado |
| EST-013 | Sim | NÃO_AUTOMATIZÁVEL | — | exige 2 sessões simultâneas; `FOR UPDATE` presente no código, não testado |
| EST-014 | Sim | BLOQUEADO | — | não executado |
| EST-015 | Sim | BLOQUEADO | — | não executado |
| EST-016 | Sim | NÃO_AUTOMATIZÁVEL | — | mesma razão de EST-013 |

### Execução

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| EXE-001 | Sim | BLOQUEADO | — | não executado |
| EXE-002 | Sim | BLOQUEADO | — | não executado |
| EXE-003 | Sim | NÃO_IMPLEMENTADO | — | **[CÓDIGO]** só "encerrar", não "remover" |
| EXE-004 | Sim | BLOQUEADO | — | não executado |
| EXE-005 | Parcial | NÃO_IMPLEMENTADO | — | **[CÓDIGO]** sem módulo de foto |
| EXE-006 | Parcial | NÃO_IMPLEMENTADO | — | idem |
| EXE-007 | Sim | NÃO_IMPLEMENTADO | — | idem |
| EXE-008 | Sim | BLOQUEADO | — | cenário "executor autenticado" não testado (RLS parece correta por leitura) |
| EXE-009 | Sim | BLOQUEADO | — | idem |
| EXE-010 | Sim | BLOQUEADO | — | não executado |

### Conclusão

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| CON-001 | Sim | BLOQUEADO | — | não executado |
| CON-002 | Sim | FALHOU | — | **[CÓDIGO]** ver Falhas altas |
| CON-003 | Sim | BLOQUEADO | — | validação de checklist obrigatório existe; não executado |
| CON-004 | Sim | BLOQUEADO | — | idem |
| CON-005 | Parcial | NÃO_IMPLEMENTADO | — | **[CÓDIGO]** sem relatório |
| CON-006 | Parcial | NÃO_IMPLEMENTADO | — | depende de CON-005 |
| CON-007 | Sim | FALHOU | — | **[CÓDIGO]** ver Falhas altas |
| CON-008 | Sim | BLOQUEADO | — | check de status bloqueia; não executado |

### Financeiro

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| FIN-001 | Sim | BLOQUEADO | — | não executado |
| FIN-002 | Sim | BLOQUEADO | — | indireto (sem aprovação parcial); não executado |
| FIN-003 | Sim | NÃO_IMPLEMENTADO | — | **[CÓDIGO]** sem mecanismo de desconto |
| FIN-004 | Sim | BLOQUEADO | — | não executado |
| FIN-005 | Sim | BLOQUEADO | — | tolerância de 0.01 em `rpc_parcelar_cobranca`; não executado |
| FIN-006 | Sim | BLOQUEADO | — | não executado |
| FIN-007 | Sim | BLOQUEADO | — | nenhum trigger automático encontrado (comportamento correto por ausência, mas não executado) |
| FIN-008 | Sim | BLOQUEADO | — | não executado |
| FIN-009 | Sim | BLOQUEADO | — | sem policy UPDATE em `cobrancas.valor_total`; não executado |
| FIN-010 | Parcial | PENDENTE_DECISÃO | — | BR-036 pendente |

### Liberação

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| LIB-001 | Sim | BLOQUEADO | `supabase/tests/040_liberacao.sql` | teste pronto, não executado |
| LIB-002 | Sim | BLOQUEADO | `supabase/tests/040_liberacao.sql` | teste pronto, não executado |
| LIB-003 | Sim | BLOQUEADO | `supabase/tests/040_liberacao.sql` | teste pronto, não executado (mas alcançabilidade da RPC sem sessão já provada — achado crítico #1) |
| LIB-004 | Sim | BLOQUEADO | — | cenário "executor autenticado" não testado |
| LIB-005 | Sim | BLOQUEADO | — | não executado |
| LIB-006 | Sim | FALHOU | — | **[CÓDIGO]** ver Achados críticos #3 |
| LIB-007 | Sim | BLOQUEADO | — | checklist já é gate de `rpc_concluir_os`, anterior à liberação; não executado |
| LIB-008 | Sim | BLOQUEADO | — | check de status bloqueia; não executado |

### Garantia

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| GAR-001 | Sim | BLOQUEADO | — | não executado |
| GAR-002 | Sim | BLOQUEADO | — | não executado |
| GAR-003 | Sim | BLOQUEADO | — | checagem de prazo de 90 dias existe; não executado |
| GAR-004 | Sim | BLOQUEADO | — | `os_origem_id`; não executado |
| GAR-005 | Sim | FALHOU | — | **[CÓDIGO]** ver Falhas altas |
| GAR-006 | Sim | BLOQUEADO | — | sem policy UPDATE em `ordens_servico`; não executado |
| GAR-007 | Parcial | NÃO_IMPLEMENTADO | — | depende de CON-005 |
| GAR-008 | Sim | NÃO_AUTOMATIZÁVEL | — | condição de corrida entre duas chamadas simultâneas; exige 2 sessões |

### Auditoria

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| AUD-001 | Sim | FALHOU | — | **[CÓDIGO]** ver Falhas críticas |
| AUD-002 | Sim | FALHOU | — | **[CÓDIGO]** ver Falhas altas |
| AUD-003 | Sim | FALHOU | — | **[CÓDIGO]** ver Falhas altas |
| AUD-004 | Sim | BLOQUEADO | — | ledger append-only para entrada; não executado |
| AUD-005 | Sim | BLOQUEADO | — | versionamento preserva histórico; não executado |
| AUD-006 | Sim | BLOQUEADO | — | ausência de policies DELETE é estrutural; não executado formalmente |

### Permissões

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| PER-001 | Sim | BLOQUEADO | — | cenário autenticado não testado |
| PER-002 | Sim | BLOQUEADO | — | idem |
| PER-003 | Sim | BLOQUEADO | — | idem |
| PER-004 | Sim | BLOQUEADO | — | idem |
| PER-005 | Sim | BLOQUEADO | — | idem |
| PER-006 | Sim | FALHOU | — | **[CÓDIGO]** ver Falhas altas |

### Documentos

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| DOC-001 | Parcial | NÃO_IMPLEMENTADO | — | sem PDF |
| DOC-002 | Parcial | NÃO_IMPLEMENTADO | — | sem PDF |
| DOC-003 | Parcial | NÃO_IMPLEMENTADO | — | sem relatório |
| DOC-004 | Parcial | BLOQUEADO | — | FK `termos_ciencia_debito.cobranca_id`; não executado |
| DOC-005 | Sim | FALHOU | — | **[CÓDIGO]** ver Demais falhas |
| DOC-006 | Sim | FALHOU | — | **[CÓDIGO]** ver Achados críticos #2 |

### Fluxo E2E

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| E2E-001 a E2E-010 | Sim | BLOQUEADO | — | exigem fluxo completo autenticado ponta a ponta; não executado nesta auditoria (ambiente) |

### Não funcional

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| NFR-001 | Sim | BLOQUEADO | — | `rpc_criar_os` é uma única transação; não executado com falha forçada |
| NFR-002 | Sim | BLOQUEADO | — | idem |
| NFR-003 | Sim | PASSOU | `docs/testing/_safe_checks_output.txt`, `_output2.txt` | **[EXEC]** payloads variados/incompletos sempre retornaram 400 com mensagem de domínio, nunca 500 |
| NFR-004 | Sim | PASSOU | idem | **[EXEC]** todas as 21 RPCs com UUID inexistente retornaram erro de domínio coerente, nunca 500 |
| NFR-005 | Sim | BLOQUEADO | — | `rpc_criar_os` valida `orcamento.veiculo_id = p_veiculo_id`; não executado |
| NFR-006 | Sim | NÃO_IMPLEMENTADO | — | nenhuma suíte existia antes desta auditoria |
| NFR-007 | Sim | NÃO_IMPLEMENTADO | — | infra pgTAP criada usa `rollback`, mas não validada em execução |
| NFR-008 | Sim | NÃO_IMPLEMENTADO | — | `supabase/config.toml:71` referencia `./seed.sql`, inexistente no repo |
| NFR-009 | Parcial | BLOQUEADO | — | precisa sessão real + acesso a logs do projeto |
| NFR-010 | Sim | BLOQUEADO | — | não executado |

### Decisão pendente

| ID | Automatizado | Resultado | Teste/arquivo | Evidência |
|---|---|---|---|---|
| PEN-001 a PEN-008 | Não | PENDENTE_DECISÃO | — | conforme definição da própria matriz (BR correspondente é PENDENTE) |

---

## 9. Próximas ações priorizadas

### P0 — Integridade / segurança / financeiro

1. **Corrigir o bypass de permissão em todas as RPCs** (Achado crítico #1) —
   trocar `current_perfil() not in (lista)` por
   `coalesce(current_perfil()::text,'') not in (lista)` em pelo menos 21
   funções. Teste de regressão já pronto em
   `supabase/tests/010_seguranca_permissao_anon_bypass.sql`.
2. **Restringir a policy de leitura do bucket `comprovantes`** (Achado
   crítico #2) para exigir vínculo com o registro (OS/cobrança) do próprio
   usuário/perfil, não o bucket inteiro.
3. **Impedir reconversão de orçamento já convertido em OS** (OS-004) — marcar
   o orçamento como "convertido" (nova coluna/enum) e checar em `rpc_criar_os`.
4. **Vincular baixa de estoque a idempotência por origem** (EST-009) — índice
   único (ou checagem explícita) em `estoque_movimentos (origem_tipo,
   origem_id, peca_id)` para saída, ou lock de aplicação equivalente.
5. **Adicionar `suporte_administrativo` à lista de perfis de `rpc_liberar_os`**
   (LIB-006), conforme BR-022/plano-arquitetura.
6. **Tratar estoque no cancelamento de OS** (OS-010) — exigir estorno
   explícito das baixas já feitas antes de permitir `cancelada`.

### P1 — Regra de negócio / operação

1. Decidir e implementar (ou formalmente descartar, com registro) a
   **aprovação parcial de orçamento** (APR-002/OS-002/BR-006 — regra
   DEFINIDA, não deveria ficar sem implementação).
2. Implementar o **módulo de Adicionais** (ADC-001 a 008) ou re-escopar
   formalmente a regra BR-009 se a intenção real for outra.
3. Implementar **mecanismo de desconto** rastreável (ORC-007/008/FIN-003),
   simétrico ao de acréscimo já existente.
4. Adicionar coluna(s) de auditoria (`atualizado_por`, `atualizado_em`,
   `motivo`) em `ordens_servico` para cobrir AUD-002/AUD-003/CON-002/CON-007.
5. Vincular a baixa de estoque da execução da OS aos itens do orçamento
   aprovado (EST-004), em vez de baixa livre por SKU.
6. Restringir `os_executores_update_proprio` para não permitir edição após a
   OS estar `concluida`/`liberada`/`cancelada` (CON-007).
7. Adicionar `meta.perfis` às rotas hoje sem restrição de role
   (`clientes`, `veiculos`, `orcamentos`, `os`, `estoque/pecas`,
   `solicitacoes` — AUT-009) e checks de perfil client-side equivalentes aos
   já usados em outras telas (PER-006).
8. Enforçar `profiles.ativo` no login/carregamento de sessão (AUT-004).

### P2 — Usabilidade / melhoria

1. Adicionar unique constraint (ou verificação explícita com aviso) em
   `clientes.documento` (CAD-004).
2. Proteger a criação inicial de orçamento/rascunho contra duplo-submit
   (ORC-016) — desabilitar botão durante a chamada.
3. Validar existência do `path` no Storage antes de aceitar `comprovante_path`
   / `arquivo_path` (DOC-005).
4. Criar tela dedicada de histórico por veículo (CAD-012).
5. Depois de qualquer correção de P0, rodar a suíte pgTAP criada em
   `supabase/tests/` contra um ambiente seguro e preencher os resultados
   reais nesta mesma tabela.

---

## 10. Comandos executados

Todos não-destrutivos — evidência bruta salva junto deste relatório.

```bash
# Bateria 1 e 2 — bypass de permissão + robustez de payload/ID inexistente
# (papel anon, sem nenhuma credencial, 23 chamadas no total)
bash docs/testing/scripts/safe_anon_rpc_checks.sh
# saída bruta: docs/testing/_safe_checks_output.txt e _safe_checks_output2.txt

# Bateria 3 — AUT-002/AUT-003 (login com credenciais inexistentes/erradas,
# via GoTrue, nenhuma conta real necessária)
curl -s -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"usuario-que-nao-existe-auditoria-2026@teste.invalido","password":"senha-qualquer-123"}'
# saída bruta: docs/testing/_safe_checks_output3.txt

# Verificação de ambiente (sem Docker disponível)
docker --version   # => "docker: command not found"
npx supabase --version   # => 2.113.0 (CLI disponível, mas sem daemon Docker p/ `supabase start`)
```

Infraestrutura criada mas **não executada** (ver `supabase/tests/README.md`):

```bash
cd "SISTEMA NOVO"
supabase start
supabase test db
```

## 11. Observações de ambiente

- **Dependências:** backend é 100% Supabase (Postgres + PostgREST + RLS +
  RPCs `plpgsql`) — não há servidor de aplicação separado. Frontend é Vue 3 +
  Vite + PrimeVue + Pinia + `@supabase/supabase-js`, compilado para estático.
- **Repositório Git:** o diretório de trabalho não é um repositório Git
  (`Is a git repository: false`) — não há branch/commit para citar no
  resumo executivo; recomendo `git init` antes da próxima rodada de testes
  para poder rastrear quando cada correção foi aplicada.
- **Serviços externos:** nenhum mock necessário — todas as regras de negócio
  vivem em RPCs Postgres, sem chamadas a serviços terceiros (sem gateway de
  pagamento, sem emissor fiscal, sem SMS/e-mail transacional custom).
- **Mocks/fixtures/seeds:** nenhum existia antes desta auditoria.
  `supabase/tests/_helpers.sql` (criado nesta auditoria) fornece
  `tests.criar_usuario_teste()` e `tests.autenticar_como()`/`autenticar_como_anon()`
  para uso futuro; não há `supabase/seed.sql`.
- **Limitações desta auditoria:**
  1. Sem Docker → sem `supabase start` → sem banco local isolado.
  2. Único projeto Supabase é o de desenvolvimento real, com dados de
     cliente reais misturados com dados de teste (ver
     `supabase/tests/README.md` e memória do projeto) → testes destrutivos
     bloqueados por instrução explícita do `CLAUDE.md`.
  3. Sem credenciais de usuários de teste por perfil (`executor`,
     `encarregado`, `suporte_administrativo`, `diretoria`) → todos os
     cenários de "usuário autenticado com perfil errado" (distintos do
     achado crítico #1, que é "sem sessão nenhuma") ficaram `BLOQUEADO`,
     mesmo onde a leitura de código sugere proteção correta.
  4. Nenhuma senha ou credencial de usuário real foi solicitada, manuseada
     ou usada nesta auditoria — apenas a `anon key` pública (já embutida em
     qualquer build do frontend) e chamadas HTTP comprovadamente
     não-destrutivas.
