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
- [x] Política de exclusão de arquivos — **decisão formal registrada**
      (ETAPA 8/RC2, `docs/testing/BUSINESS_RULES.md` BR-043): arquivos
      operacionais (comprovantes, fotos de OS) não devem ser apagados
      fisicamente por nenhum perfil, nem administrador. Confirmado que
      nenhuma migration cria policy de DELETE em `storage.objects` para os
      dois buckets — nada a fazer para produção herdar o mesmo
      comportamento, só confirmar que a policy continua ausente após
      qualquer migration futura.
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
      não os fixtures de teste usados em QA. **Verificar com
      `rpc_status_configuracao_sistema()`** (ETAPA 8/RC2, seção 2; tela
      "Configuração Inicial" no menu administrativo do frontend) — todos os
      6 itens devem aparecer CONFIGURADO antes de liberar acesso a usuários
      reais. Causa raiz conhecida (não corrigir por migration, é
      comportamento esperado): a migration
      `20260814110000_p1c_config_administrativa.sql` tenta semear
      `desconto_config`/`anexos_config` mas o `insert...select` depende de
      já existir um `administrador_tecnico` em `profiles`, o que nunca é
      verdade no momento em que as migrations rodam (o admin é criado
      DEPOIS, manualmente) — então essas duas linhas nascem vazias em toda
      instalação limpa, produção incluída. Configurar manualmente via
      `rpc_definir_custo_hora`/`rpc_definir_teto_desconto`/
      `rpc_definir_anexos_config`/`rpc_criar_centro_custo` como o admin
      inicial, e reconferir com `rpc_status_configuracao_sistema()`.
- [ ] Logs verificados — confirmar que os logs do Supabase (Auth, API,
      Postgres) estão acessíveis e sendo observados após o go-live
- [x] URLs/SPA — **não aplicável hoje.** Confirmado na ETAPA 8 (RC2), seção
      3 (`frontend/src/router/index.js`, `createWebHashHistory`): o
      roteamento é hash-based (`#/os/:id`), então o navegador sempre pede só
      `index.html` ao servidor — refresh/deep-link em qualquer rota interna
      funciona em qualquer hospedagem estática, sem nenhuma regra de rewrite
      de servidor. **Enquanto o frontend utilizar hash routing, não é
      necessário SPA rewrite. Se futuramente migrar para history routing,
      revisar esta decisão.**
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
