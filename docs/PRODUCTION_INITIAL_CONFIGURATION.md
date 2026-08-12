# Configuração Inicial de Produção — ERP Oficina (Tropical Transportes)

Criado na ETAPA 8 (RC2 — Certificação Pré-Produção), seção 8 do roteiro.
Este documento **não contém nenhum valor real** — nenhum valor de negócio
foi fornecido pelo dono do projeto até o momento da criação deste
documento, e nenhum valor foi inventado para preenchê-lo (proibido nesta
rodada, e proibido em geral: ver `docs/testing/BUSINESS_RULES.md`,
comentário da migration `20260816130000_rc2_status_configuracao_sistema.sql`
e `docs/PRODUCTION_READINESS_CHECKLIST.md`). É uma lista do que o
administrador técnico da Tropical Transportes deve informar/decidir antes
e depois do go-live, e como cada item é verificado.

Use `rpc_status_configuracao_sistema()` (tela **Configuração Inicial** no
menu administrativo do frontend, `#/admin/status-configuracao`) para
confirmar o estado real de cada item abaixo marcado como verificável por
ela — ela nunca inventa valor, só relata o que já existe no banco.

---

## OBRIGATÓRIO ANTES DO GO-LIVE

Sem estes itens, fluxos inteiros do sistema ficam bloqueados ou operam com
valores que não representam a operação real da Tropical Transportes.

### 1. Administrador técnico inicial
- **O que informar:** nome real e e-mail real de pelo menos 1 pessoa que
  será `administrador_tecnico`. Credenciais reais, senha forte própria —
  nunca `Teste@2026!Qa` nem qualquer senha usada em QA.
- **Como aplicar:** criado manualmente via Supabase Studio/Auth do projeto
  de **produção** (não existe RPC de auto-cadastro de administrador — decisão
  de segurança já em vigor). Depois de criado o usuário em `auth.users`, o
  perfil correspondente em `public.profiles` deve ser promovido para
  `administrador_tecnico` (por padrão todo novo usuário nasce `executor`).
- **Verificação:** item `administrador_tecnico` de
  `rpc_status_configuracao_sistema()` = CONFIGURADO.

### 2. Custo/hora interno (`custo_hora_config`)
- **O que informar:**
  - **Valor** (R$/hora) do custo interno de mão de obra, usado para
    calcular `custo_mao_obra`/`custo_total` de OS internas (cliente interno
    — frota própria, sem cobrança, ver BUSINESS_RULES.md Decisão 2).
  - **Vigência** — a partir de quando esse valor passa a valer (o registro
    é append-only/histórico; o valor vigente é sempre o mais recente com
    `vigente_desde <= now()`; alterar no futuro nunca recalcula OS já
    encerrada — é snapshot).
- **Como aplicar:** `rpc_definir_custo_hora(p_valor_hora)`, só
  `administrador_tecnico`.
- **Verificação:** item `custo_hora_config` de
  `rpc_status_configuracao_sistema()` = CONFIGURADO (mostra o valor
  vigente).

### 3. Desconto (`desconto_config`)
- **O que informar:**
  - **Habilitado** (sim/não) — se desconto pode ser concedido.
  - **Teto percentual máximo** permitido por perfil autorizado
    (encarregado/administrador_tecnico), ver BUSINESS_RULES.md Decisão 7.
  - Separadamente, se a diretoria decidir usar **faixas de acréscimo
    pós-orçamento** (tela "Faixas de Acréscimo", perfil
    administrador_tecnico), os valores reais de `valor_min`/`valor_max`/
    `percentual_max` por faixa — hoje **nenhuma faixa real está
    cadastrada** (pendência já registrada em
    `frontend/src/views/admin/FaixasAcrescimoList.vue`: "Pendência da
    diretoria: valores reais ainda não definidos").
- **Como aplicar:** `rpc_definir_teto_desconto(p_habilitado, p_percentual_maximo)`,
  só `administrador_tecnico`. Faixas de acréscimo: tela
  `#/admin/faixas-acrescimo`.
- **Verificação:** item `desconto_config` de
  `rpc_status_configuracao_sistema()` = CONFIGURADO.

### 4. Anexos (`anexos_config`) — fotos de OS e comprovantes
- **O que informar:**
  - **Tamanho máximo** (bytes) por arquivo enviado.
  - **MIMEs permitidos** (lista — ex.: `image/jpeg`, `image/png`,
    `application/pdf`). Definem o que passa na validação de
    `rpc_registrar_foto_os` e de qualquer fluxo que exija comprovante.
- **Como aplicar:** `rpc_definir_anexos_config(p_tamanho_maximo_bytes, p_mime_permitidos)`,
  só `administrador_tecnico`.
- **Verificação:** item `anexos_config` de
  `rpc_status_configuracao_sistema()` = CONFIGURADO. **Atenção**: causa raiz
  conhecida (ver comentário de
  `supabase/migrations/20260816130000_rc2_status_configuracao_sistema.sql`)
  — isso nasce **sempre vazio** em qualquer instalação limpa, produção
  incluída, porque o `insert` de bootstrap de uma migration anterior
  depende de um `administrador_tecnico` que só existe depois (item 1 acima).
  Sem isso configurado, **upload de fotos/comprovantes fica bloqueado** com
  o erro "Configuração de anexos não definida — contate o administrador
  técnico".

### 5. Centros de custo (`centro_custo`)
- **O que informar:** os centros de custo reais da operação (ex.: nomes de
  filiais/setores/frotas conforme a estrutura real da Tropical
  Transportes) — a estrutura é livre, sem departamentos hardcoded (ver
  BUSINESS_RULES.md Decisão 1/item 10).
- **Como aplicar:** `rpc_criar_centro_custo(p_nome)` — qualquer
  encarregado/suporte_administrativo/administrador_tecnico pode cadastrar.
- **Verificação:** item `centro_custo` de
  `rpc_status_configuracao_sistema()` = CONFIGURADO (ao menos 1 ativo).

### 6. Checklists (templates)
- **O que informar:**
  - **Templates de checklist** reais (nome, itens, obrigatoriedade de cada
    item) para os tipos de serviço praticados pela oficina.
  - Para cada template: **foto antes obrigatória?** (sim/não) e **foto
    depois obrigatória?** (sim/não) — nunca uma obrigatoriedade global, é
    por template (BUSINESS_RULES.md BR-019/BR-020).
- **Como aplicar:** tela `#/admin/checklist`
  (`ChecklistTemplatesList.vue`), perfis encarregado/administrador_tecnico.
- **Verificação:** item `checklist_template` de
  `rpc_status_configuracao_sistema()` = CONFIGURADO (ao menos 1 ativo).

### 7. Storage — buckets e policies
- Os buckets `comprovantes` e `os-fotos` são criados pelas próprias
  migrations (não é configuração manual) — confirmar, ao aplicar as
  migrations em produção, que ambos existem e continuam **privados**, com
  as mesmas policies de SELECT/INSERT validadas em QA (RC1, seção 11) e
  **sem policy de DELETE** (decisão formal, ver BUSINESS_RULES.md BR-043 e
  seção 4 deste roteiro).

### 8. Secrets e apontamento do frontend
- `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` do build de produção
  apontando para o projeto de produção (nunca para
  `jzjbiejmcaygwycvqggm`), ver `docs/ENVIRONMENTS.md`.

---

## PODE SER CONFIGURADO DEPOIS DO GO-LIVE

Itens que têm um comportamento seguro por padrão (bloqueiam a ação
específica em vez de operar com valor incorreto) e podem ser ajustados
depois, sem impedir o início da operação nos fluxos que não dependem deles:

- **Faixas de acréscimo pós-orçamento** (`orcamento_faixa_acrescimo`) — se
  nenhuma faixa cobre o valor de um orçamento, a RPC de acréscimo bloqueia
  o lançamento (comportamento seguro por padrão, já documentado na própria
  tela); o teto absoluto fixo de R$ 5.000,00 sempre se aplica independente
  de faixa. Pode ser cadastrado a qualquer momento pela diretoria sem
  migration.
- **Centros de custo e checklist templates adicionais** — os itens 5/6
  acima exigem só **1** de cada para sair de PENDENTE; templates/centros
  adicionais para outros tipos de serviço podem ser cadastrados
  progressivamente conforme a operação exigir.
- **Ajuste fino de custo/hora e teto de desconto** — são histórico
  (append-only, nunca UPDATE); o valor inicial pode ser revisado a
  qualquer momento criando um novo registro vigente, sem afetar OS já
  encerradas (snapshot).
- **Ajuste de `anexos_config`** (tamanho/MIME) — pode ser afrouxado ou
  restringido depois, também é histórico.

## O que NÃO é configuração de negócio (não entra nesta lista)

Migrations, RLS, Storage buckets/policies, e todas as RPCs já fazem parte
do schema homologado e são aplicadas via `npx supabase db push --linked`
contra o projeto de produção — não são "configuração inicial" no sentido
deste documento, são o próprio sistema. Ver
`docs/PRODUCTION_READINESS_CHECKLIST.md` para o checklist completo de
infraestrutura.
