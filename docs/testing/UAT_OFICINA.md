# UAT (Teste de Aceitação do Usuário) — Oficina Tropical Transportes

Criado na ETAPA PROD-01 (2026-08-13), seções 18/19 do roteiro. Cenários
mínimos em linguagem operacional (não técnica), prontos para serem
executados pelos usuários piloto reais assim que existirem — encarregado,
suporte administrativo e pelo menos 1 executor da oficina, cujos
nomes/e-mails reais o dono do projeto ainda não forneceu nesta rodada.

**Este documento NÃO contém nenhum resultado de PASSOU/FALHOU preenchido.**
O UAT ainda não foi executado com usuários reais — só o smoke técnico
(seção SMOKE de `docs/testing/TEST_REPORT_PROD01.md`), que usou contas de
teste descartáveis, não usuários piloto reais da oficina.

## Como usar este documento

Cada cenário abaixo deve ser executado por uma pessoa real da oficina,
usando o sistema pela interface normal (não API direta), com dados
claramente identificados como teste (sugestão: prefixo `UAT_` nos nomes de
cliente/veículo, para poder localizar e limpar depois se necessário).
Preencher a coluna **Resultado** com PASSOU, FALHOU ou BLOQUEADO, e
**Observação** com qualquer divergência do esperado.

## Pré-requisito

- Administrador técnico real (Hammed) precisa ter aceitado o convite e
  definido senha própria.
- Pelo menos 1 usuário piloto de cada perfil operacional (encarregado,
  suporte administrativo, executor) precisa existir em produção — pendência
  explícita desta rodada, ver `docs/testing/TEST_REPORT_PROD01.md` seção
  UAT.
- URL de acesso: `https://tropicaltransportes.github.io/SISTEMA-NOVO/#/login`
  (só funciona depois que o frontend de produção for publicado — ver seção
  DEPLOY do relatório).

## Cenários

| # | Perfil | Cenário | Passos (visão do usuário) | Resultado esperado | Resultado | Observação |
|---|---|---|---|---|---|---|
| 1 | Encarregado | Login | Acessar a URL do sistema, entrar com e-mail e senha reais | Entra no painel, vê o menu correspondente ao seu perfil | | |
| 2 | Encarregado | Cadastrar cliente novo | Cadastrar um cliente externo de teste (`UAT_Cliente`) com nome e documento | Cliente aparece na lista, documento validado | | |
| 3 | Encarregado | Cadastrar veículo | Vincular um veículo (`UAT_Veiculo`, placa de teste) ao cliente do passo 2 | Veículo aparece no histórico do cliente | | |
| 4 | Encarregado | Criar orçamento | Montar um orçamento com pelo menos 1 peça e 1 serviço, valores de teste | Orçamento salvo como rascunho, valores corretos | | |
| 5 | Encarregado | Enviar orçamento | Enviar o orçamento para aprovação | Status muda para "enviado" | | |
| 6 | Encarregado/Suporte | Registrar aprovação do cliente | Registrar que o cliente aprovou (sistema, e-mail, ou verbal documentado) | Item(ns) marcados como aprovados, orçamento muda de status | | |
| 7 | Encarregado | Converter em OS | Converter o orçamento aprovado em Ordem de Serviço | OS criada, vinculada ao orçamento | | |
| 8 | Executor | Ver minhas OS | Logar como executor e ver as OS em que está atuando | Só vê as OS em que foi designado | | |
| 9 | Executor | Apontar execução / baixar peça | Registrar horas trabalhadas e dar baixa numa peça do orçamento | Estoque reduz corretamente, apontamento salvo | | |
| 10 | Executor | Enviar foto da OS | Anexar 1 foto (antes ou depois) na OS | Foto aparece na OS, tamanho/tipo aceitos conforme configuração | | |
| 11 | Encarregado | Concluir OS | Marcar a OS como concluída (com todos os itens obrigatórios resolvidos) | OS muda para "concluída", bloqueios funcionam se algo obrigatório faltar | | |
| 12 | Suporte administrativo | Gerar cobrança | Gerar a cobrança da OS concluída (cliente externo) | Valor da cobrança bate com os itens aprovados | | |
| 13 | Suporte administrativo | Liberar veículo | Liberar a OS (com pagamento confirmado ou termo de ciência) | OS muda para "liberada" | | |
| 14 | Administrador técnico | Ver configuração inicial | Abrir a tela de Configuração Inicial | Mostra os itens configurados nesta rodada (custo/hora, desconto, anexos, centros de custo) e checklist como pendente | | |
| 15 | Qualquer perfil não autorizado | Tentar ação fora do seu perfil | Ex.: executor tentando aprovar orçamento pela interface | Ação não aparece disponível na interface, e se forçada pela API é bloqueada | | |
| 16 | Usuário desligado | Acesso após desativação | Desativar um usuário de teste (`profiles.ativo=false`) e tentar usar o sistema com a sessão ainda aberta | Sistema bloqueia toda leitura/escrita, força logout | | |
| 17 | OS interna (frota própria) | Fluxo interno completo | Criar OS interna (sem orçamento/cobrança), executar, concluir | Custo total calculado corretamente, nenhuma cobrança gerada | | |
| 18 | Encarregado | Garantia | Abrir uma OS de garantia a partir de uma OS liberada | Vínculo com a OS/itens originais preservado | | |

## Depois do UAT

- Preencher a coluna Resultado de cada linha com evidência real (não
  fabricada).
- Qualquer FALHOU vira um achado real, com a mesma disciplina de
  `CLAUDE.md` (não mascarar, não mudar o resultado esperado para passar).
- Ao final, decidir se os dados `UAT_*` ficam preservados (inativados) como
  evidência, mesmo padrão usado para os registros `SMOKE_PROD` desta rodada
  (ver `docs/testing/TEST_REPORT_PROD01.md`).
