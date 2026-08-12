# Checklist de Produção — ERP Oficina (Tropical Transportes)

Criado na ETAPA 7 (RC1), seção 21 do roteiro de homologação final. Nenhum
item abaixo foi marcado apenas por suposição — os itens já cobertos por
evidência real desta rodada estão anotados; os demais são ações que só
fazem sentido quando o projeto de produção for criado de fato (fora do
escopo desta rodada, que é só de homologação).

## Infraestrutura Supabase

- [ ] Projeto Supabase de **produção** criado (separado de
      `jzjbiejmcaygwycvqggm`, que continua DEV/QA — ver `docs/ENVIRONMENTS.md`)
- [ ] Migrations aplicadas — as mesmas 50 migrations homologadas nesta
      rodada, na mesma ordem, sem edição (`npx supabase db push --linked`
      contra o projeto de produção; confirmar `migration list --linked`
      local == remote)
- [ ] RLS validada em produção — reaplicar pelo menos os testes das seções
      9/10 de `docs/testing/TEST_REPORT_RC1.md` (segurança final + anon
      global) contra o projeto de produção antes de liberar acesso
- [ ] Storage policies validadas em produção — reaplicar os testes da
      seção 11 de `docs/testing/TEST_REPORT_RC1.md` (buckets `comprovantes`
      e `os-fotos`, ambos privados)
- [ ] Usuários QA ausentes — nenhum `*.qa.local`, nenhum `Teste@2026!Qa`
- [ ] Seed QA **não** aplicado (`supabase/seed.sql` é só para DEV/QA —
      nunca rodar contra produção)
- [ ] Secrets de produção configurados — `anon key`/`service_role key`
      próprios do projeto de produção, nunca reaproveitados de DEV/QA
- [ ] Frontend apontando para produção — variáveis de ambiente
      (`VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` ou equivalentes) do
      build de produção configuradas para o projeto de produção

## Continuidade operacional

- [ ] Backup configurado — confirmar retenção/frequência do backup
      automático do plano contratado + procedimento de backup lógico
      documentado em `docs/PRODUCTION_BACKUP_RESTORE.md`
- [ ] Restore documentado — `docs/PRODUCTION_BACKUP_RESTORE.md` revisado
      pelo responsável técnico antes do go-live (restore real ainda não
      testado em produção, só o mecanismo de rebuild via migrations, ver
      seção 7 do relatório RC1)

## Validação pré-go-live

- [ ] Smoke test em produção — login com o admin inicial + 1 fluxo mínimo
      (criar cliente → veículo → orçamento) executado manualmente contra o
      projeto de produção antes de liberar para usuários reais
- [ ] Admin inicial criado — pelo menos 1 usuário `administrador_tecnico`
      real (nome e credenciais reais da Tropical Transportes, não
      `Teste_Administrador_Tecnico`), criado manualmente via Supabase
      Studio/Auth do projeto de produção
- [ ] Configurações de negócio preenchidas — `custo_hora_config`,
      `desconto_config` (teto de desconto), `anexos_config` (tamanho
      máximo/MIME permitido de anexos), centros de custo reais, checklist
      templates reais — todos configurados com valores reais da operação,
      não os fixtures de teste usados em QA
- [ ] Logs verificados — confirmar que os logs do Supabase (Auth, API,
      Postgres) estão acessíveis e sendo observados após o go-live
- [ ] URLs/SPA configuradas — rewrite de servidor para SPA configurado no
      host de produção do frontend (ver seção 18 de
      `docs/testing/TEST_REPORT_RC1.md` — F5 em rota interna como
      `/os/:id` precisa continuar funcionando; documentar se o host de
      produção precisa de configuração explícita de rewrite, o que depende
      de qual hospedagem for escolhida)
- [ ] HTTPS habilitado no domínio de produção
- [ ] Domínio próprio configurado (em vez do domínio padrão do provedor de
      hospedagem do frontend, se aplicável)
- [ ] AUT-007 aceito/documentado — risco aceito de revogação de sessão via
      JWT stateless do Supabase (não corrigido por decisão de escopo, ver
      `docs/testing/BUSINESS_RULES.md` BR-040 Decisão #3 e
      `docs/testing/TEST_REPORT_P1A.md` seção 3.3); confirmar que o
      responsável pela operação está ciente de que revogar acesso de um
      usuário desligado exige desativar o perfil **e** aguardar a expiração
      natural do token (ou usar `service_role` para invalidar sessões, se
      necessário) — não existe revogação instantânea

## Observação sobre o estado desta rodada

Nenhum item deste checklist foi executado de fato nesta rodada — o objetivo
da ETAPA 7 foi provar que **DEV/QA** (`jzjbiejmcaygwycvqggm`) pode ser
reconstruído com segurança e que a suíte de testes cobre o sistema de forma
confiável, não criar produção. A criação do ambiente de produção em si é
uma decisão e uma ação que ficam para depois desta homologação, seguindo
este checklist.
