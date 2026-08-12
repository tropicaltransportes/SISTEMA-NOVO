# Ambientes — DEV/QA vs PRODUÇÃO

Criado na ETAPA 7 (RC1 — Homologação Final), seção 20 do roteiro de
homologação. Define a separação entre o ambiente usado até aqui (todas as
etapas 1 a 7) e o ambiente de produção ainda não criado.

## Situação atual (na data deste documento)

Existe **um único** projeto Supabase para este sistema:

| | |
|---|---|
| **Nome** | SISTEMA NOVO |
| **Ref** | `jzjbiejmcaygwycvqggm` |
| **Organização** | `rttewrcwuqafozthelqu` |
| **Status** | ACTIVE_HEALTHY |
| **Papel** | **DEV/QA** — nunca foi, e não é, produção |

Este projeto **continua sendo DEV/QA** após a ETAPA 7. Nada nesta rodada o
transforma em produção. Ele contém:

- as 50 migrations do schema (reproduzidas do zero nesta rodada via
  `supabase db reset --linked`, ver `docs/testing/TEST_REPORT_RC1.md` seção
  7);
- massa de teste determinística (`supabase/seed.sql`) — usuários
  `*.qa.local`, clientes/veículos/peças/OS prefixados `TESTE_`/`QA_`;
  senha única de teste `Teste@2026!Qa`;
  dados adicionais criados por scripts de teste (`docs/testing/scripts/*.sh`)
  ao longo de 7 rodadas de homologação, sempre com prefixo `TESTE_`/`PGTAP`.

Existe também um segundo projeto na mesma organização, `cedqaxmkffqrwfopgyze`
("YNAB COVER"), **sem nenhuma relação com este sistema** — não usar para
nada relacionado ao ERP Oficina.

## O que PRODUÇÃO precisa ter, obrigatoriamente

1. **Projeto Supabase próprio**, separado do DEV/QA (`jzjbiejmcaygwycvqggm`
   nunca deve virar produção — criar um projeto novo).
2. **Secrets próprios**: nova `anon key` e `service_role key`, nunca as
   mesmas usadas em DEV/QA. Nenhuma chave de DEV/QA deve estar em qualquer
   config de produção.
3. **Mesmas 50 migrations**, aplicadas na mesma ordem, sem alteração —
   migrations antigas nunca são editadas neste projeto (regra já em vigor);
   produção deve estar sempre em paridade de schema com o que foi
   homologado.
4. **Nenhuma massa de teste**: `supabase/seed.sql` **não** deve ser aplicado
   em produção. Nenhum usuário `*.qa.local`, nenhum registro `TESTE_`/`QA_`/
   `PGTAP`.
5. **Usuários reais**: pelo menos 1 administrador técnico real, criado
   manualmente (ver `docs/PRODUCTION_READINESS_CHECKLIST.md`), com senha
   forte própria — nunca `Teste@2026!Qa`.
6. **Configuração administrativa inicial preenchida de verdade**
   (`custo_hora_config`, `desconto_config`/teto de desconto,
   `anexos_config`, centros de custo reais) — os valores usados em QA são
   fixtures de teste, não representam a operação real da Tropical
   Transportes.
7. **Storage**: os buckets `comprovantes` e `os-fotos` recriados (as
   migrations já criam os buckets — confirmar que a migration de criação
   dos buckets roda em produção também) com as mesmas policies validadas
   nesta rodada (ver seção 11 de `docs/testing/TEST_REPORT_RC1.md`).
8. **Frontend apontando para o projeto de produção** — `VITE_SUPABASE_URL`/
   `VITE_SUPABASE_ANON_KEY` (ou equivalentes) de produção, nunca os de
   DEV/QA, e vice-versa (o frontend de DEV/QA nunca deve apontar para
   produção).
9. **HTTPS/domínio próprio**, rewrite de SPA configurado (ver seção 18 de
   `docs/testing/TEST_REPORT_RC1.md` — refresh em rota interna precisa
   continuar funcionando).
10. **Backup e restore documentados e testados** — ver
    `docs/PRODUCTION_BACKUP_RESTORE.md`.

## Regra permanente

- DEV/QA (`jzjbiejmcaygwycvqggm`) é o único ambiente onde é permitido rodar
  testes destrutivos, resets, massa de teste e scripts de homologação.
- PRODUÇÃO nunca recebe: `supabase/seed.sql`, scripts de
  `docs/testing/scripts/`, usuários `*.qa.local`, ou qualquer comando `db
  reset`.
- Migrations fluem sempre **DEV/QA → homologadas → produção**, nunca ao
  contrário, e nunca é criada uma migration só para produção.
- Ao criar o projeto de produção, seguir exatamente
  `docs/PRODUCTION_READINESS_CHECKLIST.md` antes de liberar acesso a
  usuários reais.
