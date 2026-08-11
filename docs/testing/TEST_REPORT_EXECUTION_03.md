# TEST REPORT — EXECUÇÃO 03 — ERP Oficina

> Terceira rodada de homologação. `docs/testing/TEST_REPORT.md` (1ª rodada,
> só leitura de código) e `docs/testing/TEST_REPORT_EXECUTION_02.md` (2ª
> rodada, 75/176 executados de verdade, 6 P0 corrigidos) ficam preservados
> intactos como baseline — nenhum dos dois foi editado nesta rodada.
>
> Autorização mantida: projeto Supabase `jzjbiejmcaygwycvqggm` ("SISTEMA
> NOVO") tratado como ambiente de desenvolvimento/teste descartável. O
> projeto `cedqaxmkffqrwfopgyze` ("YNAB COVER") não foi tocado em nenhum
> momento.
>
> Escopo desta rodada: **homologar o que já existe, com execução real** —
> nenhuma funcionalidade P1/P2 nova foi implementada (aprovação parcial,
> adicionais, descontos, fotos, PDF, relatórios, histórico por veículo
> continuam NÃO_IMPLEMENTADO). As únicas mudanças de código desta rodada são
> as duas correções P0 explicitamente autorizadas (AUT-004 e EST-009), só
> aplicadas depois de confirmar por execução real e limpa que os achados
> eram FALHOU de verdade.

---

## 1. Resumo executivo

| Métrica | Valor |
|---|---|
| **TOTAL** | **176** |
| **EXECUTADOS REALMENTE — cumulativo (rodadas 2+3)** | **124/176 ≈ 70%** (era 75/176 ≈ 43% após a rodada 2) |
| **EXECUTADOS REALMENTE — só nesta rodada** | **53** (49 casos que estavam BLOQUEADO + revalidação de AUT-004, EST-009, OS-004, DOC-006) |
| **PASSOU** | **122** |
| **FALHOU** | **17** |
| **BLOQUEADO** | **0** |
| **NÃO_IMPLEMENTADO** | **26** |
| **NÃO_AUTOMATIZÁVEL** | **2** |
| **PENDENTE_DECISÃO** | **9** |
| Soma de conferência | 122+17+0+26+2+9 = 176 ✓ |

**BLOQUEADO caiu de 49 para 0.** Todo caso que estava BLOQUEADO no relatório
da rodada 2 foi executado de verdade nesta rodada — nenhum ficou BLOQUEADO
só por falta de um teste pronto; onde a funcionalidade existia e o cenário
podia ser montado, ele foi montado e executado.

**P0 desta rodada:** 2 achados reabertos para revalidação (AUT-004, EST-009).
Ambos confirmados FALHOU por execução real e limpa **antes** de qualquer
correção, depois corrigidos numa migration nova e revalidados também por
execução real.

**1 achado novo:** AUT-007 (logout) — o token de acesso (JWT) continua
válido e aceito pelo backend mesmo depois de `/auth/v1/logout`, até expirar
naturalmente. Ver seção 4.

Nenhum resultado esperado foi alterado para fazer teste passar. Nenhum teste
que falhou foi apagado. Nenhuma correção de P1/P2 foi feita nesta rodada —
só os 2 achados P0 reabertos e explicitamente autorizados.

---

## 2. Migration nova desta rodada

`supabase/migrations/20260811170000_etapa3_correcoes.sql` +
`supabase/migrations/20260811170100_etapa3_fix_overload.sql` (a segunda
corrige um bug de sobrecarga de função introduzido pela primeira — descoberto
e corrigido na hora, por execução real, antes de prosseguir; ver seção 4.2).
Nenhuma migration antiga foi editada. Aplicadas com `npx supabase db push
--linked` (mesmo mecanismo usado na migration P0 da rodada 2).

Ambas confirmadas em `npx supabase migration list --linked`
(`local == remote` para as 18 migrations do projeto, incluindo as duas novas).

---

## 3. AUT-004 — usuário inativo (resultado final)

### Cenário limpo (conforme exigido: OS exclusiva, peça exclusiva, quantidade
nunca usada antes, operação permitida ao perfil original do usuário)

**Pré-fix — execução real, `docs/testing/_etapa3_prefix_output.txt`:**
- Peça nova `QA_PECA_AUT004_E03` (saldo 20, via NF de entrada real).
- OS interna nova, exclusiva, em `em_execucao`.
- `teste.inativo` (`profiles.ativo=false`, perfil real `executor`) chama
  `rpc_baixar_peca_os` com 3 unidades (operação nunca feita antes) →
  **HTTP 204 (sucesso)**.
- **AUT-004 = FALHOU CONFIRMADO** por execução real e limpa: `profiles.ativo`
  não tinha nenhum efeito sobre nenhuma operação do sistema.

### Correção

`current_perfil()` (helper central usado por `tem_perfil()` e por toda a RLS
do projeto) passou a retornar `NULL` também quando `profiles.ativo = false`,
não só quando não há sessão/perfil — mesma filosofia "fail closed" do fix
P0-01 da rodada anterior. Ver
`supabase/migrations/20260811170000_etapa3_correcoes.sql`.

### Pós-fix — os 4 cenários exigidos, execução real,
`docs/testing/_etapa3_posfix_p0_output.txt`

| Cenário | Usuário | Ação | Resultado | Classificação |
|---|---|---|---|---|
| `ativo=true` + perfil autorizado | `teste.executor` | `rpc_baixar_peca_os` 2un (op. nova) | HTTP 204, saldo 30→28 | **permitido, correto** |
| `ativo=false` + MESMO perfil | `teste.inativo` | `rpc_baixar_peca_os` 3un (op. nova, nunca feita) | HTTP 400 "Perfil sem permissão para baixar peça em OS" | **bloqueado, correto** |
| sem profile | `teste.semperfil` | `rpc_baixar_peca_os` 4un | HTTP 400, mesma mensagem | **bloqueado, correto** |
| anônimo | (sem token) | `rpc_baixar_peca_os` 5un | HTTP 400, mesma mensagem | **bloqueado, correto** |

Saldo final da peça confirmado via `SELECT`: 28 (só o cenário 1, o único
legítimo, afetou o estoque). Controle extra: `teste.inativo` ainda consegue
**ler** dados (`SELECT ordens_servico` → HTTP 200) — o fix é fail-closed para
*operações*, não bloqueia leitura básica, o que está alinhado ao escopo do
BR-028 (restrições de escrita/operação por perfil).

**AUT-004 = PASSOU (corrigido nesta rodada).** Migration:
`supabase/migrations/20260811170000_etapa3_correcoes.sql`.

---

## 4. EST-009 — idempotência real de baixa de estoque (resultado final)

### 4.1 Pré-fix: a janela de 5s não é idempotência persistente

Execução real, `docs/testing/_etapa3_prefix_output.txt`, peça exclusiva
`QA_PECA_EST009_E03` (saldo inicial 30), OS interna exclusiva:

| Passo | Ação | Resultado | Saldo após |
|---|---|---|---|
| (A) baixa original | `rpc_baixar_peca_os` 4un | HTTP 204 | 26 |
| (B) retry imediato | mesma chamada | HTTP 400 (bloqueado pela janela de 5s) | 26 |
| aguarda 6s | — | — | 26 |
| (C) retry após >5s, mesma operação lógica | mesma chamada | **HTTP 204 (sucesso — duplicou!)** | **22** |
| (D) retry imediato após (C) | mesma chamada | HTTP 400 (nova janela de 5s a partir de C) | 22 |

**EST-009 = NÃO CORRIGIDO DE FORMA COMPLETA, confirmado por execução real**:
o saldo caiu de novo no passo (C), depois de exatamente a mesma operação
lógica ser repetida passados mais de 5 segundos.

### 4.2 Correção: idempotency_key persistente

`estoque_movimentos` ganhou coluna `idempotency_key uuid` + unique index
parcial `(origem_tipo, origem_id, peca_id, tipo, idempotency_key) where
idempotency_key is not null`. `rpc_baixar_peca_os`/`rpc_registrar_saida_estoque`
ganharam parâmetro opcional `p_idempotency_key` (default `null`, portanto
retrocompatível). Quando informada, a mesma chave nunca gera uma 2ª linha —
**para sempre**, não só por 5 segundos. A trava `FOR UPDATE` já existente na
peça também serializa corretamente duas chamadas *simultâneas* com a mesma
chave. A janela de 5s antiga foi mantida como fallback best-effort só para
chamadas **sem** chave (compatibilidade com qualquer client mais antigo),
deixando de ser a única linha de defesa.

Durante a aplicação, a primeira versão da migration
(`20260811170000_etapa3_correcoes.sql`) causou um bug real detectado na hora
por execução (HTTP 300 `PGRST203`, "Could not choose the best candidate
function"): `CREATE OR REPLACE FUNCTION` com uma assinatura diferente (mais
um parâmetro) criou uma função sobrecarregada nova em vez de substituir a
antiga, e o PostgREST ficou sem saber qual chamar. Corrigido na mesma sessão
com uma segunda migration (`20260811170100_etapa3_fix_overload.sql`) que
remove explicitamente as assinaturas antigas antes de recriar. Evidência do
bug e da correção: `docs/testing/_etapa3_posfix_p0_output.txt` (1ª execução,
todas as chamadas retornam HTTP 300) vs. a mesma bateria reexecutada depois
do fix (2ª execução, todas OK).

### 4.3 Pós-fix — execução real, `docs/testing/_etapa3_posfix_p0_output.txt`

Peça exclusiva `QA_PECA_EST009_POSFIX2` (saldo inicial 40):

| Passo | Ação | Resultado | Saldo após |
|---|---|---|---|
| (A) baixa original, chave K1 | `rpc_baixar_peca_os` 5un + `p_idempotency_key=K1` | HTTP 204 | 35 |
| (B) retry imediato, mesma K1 | idem | HTTP 400 "Operação já processada" | 35 |
| aguarda 6s | — | — | 35 |
| (C) retry após >5s, mesma K1 | idem | **HTTP 400 — continua bloqueado** | 35 |
| (D) retry de novo, mesma K1 | idem | HTTP 400 | 35 |
| controle: operação NOVA, chave K2 diferente | 3un + `p_idempotency_key=K2` | HTTP 204 (legítima, não é duplicata) | 32 |
| concorrência: 2 chamadas SIMULTÂNEAS, mesma chave K3 | 2un cada, em paralelo (bash `&`+`wait`) | uma HTTP 204, outra HTTP 400 | 30 |

Confirmado via SQL direto: `select count(*) from estoque_movimentos where
idempotency_key in (K1, K3) group by idempotency_key` → **exatamente 1 linha
para cada chave**, mesmo com a chamada concorrente.

**EST-009 = PASSOU (corrigido nesta rodada, com mecanismo persistente real,
não mais dependente de janela temporal).** Migrations:
`supabase/migrations/20260811170000_etapa3_correcoes.sql` +
`20260811170100_etapa3_fix_overload.sql`.

---

## 5. OS-004 — orçamento após cancelamento de OS

Execução real nova (cenário exclusivo), `docs/testing/_etapa3_os004_doc006_output.txt`:

1. Orçamento aprovado (cliente/veículo externos b...0001/c...0001) →
   convertido em OS externa: **sucesso** (OS_ID `1acfd1a2...`).
2. Tentativa de reconverter o MESMO orçamento **enquanto a OS ainda está
   ativa**: bloqueado — "Este orçamento já foi convertido em uma OS ativa"
   (reconfirma o fix P0-03 da rodada 2, controle).
3. `rpc_transicionar_os` cancela a OS (`aberta → cancelada`): sucesso,
   confirmado via `SELECT` (`status: cancelada`).
4. **Tentativa de reconverter o MESMO orçamento agora que a OS está
   cancelada: HTTP 200, uma SEGUNDA OS é criada** (OS_ID `5c442ec3...`,
   status `aberta`). Confirmado via `SELECT ordens_servico where
   orcamento_id=...`: duas linhas — a cancelada e a nova.

### Comportamento real observado

O sistema **permite reconversão** do mesmo orçamento depois que a OS
originada dele é cancelada. O código implementa isso deliberadamente: o
check de duplicidade em `rpc_criar_os` é
`os.orcamento_id = p_orcamento_id and os.status <> 'cancelada'` — ou seja,
uma OS cancelada explicitamente **não** conta como "já convertido" para
efeito de bloqueio.

### Classificação: PENDENTE_DECISÃO (achado específico desta rodada, sem ID
próprio na matriz — o ID `OS-004` da matriz cobre o caso "conversão duplicada
enquanto a OS de origem ainda está ativa", que **continua PASSOU**, e não foi
alterado; o cenário pós-cancelamento é uma extensão pedida especificamente
para esta rodada)

`BUSINESS_RULES.md` (BR-008) diz apenas: *"O mesmo orçamento não pode gerar
OS duplicada de forma acidental."* Isso não define explicitamente o caso de
reconversão **intencional** após cancelamento formal. Duas alternativas de
negócio, ambas com riscos e vantagens reais:

- **(A) Permitir reconversão (comportamento atual)** — vantagem: se uma OS
  foi cancelada por engano operacional (ex.: cliente desistiu e depois
  voltou atrás, ou a OS foi cancelada por erro de digitação/duplicidade),
  o mesmo orçamento pode ser reaproveitado sem precisar recriar tudo do
  zero. Risco: um orçamento pode, em tese, gerar múltiplas OS ao longo do
  tempo (uma cancelada, outra ativa, outra cancelada, outra ativa...) sem
  nenhum limite, o que pode confundir auditoria/rastreabilidade se não
  houver disciplina operacional.
- **(B) Bloquear reconversão permanentemente** (mesmo com a OS cancelada) —
  vantagem: um orçamento "gasta" sua única conversão possível, forçando
  qualquer novo atendimento a passar por um orçamento novo (mais rastreável,
  sem ambiguidade sobre "qual OS é a definitiva" desse orçamento). Risco:
  cancelamentos operacionais legítimos (ex.: erro de OS interna x externa)
  forçariam sempre a criação de um orçamento novo do zero, mesmo quando o
  conteúdo é idêntico.

Nenhuma correção foi aplicada — o comportamento atual (A) foi apenas
registrado, com evidência de execução real, para decisão do dono do projeto.

---

## 6. DOC-006 — segurança por documento no Storage (modelo real confirmado)

Execução real nova, `docs/testing/_etapa3_os004_doc006_output.txt`: dois
documentos completamente não relacionados foram criados —
**Documento A** (upload por `teste.suporte`, ligado ao fluxo do orçamento
OS-004/cliente b...0001) e **Documento B** (upload por `teste.encarregado`,
sem NENHUMA relação com o Documento A ou seu fluxo).

| Quem lê | Qual documento | Participou do fluxo desse documento? | Resultado |
|---|---|---|---|
| `teste.encarregado` | Documento A (fez upload do B, nunca tocou no A) | Não | **HTTP 200 — leu o conteúdo completo** |
| `teste.suporte` | Documento B (fez upload do A, nunca tocou no B) | Não | **HTTP 200 — leu o conteúdo completo** |
| `teste.diretoria` | Documentos A e B (não participou de nenhum dos dois fluxos) | Não | **HTTP 200 nos dois** |
| `teste.executor` | Documento A | Não (perfil bloqueado por completo, fix P0-02) | Bloqueado (objeto não encontrado via RLS) |

### Conclusão: modelo **(A) — autorização somente por perfil**

Qualquer perfil diferente de `executor` lê **qualquer** documento do bucket
`comprovantes`, independentemente de ter algum vínculo com o registro
(orçamento/cobrança/OS) ao qual o documento pertence. Não existe policy que
restrinja por vínculo com a entidade — a policy real
(`comprovantes_select_gestao`, ver
`supabase/migrations/20260810160000_p0_correcoes_criticas.sql`) é
`bucket_id = 'comprovantes' and current_perfil() <> 'executor'`, sem nenhuma
referência a qual orçamento/cobrança o objeto pertence.

Isto é **consistente** com o resto do módulo financeiro do sistema —
`cobrancas`, `parcelas`, `recebimentos`, `termos_ciencia_debito` também usam
exatamente o mesmo critério (`current_perfil() <> 'executor'`, sem
granularidade por registro) — e é o mesmo critério que a rodada 2 já havia
corrigido deliberadamente como suficiente para o achado P0-02 (bloquear
`executor`). Por isso **DOC-006 permanece classificado PASSOU** (o achado
crítico original — executor lendo documentos financeiros — está corrigido e
confirmado de novo por execução real cruzada). Nenhuma mudança de regra foi
feita nesta rodada; o comportamento foi só investigado e documentado com
evidência real, como pedido. Fica registrado como oportunidade de
endurecimento P2 (granularidade por vínculo/entidade), não como regressão.

---

## 7. Casos que mudaram de BLOQUEADO → PASSOU nesta rodada (48)

Todos com execução real referenciada; dados/cenário e chamada específicos de
cada um estão detalhados na seção 9 (tabela completa) e nos arquivos brutos
`docs/testing/_etapa3_bloqueados_1_output.txt`,
`_etapa3_bloqueados_2_output.txt`, `_etapa3_bloqueados_3_output.txt`.

AUT-008, AUT-010, CAD-001, CAD-002, CAD-003, CAD-005, CAD-006, CAD-007,
CAD-008, CAD-009, CAD-011, ORC-002, ORC-003, ORC-006, ORC-015, APR-003,
APR-008, APR-009, APR-010, APR-011, OS-003, OS-008, OS-009, OS-011, EST-001,
EST-003, EST-012, EST-014, EXE-008, CON-004, CON-008, FIN-002, FIN-005,
FIN-007, FIN-008, FIN-009, LIB-007, LIB-008, GAR-006, AUD-005, PER-003,
PER-005, DOC-004, NFR-001, NFR-002, NFR-005, NFR-009, NFR-010.

## 8. Casos que mudaram de BLOQUEADO → FALHOU nesta rodada (1)

**AUT-007 — Logout.**

Execução real, `docs/testing/_etapa3_bloqueados_1_output.txt`:

1. `teste.executor` faz login (obtém `access_token` + `refresh_token`).
2. Lê `ordens_servico` com o `access_token` → HTTP 200 (confirma que a
   sessão funciona).
3. Chama `POST /auth/v1/logout?scope=global` → HTTP 204 (logout aceito).
4. Lê `ordens_servico` de novo, **com o MESMO `access_token` de antes do
   logout** → **HTTP 200 — a operação protegida continua permitida**.
5. Tenta usar o `refresh_token` antigo → HTTP 400
   `refresh_token_not_found` — **esse sim foi revogado**.

**Resultado: FALHOU.** O logout do Supabase Auth (GoTrue) revoga o
*refresh token*, mas **não** invalida o *access token* (JWT) já emitido —
ele continua sendo aceito pelo PostgREST/backend normalmente até expirar
pelo próprio prazo (TTL do token, tipicamente ~1h), mesmo depois do usuário
"deslogar". Isto é uma característica arquitetural do modelo de JWT
stateless do Supabase (o backend valida só assinatura + expiração, sem
consultar uma lista de revogação a cada chamada) — não é um bug introduzido
pelo código deste projeto, mas é um risco operacional real: um token
capturado (ex.: aba esquecida aberta, extensão maliciosa, log vazado)
continua utilizável mesmo depois que o usuário "sai" do sistema, até expirar
sozinho. Registrado como achado real, não mascarado. Está fora do escopo
desta rodada corrigir (não é um dos dois P0 pré-autorizados, e mitigar
isso — TTL de access token mais curto, ou checagem de revogação — é uma
mudança de infraestrutura de auth, não um bug pontual de RPC/RLS).

---

## 9. Tabela completa dos 49 casos ex-BLOQUEADO — dados, ação, resultado observado

### Autenticação
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| AUT-007 | login real de `teste.executor`, access+refresh token | ler dado protegido antes/depois de `/auth/v1/logout`, reusar refresh depois | access_token continua válido após logout (HTTP 200); refresh_token revogado (HTTP 400) | **FALHOU** |
| AUT-008 | `teste.executor` autenticado | `PATCH profiles?id=eq.<próprio id>` tentando `perfil=administrador_tecnico` | HTTP 403 RLS "new row violates row-level security policy"; perfil real inalterado (confirmado via SELECT) | **PASSOU** |
| AUT-010 | resposta de login de `teste.executor` | inspeção do corpo JSON completo da resposta | chaves: `access_token, expires_at, expires_in, refresh_token, token_type, user, weak_password`; string `Teste@2026` (senha) ausente da resposta | **PASSOU** |

### Cadastros
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| CAD-001 | cliente novo `TESTE_E03_Cliente_Externo_CAD001`, tipo=externo | `POST clientes` como encarregado | HTTP 201, `tipo:"externo"` persistido | **PASSOU** |
| CAD-002 | cliente novo `TESTE_E03_Cliente_Interno_CAD002`, tipo=interno | `POST clientes` | HTTP 201, `documento:null`, sem faturamento implícito | **PASSOU** |
| CAD-003 | payload sem `nome` | `POST clientes` | HTTP 400, `23502 null value in column "nome"` | **PASSOU** |
| CAD-005 | veículo `TSE0301` vinculado ao cliente CAD-001 | `POST veiculos` | HTTP 201 | **PASSOU** |
| CAD-006 | 2º veículo com a MESMA placa `TSE0301` | `POST veiculos` | HTTP 409, `23505 duplicate key ... uq_veiculos_placa_ativo` | **PASSOU** |
| CAD-007 | veículo sem `cliente_id` | `POST veiculos` | HTTP 400, `23502 null value in column "cliente_id"` | **PASSOU** |
| CAD-008 | cliente CAD-001 | `PATCH clientes` telefone/email | HTTP 200, dados atualizados | **PASSOU** |
| CAD-009 | cliente `b...0001` (6 OS reais vinculadas, incl. `f...0004` concluída) | `PATCH clientes set deleted_at=now()`, depois SELECT das OS | cliente marcado inativo; as 6 OS continuam consultáveis com status corretos; revertido ao final | **PASSOU** |
| CAD-011 | veículo `c...0001` (tem OS `f...0004` concluída, `cliente_id=b...0001`) | `PATCH veiculos set cliente_id=<cliente interno novo>` | veículo passa a apontar pro cliente novo; `ordens_servico.f...0004.cliente_id` **permanece** `b...0001` (não muda); revertido ao final | **PASSOU** |

### Orçamento
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| ORC-002 | payload sem `cliente_id` | `POST orcamentos` | HTTP 400, `23502 null value in column "cliente_id"` | **PASSOU** |
| ORC-003 | payload sem `veiculo_id` | `POST orcamentos` | HTTP 400, `23502 null value in column "veiculo_id"` | **PASSOU** |
| ORC-006 | item de `e...0001` (rascunho), qtd 1→5, R$100/un | `PATCH orcamento_itens.quantidade=5` | `valor_total` do item: 100→500 (trigger); `orcamentos.valor_total`: 100→500; revertido ao final | **PASSOU** |
| ORC-015 | orçamento novo, enviado, 1 item | `PATCH orcamento_itens` direto (bloqueado) vs. `rpc_criar_versao_orcamento` (caminho correto) | PATCH direto: HTTP 200 com `[]` (RLS filtrou, 0 linhas, valor inalterado); versão nova criada com sucesso (`versao=2`), original marcado `substituido` (preservado, não apagado) | **PASSOU** |

### Aprovação
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| APR-003 | orçamento novo, enviado | `rpc_rejeitar_orcamento` depois `rpc_criar_os` no mesmo orçamento | status vira `rejeitado`; conversão em OS bloqueada ("Orçamento precisa estar aprovado") | **PASSOU** |
| APR-008 | item de `e...0006` (aprovado), preço R$300 | `PATCH orcamento_itens.valor_unitario=9999` | HTTP 200 `[]` (0 linhas, RLS exige rascunho); preço inalterado | **PASSOU** |
| APR-009 | mesmo item | `PATCH orcamento_itens.quantidade=50` | HTTP 200 `[]`; quantidade inalterada | **PASSOU** |
| APR-010 | orçamento `e...0006` (aprovado) | `POST orcamento_itens` novo item | HTTP 403 RLS explícito ("new row violates row-level security policy") | **PASSOU** |
| APR-011 | orçamento `e...0006` (aprovado, com evidência) | `PATCH orcamentos` tentando `autorizado_por_nome=null, comprovante_path=null` | HTTP 403 "permission denied for table orcamentos" (GRANT de coluna não inclui esses campos); evidência de aprovação intacta | **PASSOU** |

### Ordem de Serviço
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| OS-003 | `e...0001` (rascunho) | `rpc_criar_os` com esse orçamento | HTTP 400 "Orçamento precisa estar aprovado para gerar OS"; nenhuma OS criada | **PASSOU** |
| OS-008 | OS interna nova, `aberta` | `rpc_transicionar_os` direto p/ `concluida` | HTTP 400 "Use a RPC específica ... (rpc_concluir_os / rpc_liberar_os)" | **PASSOU** |
| OS-009 | OS `em_diagnostico`; e separadamente `f...0006` (liberada) | `rpc_transicionar_os` tentando voltar p/ `em_execucao` em ambas | HTTP 400 "Transição concluida -> em_execucao não é permitida" / "Transição liberada -> em_execucao não é permitida" | **PASSOU** |
| OS-011 | OS interna nova, `aberta` | `rpc_transicionar_os` `aberta→em_diagnostico` 2x seguidas | 1ª: HTTP 204; 2ª: HTTP 400 "Transição em_diagnostico -> em_diagnostico não é permitida"; status final confirmado único, sem duplicar evento | **PASSOU** |

### Estoque
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| EST-001 | peça nova `QA_PECA_EST001_E03`, NF com 10un x R$25 | `rpc_confirmar_nf_entrada` | saldo 0→10; movimento `entrada`/`nf_entrada` com origem/custo corretos | **PASSOU** |
| EST-003 | item de NF com `valor_unitario=-10` | `POST nf_entrada_itens` | HTTP 400, `23514 check constraint "nf_entrada_itens_valor_unitario_check"` | **PASSOU** |
| EST-012 | peça EST-001 (custo R$25), 2ª entrada 10un x R$45 | `rpc_confirmar_nf_entrada` 2ª NF | `pecas.custo_medio`: 25→35 (média ponderada correta); movimento da 1ª entrada mantém `custo_unitario=25.00` inalterado | **PASSOU** |
| EST-014 | peça EST-001, 2 entradas (10+10) | soma de `estoque_movimentos.quantidade` vs `pecas.saldo_atual` | 10+10=20 = `saldo_atual` (20.000) — reconciliação exata | **PASSOU** |

### Execução
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| EXE-008 | item de orçamento `e...0001` (rascunho) | `teste.executor` faz `PATCH orcamento_itens.valor_unitario` | HTTP 200 `[]` (RLS exige perfil encarregado/administrador_tecnico); preço inalterado | **PASSOU** |

### Conclusão
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| CON-004 | OS nova, `aguardando_teste`, checklist NUNCA respondido | `rpc_concluir_os` | HTTP 400 "Existem itens obrigatórios do checklist pendentes"; status permanece `aguardando_teste` | **PASSOU** |
| CON-008 | mesma OS, depois de concluída de verdade | `rpc_concluir_os` de novo | HTTP 400 "Somente OS em Aguardando Teste podem ser concluídas" | **PASSOU** |

### Financeiro
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| FIN-002 | orçamento novo, enviado, rejeitado (item nunca aprovado) | `rpc_criar_os` no orçamento rejeitado | HTTP 400 "Orçamento precisa estar aprovado"; item nunca alcança OS/cobrança, logo nunca é cobrado (rejeição só existe no nível do orçamento inteiro, não por item — ver nota) | **PASSOU**¹ |
| FIN-005 | cobrança real de R$400 | `rpc_parcelar_cobranca` com 2 parcelas de R$100 (soma R$200 ≠ R$400) | HTTP 400 "Soma das parcelas (R$ 200.00) não confere com o valor da cobrança (R$ 400.00)"; nenhuma parcela criada | **PASSOU** |
| FIN-007 | OS nova, concluída agora mesmo | SELECT `cobranca_origens`/`ordens_servico` logo após concluir | nenhuma cobrança automática; status `concluida`, `data_liberacao=null` | **PASSOU** |
| FIN-008 | parcela de R$200 (2x formalizadas) | `rpc_registrar_recebimento` de R$80 (parcial) | parcela permanece `pendente` (não paga integralmente); cobrança vira `parcial`; saldo remanescente R$120 correto | **PASSOU** |
| FIN-009 | cobrança com recebimento parcial já registrado | `PATCH cobrancas.valor_total=1` | HTTP 403 "permission denied for table cobrancas"; valor inalterado | **PASSOU** |

¹ Nota: BR-006 (aprovação/rejeição por item) não está implementado — só existe
aprovar/rejeitar o orçamento inteiro (já registrado como achado em
ADC/APR-002 nas rodadas anteriores). FIN-002 passa no sentido estrito do seu
enunciado (item rejeitado não é cobrado), mas isso é garantido pela ausência
total de granularidade por item, não por uma lógica de exclusão seletiva.

### Liberação
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| LIB-007 | (1) tentativa de bypass direto de status; (2) fluxo real completo | (1) `PATCH ordens_servico.status='concluida'` direto; (2) fluxo `concluir→cobrar→parcelar→liberar` | (1) HTTP 403 "permission denied for table ordens_servico" — não existe via de escrita direta que burle o checklist; (2) CON-004 (mesma rodada) já confirma que `rpc_concluir_os` bloqueia com checklist pendente, então **não existe caminho na API atual para uma OS chegar a `concluida` com checklist obrigatório pendente** — a garantia está estruturalmente upstream | **PASSOU**² |
| LIB-008 | OS recém-liberada nesta rodada | `rpc_liberar_os` de novo na mesma OS | HTTP 400 "Somente OS concluída pode ser liberada" (já não é mais `concluida`, é `liberada`) | **PASSOU** |

² Nota: o cenário literal da matriz ("OS financeiramente elegível; checklist
pendente") pressupõe um estado (`concluida` com checklist incompleto) que a
arquitetura atual torna irrealizável — a única RPC que leva a `concluida`
(`rpc_concluir_os`) já barra isso antes. Testado e confirmado, não presumido.

### Garantia
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| GAR-006 | OS `f...0007` (liberada há 100 dias) | `PATCH ordens_servico.data_liberacao` p/ agora, como encarregado | HTTP 403 "permission denied for table ordens_servico"; `data_liberacao` inalterada (confirmado via SELECT) | **PASSOU** |

### Auditoria
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| AUD-005 | orçamento novo, aprovado, com evidência (`autorizado_por_nome`/`comprovante_path`) | `rpc_criar_versao_orcamento` | original marcado `substituido`, `autorizado_por_nome`/`comprovante_path` **preservados** (não apagados); nova versão (`versao=2`) criada em rascunho | **PASSOU** |

### Permissões
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| PER-003 | item de orçamento rascunho novo, R$10 | `teste.encarregado` `PATCH orcamento_itens.valor_unitario=25` | HTTP 200, alterado com sucesso (operação permitida ao perfil correto) | **PASSOU** |
| PER-005 | apontamento (`os_executores`) criado por `teste.encarregado` | `teste.executor` tenta `PATCH` no `id` desse apontamento (de outro usuário) via manipulação de ID | HTTP 200 `[]` (RLS `usuario_id = auth.uid()`, 0 linhas); observação original inalterada | **PASSOU** |

### Documentos
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| DOC-004 | fluxo completo novo (cliente/veículo/orçamento/OS exclusivos), termo de ciência registrado | `rpc_registrar_termo_ciencia` + `rpc_liberar_os`, depois SELECT `termos_ciencia_debito` | OS liberada; termo encontrado vinculado à `cobranca_id` correta, `arquivo_path` e `assinado_em` presentes | **PASSOU** |

### Não funcional
| ID | Dados/cenário | Ação | Resultado observado | Classificação |
|---|---|---|---|---|
| NFR-001 | contagem de `ordens_servico` antes/depois | `rpc_criar_os` forçado a falhar no meio (veículo incompatível com o orçamento) | exceção "OS externa exige veículo de cliente externo" (falha após parte das validações, antes do INSERT); contagem de OS idêntica antes/depois (31/31) — nenhuma OS parcial | **PASSOU**³ |
| NFR-002 | saldo da peça EST-001 antes/depois | `rpc_estornar_saida_estoque` com `movimento_id` inexistente | exceção "Movimento de saída ... não encontrado"; saldo inalterado (20.000 antes e depois) | **PASSOU** |
| NFR-005 | veículo `c...0001` pertence a cliente EXTERNO | `rpc_criar_os` com `p_tipo=interna` usando esse veículo | HTTP 400 "OS interna exige veículo da frota própria (cliente interno)" | **PASSOU** |
| NFR-009 | todos os corpos de resposta HTTP capturados nesta rodada (`_etapa3_*.txt`) | `grep` por `Teste@2026` (senha em claro) em todos os arquivos de evidência | 0 ocorrências em todos os arquivos | **PASSOU**⁴ |
| NFR-010 | caminho de objeto inexistente no bucket `comprovantes` | `GET /storage/v1/object/authenticated/.../arquivo-que-nao-existe...pdf` | HTTP 400 com corpo JSON limpo `{"statusCode":"404","error":"not_found","message":"Object not found","code":"NoSuchKey"}` — não é um erro 500 cru | **PASSOU** |

³ Nota de metodologia: a falha foi forçada por uma violação de regra de
negócio (parâmetro incompatível) que a própria função detecta e aborta via
`RAISE EXCEPTION` — não uma injeção de falha em baixo nível (ex.: kill de
conexão no meio da transação). Como cada RPC roda como uma única função
`plpgsql` (uma unidade transacional implícita do Postgres), qualquer exceção
levantada em qualquer ponto da função reverte automaticamente tudo que já
tinha sido feito nela — o teste comprova exatamente esse comportamento via
contagem antes/depois, não presume.

⁴ Nota: evidência limitada aos corpos de resposta HTTP observados
(coincide com o escopo de AUT-010). Não houve acesso ao dashboard/logs de
servidor do Supabase nesta rodada — não é possível confirmar 100% que
nenhum log interno da infraestrutura grava a senha; o que se confirma é que
nenhuma resposta de API observada, em nenhuma das ~200 chamadas reais feitas
nesta rodada, vazou a senha em claro.

---

## 10. Achados residuais (inalterados desta rodada)

Os achados FALHOU e NÃO_IMPLEMENTADO já documentados nas rodadas 1 e 2
continuam os mesmos (não foram reexecutados nem alterados nesta rodada, por
estarem fora do escopo — não são P0): módulo de Adicionais ausente,
aprovação parcial ausente, mecanismo de desconto ausente, sem trilha de
auditoria genérica para mudança de status/cancelamento de OS (AUD-001/002/
003), conversão de orçamento em OS não verifica/baixa estoque (EST-004,
E2E-003), sem constraint de unicidade em `clientes.documento` (CAD-004), sem
geração de PDF/relatório algum, `APR-004/005/006` sem campo distinto de
"meio" de aprovação, `CON-007` (apontamento editável após OS concluída).

**Novo achado desta rodada:** AUT-007 (logout não invalida access_token já
emitido) — ver seção 8.

---

## 11. Cobertura completa (176 casos) — apenas os IDs que mudaram nesta rodada

Todos os demais 123 IDs (que já tinham veredito de execução real ou de
código na rodada 2, e não fazem parte da lista de BLOQUEADO nem dos 4 itens
de revalidação) permanecem **exatamente como estão em
`docs/testing/TEST_REPORT_EXECUTION_02.md`** — não foram reexecutados nesta
rodada, não foram reclassificados, e esse relatório permanece intacto como
referência para eles.

| ID | Resultado rodada 2 | Resultado rodada 3 | Evidência rodada 3 |
|---|---|---|---|
| AUT-004 | FALHOU | **PASSOU [NEW]** (corrigido) | `_etapa3_prefix_output.txt`, `_etapa3_posfix_p0_output.txt` |
| AUT-007 | BLOQUEADO | **FALHOU [NEW]** | `_etapa3_bloqueados_1_output.txt` |
| AUT-008 | BLOQUEADO | **PASSOU [NEW]** | `_etapa3_bloqueados_1_output.txt` |
| AUT-010 | BLOQUEADO | **PASSOU [NEW]** | `_etapa3_bloqueados_1_output.txt` |
| CAD-001, CAD-002, CAD-003, CAD-005, CAD-006, CAD-007, CAD-008, CAD-009, CAD-011 | BLOQUEADO | **PASSOU [NEW]** (todos) | `_etapa3_bloqueados_1_output.txt` |
| ORC-002, ORC-003, ORC-006, ORC-015 | BLOQUEADO | **PASSOU [NEW]** (todos) | `_etapa3_bloqueados_1_output.txt` |
| APR-003, APR-008, APR-009, APR-010, APR-011 | BLOQUEADO | **PASSOU [NEW]** (todos) | `_etapa3_bloqueados_1_output.txt` |
| OS-003, OS-008, OS-009, OS-011 | BLOQUEADO | **PASSOU [NEW]** (todos) | `_etapa3_bloqueados_2_output.txt` |
| EST-001, EST-003, EST-012, EST-014 | BLOQUEADO | **PASSOU [NEW]** (todos) | `_etapa3_bloqueados_2_output.txt` |
| EXE-008 | BLOQUEADO | **PASSOU [NEW]** | `_etapa3_bloqueados_2_output.txt` |
| CON-004, CON-008 | BLOQUEADO | **PASSOU [NEW]** (ambos) | `_etapa3_bloqueados_2_output.txt` |
| FIN-002, FIN-005, FIN-007, FIN-008, FIN-009 | BLOQUEADO | **PASSOU [NEW]** (todos) | `_etapa3_bloqueados_3_output.txt` |
| LIB-007, LIB-008 | BLOQUEADO | **PASSOU [NEW]** (ambos) | `_etapa3_bloqueados_3_output.txt` |
| GAR-006 | BLOQUEADO | **PASSOU [NEW]** | `_etapa3_bloqueados_3_output.txt` |
| AUD-005 | BLOQUEADO | **PASSOU [NEW]** | `_etapa3_bloqueados_3_output.txt` |
| PER-003 | BLOQUEADO | **PASSOU [NEW]** | `_etapa3_bloqueados_3_output.txt` |
| PER-005 | BLOQUEADO | **PASSOU [NEW]** | `docs/testing/_etapa3_bloqueados_3_output.txt` + reteste dedicado (ver seção 9) |
| DOC-004 | BLOQUEADO | **PASSOU [NEW]** | `_etapa3_bloqueados_3_output.txt` |
| NFR-001, NFR-002, NFR-005, NFR-009, NFR-010 | BLOQUEADO | **PASSOU [NEW]** (todos) | `_etapa3_bloqueados_3_output.txt` |
| EST-009 | PASSOU (P0-04, incompleto) | **PASSOU [reforçado]** (mecanismo persistente) | `_etapa3_prefix_output.txt`, `_etapa3_posfix_p0_output.txt` |
| OS-004 | PASSOU | **PASSOU [inalterado]** + achado adicional PENDENTE_DECISÃO (pós-cancelamento) | `_etapa3_os004_doc006_output.txt` |
| DOC-006 | PASSOU | **PASSOU [confirmado, modelo A documentado]** | `_etapa3_os004_doc006_output.txt` |

---

## 12. Metodologia e ambiente

- Projeto Supabase confirmado antes de qualquer escrita: `npx supabase
  projects list` → só `jzjbiejmcaygwycvqggm` (`ACTIVE_HEALTHY`) linkado;
  `cedqaxmkffqrwfopgyze` (YNAB COVER) aparece na lista mas **não** foi
  usado em nenhum comando desta rodada.
- `npx supabase migration list --linked` confirmado local=remote em todas as
  18 migrations (16 anteriores + 2 novas desta rodada) antes de encerrar.
- Contagens de linhas antes/depois (evidência de que nada foi resetado
  destrutivamente, só criado): `clientes` 10→13 (+3), `veiculos` 8→10 (+2),
  `ordens_servico` 20→31 (+11), `orcamentos` 15→25 (+10), `cobrancas` 9→11
  (+2), `pecas` 7→14 (+7), `estoque_movimentos` 18→36 (+18). Todo dado novo
  usa nomes/SKUs/placas com o prefixo `TESTE_`/`QA_`/`TSE`/sufixo `_E03`,
  igual à convenção já estabelecida em `supabase/seed.sql`.
- Nenhum reset destrutivo geral do banco foi executado. `supabase/seed.sql`
  **não foi reexecutado** nesta rodada (os dados da rodada 2 continuam
  intactos e foram, inclusive, reaproveitados como pré-condição em vários
  casos desta rodada — ex.: CAD-009/011 usam `b...0001`/`c...0001` do seed).
  Duas alterações feitas **e revertidas ao final do mesmo teste** (não
  deixadas "sujas"): inativação temporária de `b...0001` (CAD-009) e troca
  temporária de vínculo de `c...0001` (CAD-011) — ambas confirmadas
  revertidas por `SELECT` no próprio script.
- Ferramentas: `curl` contra `/auth/v1/token`, `/rest/v1/rpc/*`,
  `/rest/v1/<tabela>` e `/storage/v1/object/*` com sessões reais de cada
  persona semeada (`Teste@2026!Qa`); `npx supabase db query --linked` para
  aplicar migrations, conferir contagens e checar `idempotency_key` no
  banco.
- Scripts novos e reproduzíveis, todos em `docs/testing/scripts/`:
  `etapa3_prefix_repro.sh`, `etapa3_posfix_p0.sh`, `etapa3_os004_doc006.sh`,
  `etapa3_bloqueados_1.sh`, `etapa3_bloqueados_2.sh`, `etapa3_bloqueados_3.sh`.
- Saídas brutas: `docs/testing/_etapa3_prefix_output.txt`,
  `_etapa3_posfix_p0_output.txt`, `_etapa3_os004_doc006_output.txt`,
  `_etapa3_bloqueados_1_output.txt`, `_etapa3_bloqueados_2_output.txt`,
  `_etapa3_bloqueados_3_output.txt`.

---

## 13. Arquivos gerados/alterados nesta rodada

- `supabase/migrations/20260811170000_etapa3_correcoes.sql` (fix AUT-004 +
  EST-009)
- `supabase/migrations/20260811170100_etapa3_fix_overload.sql` (corrige bug
  de sobrecarga de função introduzido pela migration acima, descoberto por
  execução real)
- `docs/testing/scripts/etapa3_prefix_repro.sh`,
  `etapa3_posfix_p0.sh`, `etapa3_os004_doc006.sh`,
  `etapa3_bloqueados_1.sh`, `etapa3_bloqueados_2.sh`, `etapa3_bloqueados_3.sh`
  (novos)
- `docs/testing/_etapa3_prefix_output.txt`, `_etapa3_posfix_p0_output.txt`,
  `_etapa3_os004_doc006_output.txt`, `_etapa3_bloqueados_1_output.txt`,
  `_etapa3_bloqueados_2_output.txt`, `_etapa3_bloqueados_3_output.txt`
  (evidência bruta desta rodada)
- `docs/testing/TEST_REPORT_EXECUTION_03.md` (este arquivo)
- `docs/testing/TEST_REPORT.md` e `docs/testing/TEST_REPORT_EXECUTION_02.md`
  — **preservados sem nenhuma alteração**, como baseline das rodadas
  anteriores.

---

## 14. Próximas ações priorizadas

1. **Decisão de negócio pendente: OS-004 pós-cancelamento** (seção 5) —
   decidir entre permitir ou bloquear reconversão de orçamento após
   cancelamento da OS gerada por ele.
2. **AUT-007 (logout não invalida access_token)** — decidir se vale a pena
   endurecer (ex.: reduzir TTL do access token, ou implementar checagem de
   revogação) dado o perfil de risco operacional da oficina, ou aceitar como
   comportamento padrão do Supabase Auth.
3. Os achados P1/P2 já conhecidos das rodadas 1 e 2 continuam a lista de
   próximos passos de implementação (módulo de Adicionais, aprovação
   parcial, desconto, trilha de auditoria de status/cancelamento, baixa de
   estoque vinculada à conversão, unicidade de `clientes.documento`, PDF/
   relatórios) — nenhum novo item crítico foi descoberto nesta rodada além
   dos dois já tratados (AUT-004, EST-009) e do achado novo AUT-007.
4. Endurecimento P2 opcional: granularidade por vínculo/entidade no bucket
   `comprovantes` (DOC-006, seção 6) — hoje qualquer perfil não-executor lê
   qualquer documento; não é um bug, mas pode ser refinado se o dono do
   projeto quiser um controle mais granular no futuro.
