# Backup, Restore, Migration e Rollback Operacional — Produção

Criado na ETAPA 7 (RC1), seção 19 do roteiro de homologação final. Documenta
o procedimento; **não foi executada nenhuma restauração destrutiva** contra
`jzjbiejmcaygwycvqggm` como parte deste documento (o rebuild controlado
executado na seção 7 usou `db reset --linked`, um mecanismo diferente —
"reconstruir do zero pelas migrations", não "restaurar um backup").

## 1. Backup

O Supabase gerencia backups automáticos do Postgres por trás do projeto
(frequência e retenção dependem do plano contratado — confirmar no painel
do projeto de produção assim que criado, em *Database → Backups*). Isso
cobre desastre de infraestrutura, mas **não substitui** um backup lógico
próprio para os cenários abaixo, que são operacionais, não de
infraestrutura:

- erro humano (RPC/migration com bug que corrompe dados em produção);
- necessidade de auditoria/exportação pontual;
- necessidade de restaurar em um projeto separado para investigação, sem
  tocar produção.

### Backup lógico recomendado (fora do escopo desta rodada implementar —
### documentado para quando produção existir)

```bash
# Dump completo (schema + dados) do projeto de produção, usando a connection
# string do próprio projeto (Settings → Database → Connection string):
npx supabase db dump --db-url "<connection-string-producao>" -f backup_$(date +%Y%m%d_%H%M%S).sql

# Ou, com pg_dump diretamente (mesma connection string):
pg_dump "<connection-string-producao>" -F c -f backup_$(date +%Y%m%d_%H%M%S).dump
```

Frequência sugerida: diária, retida por pelo menos 30 dias, armazenada fora
do Supabase (ex.: bucket separado, storage externo) — nunca só no mesmo
projeto que se está protegendo.

## 2. Restore

Dois cenários distintos:

### 2a. Restaurar um backup lógico (recuperar de erro operacional)

```bash
# NUNCA rodar contra produção sem confirmar 3x o project-ref/connection
# string (mesma disciplina usada nesta rodada para o reset de QA — ver
# seção 7 de docs/testing/TEST_REPORT_RC1.md).
psql "<connection-string-destino>" -f backup_YYYYMMDD_HHMMSS.sql
# ou, para dump em formato custom:
pg_restore -d "<connection-string-destino>" backup_YYYYMMDD_HHMMSS.dump
```

Sempre restaurar primeiro num projeto Supabase **separado** (nunca direto em
produção) para validar o backup antes de qualquer decisão de substituir
dados reais.

### 2b. Reconstruir o schema do zero a partir das migrations (o mecanismo
### provado nesta rodada)

Esse é o procedimento que a ETAPA 7 realmente executou e comprovou
funcionar sem depender de estado acumulado (ver
`docs/testing/TEST_REPORT_RC1.md`, seção 7):

```bash
npx supabase link --project-ref <ref-do-projeto-alvo>
npx supabase db reset --linked   # dropa, recria, aplica as 50 migrations em ordem
```

Isso reconstrói o **schema e as RPCs**, não os dados de produção — usar
apenas em: (a) DEV/QA, para provar reprodutibilidade (como aqui); (b) um
projeto de produção **recém-criado, ainda vazio**, como primeiro passo antes
de criar o admin inicial (ver `docs/PRODUCTION_READINESS_CHECKLIST.md`).
**Nunca** rodar `db reset --linked` num projeto de produção que já tem dados
reais — isso apaga tudo. Se o projeto linkado no momento não for
inequivocamente o de produção-vazia-recém-criada, parar e não executar.

## 3. Migration (produção em dia com o schema homologado)

```bash
npx supabase link --project-ref <ref-do-projeto-producao>
npx supabase migration list --linked   # confirma o que falta aplicar
npx supabase db push --linked          # aplica só as migrations pendentes, em ordem
npx supabase migration list --linked   # confirma local == remote depois
```

Regra permanente do projeto (já em vigor, mantida): migrations antigas
nunca são editadas; correção de bug em produção é sempre uma migration nova,
nunca uma alteração retroativa.

## 4. Rollback operacional

Este projeto **não usa migrations de rollback automático** (não há
`down.sql` por migration). Rollback de uma migration com problema é sempre
uma **migration corretiva nova**, seguindo a mesma regra usada durante toda
a homologação (ex.: `20260814111100_p1c_fix_ordem_ramos_baixa_garantia.sql`,
`20260815120000_rc1_fix_overload_orfao_termo_ciencia.sql`) — nunca editar a
migration com o bug.

Passo a passo para um incidente em produção:

1. Identificar exatamente o `CREATE OR REPLACE FUNCTION`/DDL problemático.
2. Escrever uma migration nova (timestamp maior que a última aplicada) que
   reverte ou corrige o comportamento — reaplicando a versão anterior da
   função, ou uma versão corrigida.
3. Testar a migration corretiva em DEV/QA primeiro (`jzjbiejmcaygwycvqggm`),
   com um teste de regressão pgTAP cobrindo o bug (mesma regra do
   `CLAUDE.md`, seção 3).
4. Só então aplicar em produção com `db push --linked`.
5. Se o incidente envolveu perda/corrupção de **dados** (não só de
   comportamento de função), avaliar restore de backup lógico (seção 2a)
   para o período afetado, em vez de tentar corrigir dado por dado.

## 5. O que esta rodada comprovou de verdade (não é só teoria)

- As 50 migrations aplicam do zero, em ordem, sem depender de estado
  acumulado de rodadas anteriores (`db reset --linked` executado com
  sucesso após 1 correção real — ver seção 7 do relatório RC1).
- `supabase/seed.sql` roda de forma determinística após as migrations
  (com a correção de schema-qualificação do `pgcrypto` feita nesta rodada).
- A suíte pgTAP completa (6 arquivos, 44 assertions) roda limpa
  imediatamente após o rebuild, sem ajuste manual além da correção de
  assinatura já documentada.

O que esta rodada **não** testou (fica pendente para quando produção
existir): restore de um backup lógico real, e falha simulada de rede/timeout
durante uma migration em andamento.
