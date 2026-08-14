# TEST REPORT — FEATURE-SERVICOS-01 (Catálogo estruturado de Serviços/Mão de obra)

Data: 2026-08-17
Ambiente: homologado em DEV/QA (`jzjbiejmcaygwycvqggm`) e, após aprovação explícita do usuário no mesmo dia, **promovido também para produção** (`wtxbodhqyasdlmyoyjur`).
Migrations: `20260817140000_p2_servicos_catalogo.sql` (versão inicial) + `20260817140100_p2_fix_natureza_gerada.sql` (correção same-day, ver seção MODELAGEM). Ambas aplicadas nos dois ambientes, na mesma ordem, sem edição entre um e outro.

**Nota sobre a promoção:** o merge do PR que trouxe o frontend desta feature disparou o deploy automático do GitHub Pages (CI on-push-to-main) **antes** da migration ter sido aplicada em produção — uma janela em que a tela "Serviços" ficaria com erro de carregamento em produção (degradação graciosa: a tela mostra "não foi possível carregar", e o restante do app — incluindo Orçamentos — continua funcionando normalmente, pois a ausência da tabela `servicos` é tratada sem exceção não tratada). Identificada e comunicada ao usuário assim que descoberta; usuário autorizou explicitamente a promoção da migration para fechar a janela. Aplicada por ele mesmo via `npx supabase db push --project-ref wtxbodhqyasdlmyoyjur` (mesmo padrão já usado nas etapas anteriores) e confirmada por leitura (`migration list` + contagem de categorias/RPCs/coluna gerada) do lado do Claude Code.

---

## Resumo executivo

Catálogo de Serviços implementado e homologado em DEV/QA: tabela `servicos` (com `codigo` único gerado automaticamente ou manual, `preco_referencia` comercial independente de `custo_hora_config`, `tempo_estimado_minutos`, `garantia_dias`, vínculo opcional a `checklist_templates`), tabela `servico_categorias` (administrável, seed inicial de 7 categorias), RPCs auditadas para escrita, RLS/RBAC espelhando o catálogo irmão (Peças), integração no orçamento com **snapshot imutável** (regra crítica do pedido) e serviço avulso preservado. 60/60 asserções pgTAP passando (16 novas + 44 de regressão pré-existente, 0 falhas). `npm run build` do frontend passou. Validação por clique real no browser **bloqueada** pela mesma limitação de credenciais de DEV já registrada nas etapas anteriores (ver seção BUILD).

---

## MODELAGEM

Implementado. `servicos` (id, codigo único, nome, categoria_id → `servico_categorias`, descricao, preco_referencia, tempo_estimado_minutos, garantia_dias default 90, checklist_template_id → `checklist_templates` já existente, ativo, criado_em/por, atualizado_em/por). `servico_categorias` (id, nome único, ativo) — estrutura administrável simples, seedada com Ar-condicionado/Mecânica/Elétrica/Suspensão/Freios/Preventiva/Diagnóstico como dado inicial editável, não regra hardcoded.

`orcamento_itens` estendida de forma aditiva: `servico_id`, `codigo_servico_snapshot`, `tempo_estimado_minutos_snapshot`, `garantia_dias_snapshot`, e `natureza` (discriminador `peca`/`servico_cadastrado`/`servico_avulso`).

**Correção same-day registrada:** a primeira versão de `natureza` era coluna manual com `default 'peca'` + CHECK de consistência — isso quebrou, na regressão pgTAP, fixtures existentes (`030_orcamento.sql`, `040_liberacao.sql`) que inserem `orcamento_itens` sem `peca_id` e sem informar `natureza` (mesmo padrão usado hoje pelo frontend). Corrigido pela migration `20260817140100_p2_fix_natureza_gerada.sql`: `natureza` virou coluna **gerada** (`generated always as`, derivada de `peca_id`/`servico_id`), eliminando a classe inteira de divergência possível em vez de só o caso encontrado. Regressão completa (10 arquivos, 60 asserções) confirmada verde depois da correção.

Checklist/fotos: reaproveita `checklist_templates`/`foto_antes_obrigatoria`/`foto_depois_obrigatoria` já existentes — nenhum campo duplicado em `servicos`.

## RLS

Implementado.
- `servicos`: SELECT liberado a qualquer perfil autenticado ativo (`current_user_ativo()`) — inclusive inativos, de propósito (histórico e tela administrativa precisam ver). INSERT/UPDATE restrito a `suporte_administrativo`/`administrador_tecnico`. Sem policy de DELETE (soft-disable apenas).
- `servico_categorias`: SELECT amplo; INSERT/UPDATE restrito a `administrador_tecnico`.
- Testado real contra DEV (SERV-009/009b): `anon` bloqueado tanto na RPC de escrita (P0001) quanto no SELECT (0 linhas retornadas).

## RBAC

Implementado, decisão confirmada com o usuário durante o planejamento: escrita no catálogo espelha **Peças** (`suporte_administrativo` + `administrador_tecnico`), não `checklist_templates`. `encarregado` consulta e seleciona no orçamento, mas não cadastra/edita serviço — testado real (SERV-007 executor bloqueado, SERV-008 suporte_administrativo permitido, SERV-010 usuário autenticado porém `profiles.ativo=false` bloqueado).

## CRUD

Implementado via RPC (não escrita direta via RLS, ver AUDITORIA): `rpc_criar_servico`, `rpc_atualizar_servico`, `rpc_ativar_servico`, `rpc_inativar_servico`. Código humano (`SV-001`, `SV-002`...) gerado automaticamente por sequence quando não informado, ou aceita valor manual customizado (`UNIQUE` garante integridade) — decisão confirmada com o usuário. Testado real: criação (SERV-001), duplicidade de código bloqueada (SERV-002), preço negativo bloqueado (SERV-003), inativação (SERV-004), inativo some do filtro de nova seleção mas continua visível no histórico/admin (SERV-005/006).

## AUDITORIA

Implementado. Todas as 4 RPCs de escrita chamam `registrar_auditoria` (mesmo mecanismo único do projeto — `auditoria_eventos`/`registrar_auditoria()`, nenhum segundo sistema criado), com valor anterior/novo em JSONB. É também o motivo de usar RPC em vez de escrita direta via RLS (diferente de `orcamento_itens`): `registrar_auditoria` está com `REVOKE EXECUTE FROM anon, authenticated`, só chamável de dentro de função `SECURITY DEFINER`.

## ORÇAMENTO

Implementado. `OrcamentosList.vue`: seletor "Tipo" no formulário de item passa de 2 para 3 opções (Peça / Serviço cadastrado / Mão de obra avulsa). Selecionar um serviço cadastrado preenche automaticamente descrição e preço de referência (mantendo `valor_unitario` livremente editável — ver PREÇO REFERÊNCIA). Tabela de itens já incluídos ganhou um terceiro estado de badge ("Serviço"). `salvarItens()` grava `servico_id` + os 3 campos de snapshot junto com o payload já existente.

## SNAPSHOT

Implementado e testado — regra crítica do pedido (seção 8). Teste real (SERV-ORC-001): serviço criado a R$450, adicionado a um item de orçamento, catálogo depois alterado para R$520 via `rpc_atualizar_servico` — o item de orçamento já salvo permanece em R$450. `descricao`/`valor_unitario` já eram, por construção, o próprio snapshot (copiados no insert, nunca joins vivos); a extensão só formaliza código/tempo/garantia como colunas explícitas.

## SERVIÇO AVULSO

Implementado e testado (SERV-ORC-003). Mão de obra sem catálogo continua funcionando exatamente como antes — `natureza` computa `servico_avulso` automaticamente quando nem `peca_id` nem `servico_id` estão preenchidos. Nenhum código (teste ou frontend) precisa declarar `natureza` manualmente, já que é coluna gerada.

## PREÇO REFERÊNCIA

Implementado e testado (SERV-ORC-002). `preco_referencia` é comercial de referência; o item do orçamento pode divergir livremente (testado: serviço referência R$450, item lançado a R$480 — catálogo permanece R$450, item permanece R$480). Reconfirmado por leitura de código e pela própria migration que `servicos.preco_referencia` **não** entra no cálculo de `calcular_e_snapshot_custo_interno_os` — custo interno continua exclusivamente `horas_apontadas × custo_hora_vigente()`, sem nenhuma referência a `servicos`.

## TEMPO ESTIMADO

Estruturado, não explorado além do dado. `tempo_estimado_minutos` existe no catálogo e é snapshotado no item (`tempo_estimado_minutos_snapshot`) quando um serviço cadastrado é usado. Nenhum dashboard/indicador de "estimado × real" foi implementado nesta etapa (fora de escopo explícito do pedido, seção 9) — registrado em MELHORIAS FUTURAS.

## GARANTIA

Estruturado, não integrado à lógica de garantia existente. `garantia_dias` (default 90) existe no catálogo como metadado de referência e é snapshotado no item (`garantia_dias_snapshot`). **Não altera** o literal fixo de 90 dias já usado em `rpc_criar_os_garantia` — investigado antes de implementar (instrução seção 10: "não quebrar garantia existente"); a garantia de fato continua uma OS nova vinculada por `os_garantia_itens.orcamento_item_original_id` (FK para a linha já salva de `orcamento_itens`), que nunca lê `servicos` diretamente, então uma mudança futura no catálogo não tem caminho para alcançar um registro de garantia já criado. **Não testado ponta a ponta nesta rodada** (SERV-GAR-001 na matriz, marcado NÃO_AUTOMATIZÁVEL/manual) — a garantia dessa invariante nesta etapa é por leitura de código + regressão da suíte `050_regressao_garantia.sql` (4/4 verde, sem alteração de comportamento).

## CHECKLIST

Implementado apenas o vínculo no catálogo (`servicos.checklist_template_id → checklist_templates`), sem automação. Investigado como checklists são hoje vinculados à OS (via `ordens_servico.checklist_template_id`, setado por `rpc_definir_checklist_os`) antes de decidir — automatizar a propagação Serviço → Checklist → OS ficaria fora do escopo desta etapa por decisão explícita do pedido (seção 11: "caso haja dúvida, implementar apenas o vínculo... registrar automação como melhoria futura"). Registrado em MELHORIAS FUTURAS.

## PDF

Nenhuma mudança necessária, confirmado por leitura de código. `OrcamentoPdf.vue` e `rpc_dados_pdf_orcamento` (`supabase/migrations/20260814111000_p1c_relatorios.sql`) só leem `descricao`/`quantidade`/`valor_unitario` de `orcamento_itens` — nunca fazem join vivo com `pecas`/`servicos`. A imutabilidade histórica do PDF já era garantida por construção antes desta etapa; o snapshot só formaliza o que já era verdade.

## BUILD

`npm run build` (frontend) passou sem erros — `ServicosList-*.js` (9.66 kB) gerado, `OrcamentosList-*.js` compilou normalmente com as mudanças.

**Validação por clique real no browser: bloqueada.** Tentativa de login em DEV com um usuário de teste criado via SQL (mesmo padrão de `tests.criar_usuario_teste` do pgTAP) falhou — GoTrue rejeitou "E-mail ou senha inválidos" (um INSERT direto em `auth.users` não é suficiente para autenticação real via API; precisaria da Admin API com `service_role`, não disponível localmente). Usuário de teste removido do banco após a tentativa (nenhum resíduo). Esta é a mesma limitação já registrada nas etapas UX anteriores (ver memória `project_ux_redesign_status`) — verificação desta etapa foi por migration real + pgTAP real + build + revisão de código, não por clique real na tela.

## PGTAP

Implementado e executado de verdade contra DEV (`npx supabase db query --linked -f`), seguindo o padrão RC1 já estabelecido (nenhum arquivo novo, nenhum Docker). Novo arquivo `supabase/tests/070_servicos.sql`: **16/16 asserções passando** (SERV-001 a SERV-010, SERV-ORC-001/002/002b/003, mais um teste bônus do CHECK `orcamento_itens_peca_ou_servico_nao_ambos`).

## REGRESSÃO

Suíte completa (`010` a `060`) reexecutada depois da migration — **44/44 asserções passando, 0 falhas**: `010_seguranca_permissao_anon_bypass` (6/6), `020_estoque` (6/6), `030_orcamento` (4/4), `040_liberacao` (4/4), `050_regressao_garantia` (4/4), `060_contratos_rpc_criticas` (20/20). Total combinado: **60/60**.

A primeira aplicação da migration quebrou `030_orcamento.sql`/`040_liberacao.sql` (ver MODELAGEM) — corrigida same-day antes de qualquer promoção, com a suíte completa reexecutada e verde depois da correção.

---

## Cobertura completa

| ID | Automatizado | Resultado | Evidência |
|---|---|---|---|
| SERV-001 | Sim | PASSOU | `070_servicos.sql` |
| SERV-002 | Sim | PASSOU | `070_servicos.sql` |
| SERV-003 | Sim | PASSOU | `070_servicos.sql` |
| SERV-004 | Sim | PASSOU | `070_servicos.sql` |
| SERV-005 | Sim | PASSOU | `070_servicos.sql` |
| SERV-006 | Sim | PASSOU | `070_servicos.sql` |
| SERV-007 | Sim | PASSOU | `070_servicos.sql` |
| SERV-008 | Sim | PASSOU | `070_servicos.sql` |
| SERV-009 | Sim | PASSOU | `070_servicos.sql` |
| SERV-010 | Sim | PASSOU | `070_servicos.sql` |
| SERV-ORC-001 | Sim | PASSOU | `070_servicos.sql` |
| SERV-ORC-002 | Sim | PASSOU | `070_servicos.sql` |
| SERV-ORC-003 | Sim | PASSOU | `070_servicos.sql` |
| SERV-ORC-004 | Não | NÃO_AUTOMATIZÁVEL nesta rodada | mecanismo de aprovação parcial não alterado por esta feature; ver TEST_MATRIX |
| SERV-GAR-001 | Não | NÃO_AUTOMATIZÁVEL nesta rodada | garantia referencia item já salvo, não catálogo; ver TEST_MATRIX/BR-044 |

## MELHORIAS FUTURAS

Conscientemente fora de escopo nesta etapa (registradas no pedido original e/ou descobertas durante a implementação):

- Automação `Serviço → Checklist → OS` (hoje só existe o vínculo no catálogo).
- Extensão do mesmo conceito de catálogo a Adicionais da OS (FEATURE-SERVICOS-02, conforme o próprio pedido já antecipava).
- Relatórios: serviços mais vendidos, faturamento por serviço, quantidade por serviço, tempo estimado × real, margem de mão de obra, retornos em garantia por serviço — o modelo de dados já está apto (`tempo_estimado_minutos`, snapshots), mas nenhum dashboard/indicador novo foi implementado.
- SERV-ORC-004 (aprovação parcial combinando peça + serviço cadastrado + avulso na mesma OS) e SERV-GAR-001 (garantia ponta a ponta com mudança de catálogo) ficaram como casos manuais/E2E, não automatizados nesta rodada.
- Validação por clique real no browser (bloqueada por credenciais de DEV, ver BUILD) — pendente de um usuário de teste válido fornecido pelo usuário, ou de acesso à Admin API do Supabase.

## Próximas ações priorizadas

**P0:**
1. Homologação visual real (clique no browser), tanto em DEV quanto no app publicado em produção, cobrindo pelo menos: criar/editar/inativar serviço, adicionar serviço cadastrado + avulso a um orçamento, gerar PDF. Continua **pendente** — bloqueada nesta sessão pela mesma limitação de credenciais de DEV já registrada nas etapas anteriores; usuário optou por pular por ora e aprovar a promoção só com base em migration real + 60/60 pgTAP + build + revisão de código.

**P1:**
2. Decidir se SERV-ORC-004/SERV-GAR-001 precisam de teste E2E dedicado, ou se a cobertura por regressão + leitura de código já registrada é suficiente.
3. Atualizar `docs/PRODUCTION_READINESS_CHECKLIST.md` com esta promoção (feito nesta rodada, ver arquivo).

**P2:**
4. Itens de MELHORIAS FUTURAS, sem urgência.

## Status final

**PROMOVIDO PARA PRODUÇÃO em 2026-08-17**, com aprovação explícita do usuário. `migration list --project-ref wtxbodhqyasdlmyoyjur` confirma as duas migrations com `remote` preenchido; verificação adicional confirma 7 categorias seedadas, as 5 funções (`rpc_criar_servico`, `rpc_atualizar_servico`, `rpc_ativar_servico`, `rpc_inativar_servico`, `gerar_codigo_servico`) presentes, e `orcamento_itens.natureza` como coluna gerada (versão corrigida, não a que quebrou a regressão na primeira tentativa).
