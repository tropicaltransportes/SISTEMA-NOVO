-- Habilita a extensão pgTAP, necessária para executar supabase/tests/*.sql
-- contra este ambiente (agora autorizado como dev/teste — ver
-- docs/testing/TEST_REPORT_EXECUTION_02.md). Não é alteração de regra de
-- negócio, só infraestrutura de teste.
create extension if not exists pgtap with schema extensions;
