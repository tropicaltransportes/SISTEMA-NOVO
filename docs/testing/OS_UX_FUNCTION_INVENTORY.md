# Inventário funcional — OrdemServicoDetalhe.vue (pré-ETAPA OS-UX-02)

Levantado antes de qualquer alteração de código, conforme item 46 do pedido.
Cobre toda interação existente em `frontend/src/views/os/OrdemServicoDetalhe.vue`
(estado anterior à reestruturação OS-UX-02). Nenhuma linha desta tabela pode
"sumir silenciosamente" na nova tela — cada uma deve ter um "Novo local" e,
ao final da ETAPA OS-UX-02, "Testada?" preenchido.

| # | Funcionalidade | Local atual | Perfis | Status permitidos | Novo local | Testada? |
|---|---|---|---|---|---|---|
| 1 | Voltar para listagem | Cabeçalho | todos | qualquer | `OsCabecalho` | SIM (navegação usada em toda a sessão de teste) |
| 2 | Transição de status (Iniciar Diagnóstico / Enviar p/ Aprovação / Iniciar Execução / Enviar p/ Teste) | Cabeçalho (ação primária/secundária) | encarregado, administrador_tecnico | aberta, em_diagnostico, aguardando_aprovacao, em_execucao | `OsCabecalho` (zona ação principal) | SIM — "Enviar p/ Teste" clicado de verdade, status mudou e recarregou |
| 3 | Concluir (checklist) | Cabeçalho | encarregado, administrador_tecnico | aguardando_teste | `OsCabecalho` / `OsPendenciasConclusao` | SIM — clicado de verdade, `rpc_concluir_os` confirmado, bloco "Serviço Concluído" correto |
| 4 | Liberar | Cabeçalho | encarregado, administrador_tecnico | concluida | `OsCabecalho` (ação principal) | SIM — clicado de verdade, `rpc_liberar_os` confirmado |
| 5 | Gerar Cobrança | Cabeçalho | suporte_administrativo, administrador_tecnico | concluida + tipo externa | `OsCabecalho` (menu ⋮) | NÃO — condição não estava disponível no OS de teste (tipo interna); lógica idêntica ao original, revisada por leitura |
| 6 | Abrir Garantia | Cabeçalho | encarregado, administrador_tecnico | liberada, dentro de 90 dias, sem os_origem_id | `OsCabecalho` (menu ⋮) | PARCIAL — item apareceu corretamente no menu ⋮ após liberar a OS de teste; não cliquei para criar a garantia (evitar poluir dados de teste) |
| 7 | Relatório de Encerramento (link) | Cabeçalho | todos | concluida, liberada | `OsCabecalho` (menu ⋮) | PARCIAL — item apareceu corretamente no menu ⋮ após liberar; não cliquei (rota já existente, não alterada) |
| 8 | Relatório de Garantia (link) | Cabeçalho | todos | os_origem_id truthy | `OsCabecalho` (menu ⋮) | NÃO — nenhuma OS de garantia usada no teste; lógica idêntica ao original |
| 9 | Excluir OS (soft delete de rascunho) | Menu ⋮ | encarregado, administrador_tecnico | aberta, "virgem", não deletada | `OsCabecalho` (menu ⋮) + dialog | NÃO — dialog não tocado neste teste (evitar excluir OS de teste); lógica/markup idênticos ao original, só relocados |
| 10 | Cancelar OS | Menu ⋮ | encarregado, administrador_tecnico | aberta..concluida, não virgem, não deletada | `OsCabecalho` (menu ⋮) + dialog | PARCIAL — menu ⋮ confirmado mostrando "Cancelar OS" corretamente para OS não-virgem; dialog em si não submetido |
| 11 | Restaurar OS | Menu ⋮ | administrador_tecnico | deleted_at truthy | `OsCabecalho` (menu ⋮) + confirm | NÃO — nenhuma OS excluída disponível no teste; lógica idêntica ao original |
| 12 | Barra de etapas (visual) | Abaixo do cabeçalho | todos | aberta..liberada | `OsFaseAtual` (compacta) | SIM — visto em aberta/em_execucao/aguardando_teste/concluida/liberada |
| 13 | Badge terminal cancelada/excluída (visual + motivo/quem/quando) | Abaixo do cabeçalho | todos | cancelada / deleted_at | `OsFaseAtual` | SIM — visto numa OS cancelada real, motivo/quem/quando corretos |
| 14 | Definir checklist (selecionar template) | Aba Visão Geral | encarregado, administrador_tecnico | !checklist_template_id | `OsChecklistDialog` | NÃO — todas as OS de teste já tinham checklist definido; lógica idêntica ao original |
| 15 | Marcar item de checklist (toggle) | Aba Visão Geral | executor, encarregado, administrador_tecnico | qualquer (com checklist definido) | `OsChecklistDialog` | SIM — toggle real, upsert em `os_checklist_respostas` confirmado via REST, progresso do card atualizou |
| 16 | Definir/alterar previsão de conclusão | Aba Visão Geral + ícone no cabeçalho | encarregado, administrador_tecnico | !osEncerrada | `OsCabecalho` (ícone) + dialog | NÃO — dialog não submetido neste teste; markup/lógica idênticos ao original, só relocados |
| 17 | Marcar item de mão de obra como executado | Aba Visão Geral | executor, encarregado, administrador_tecnico | item aprovado, não executado/cancelado | `OsServicos` | NÃO — nenhuma OS de teste tinha item de mão de obra pendente; lógica idêntica ao original |
| 18 | Dispensar (cancelar) item de mão de obra | Aba Visão Geral | executor, encarregado, administrador_tecnico | item aprovado, não executado/cancelado | `OsServicos` (dialog motivo) | NÃO — idem acima |
| 19 | Informações de Garantia / Custo Interno (somente leitura) | Aba Visão Geral | todos | condicional a dados | Linha compacta de texto abaixo da fase (orquestrador) | SIM — "Custo interno: peças... = ..." e "Garantia até..." vistos corretamente em OS reais |
| 20 | Iniciar apontamento (selecionar etapa + observação) | Aba Execução | executor, encarregado, administrador_tecnico | qualquer | `OsTrabalhoAtual` | SIM — insert real em `os_executores` confirmado, card "Trabalho Atual" atualizou |
| 21 | Encerrar apontamento (próprio) | Aba Execução | dono da linha (usuario_id = eu) | !osEncerrada | `OsTrabalhoAtual` | SIM — update real (`fim`) confirmado, card voltou a "Nenhuma atividade" |
| 22 | Remover executor (formal, com motivo) | Aba Execução | encarregado, administrador_tecnico | linha ativa, !osEncerrada | `OsTrabalhoAtual` ("Ver todos os apontamentos", dialog no orquestrador) | NÃO — dialog não submetido neste teste; markup/lógica idênticos ao original |
| 23 | Baixar peça (vinculada a item de orçamento/garantia/adicional aprovado) | Aba Peças | executor, encarregado, suporte_administrativo, administrador_tecnico | em_diagnostico/em_execucao, há item elegível | `OsPecasDialog` | PARCIAL — dialog aberto de verdade, Select de item elegível populado corretamente; baixa em si não submetida (evitar mexer em estoque de teste) |
| 24 | Baixar peça livre (sem orçamento nem origem) | Aba Peças | idem | em_diagnostico/em_execucao, sem orçamento/origem | `OsPecasDialog` | NÃO — OS de teste usada tinha orçamento/origem; lógica idêntica ao original |
| 25 | Tabela de movimentos de peça (leitura, com origem) | Aba Peças | todos com acesso à OS | qualquer | `OsPecasDialog` | SIM — tabela populada com dados reais (peça, qtde, origem "adicional", custo, data) |
| 26 | Enviar foto (tipo antes/depois/outro + observação) | Aba Fotos | executor, encarregado, suporte_administrativo, administrador_tecnico | !osEncerrada | `OsFotosDialog` | NÃO — upload de arquivo não exercido neste teste; lógica idêntica ao original |
| 27 | Hint de obrigatoriedade de foto antes/depois (do checklist template) | Aba Fotos | todos | checklist_template_id definido | `OsFotosDialog` | SIM — visto no dialog aberto ("foto antes opcional"/"foto depois opcional") |
| 28 | Lista de fotos (leitura) | Aba Fotos | todos com acesso | qualquer | `OsFotosDialog` | SIM — dialog abriu corretamente (estado vazio visto numa OS sem fotos) |
| 29 | Identificar Necessidade de Adicional | Aba Adicionais | executor, encarregado, administrador_tecnico | !osEncerrada | `OsAdicionaisDialog` | NÃO — sub-dialog não submetido neste teste; lógica idêntica ao original |
| 30 | Incluir item precificado no adicional | Aba Adicionais | encarregado, administrador_tecnico | !osEncerrada | `OsAdicionaisDialog` | NÃO — idem acima |
| 31 | Cancelar adicional inteiro | Aba Adicionais | encarregado, administrador_tecnico | status aguardando_aprovacao | `OsAdicionaisDialog` | NÃO — nenhum adicional aguardando aprovação disponível no teste |
| 32 | Decidir item de adicional (aprovar/rejeitar, meio de aprovação) | Aba Adicionais | encarregado, suporte_administrativo, administrador_tecnico | item pendente | `OsAdicionaisDialog` | NÃO — idem acima |
| 33 | Marcar item de adicional (mão de obra) como executado | Aba Adicionais | executor, encarregado, administrador_tecnico | item aprovado, não executado/cancelado | `OsAdicionaisDialog` | NÃO — itens de teste disponíveis já estavam executados |
| 34 | Dispensar item de adicional aprovado | Aba Adicionais | idem | idem | `OsAdicionaisDialog` (dialog motivo compartilhado) | NÃO — idem acima |
| 35 | Histórico (timeline completa) | Aba Histórico | todos exceto executor | qualquer | `OsAtividadeRecente` (dialog "Ver histórico completo") | SIM — abas recentes vistas em várias OS; botão "Ver histórico completo" presente quando >5 eventos |
| 36 | Atividade recente (3-5 últimos eventos) | — (não existia) | todos exceto executor | qualquer | `OsAtividadeRecente` (NOVO bloco, mesmo dado) | SIM — visto atualizando em tempo real após cada transição/apontamento |
| 37 | Card de atenção — adicional aguardando decisão | — (não existia como destaque) | quem pode decidir | item aguardando_aprovacao | NOVO bloco contextual acima de Serviços | NÃO — nenhum adicional aguardando decisão disponível no teste; lógica revisada por leitura |
| 38 | Pendências para conclusão (lista do que falta) | — (não existia) | todos | aguardando_teste | `OsPendenciasConclusao` (NOVO, client-only) | SIM — testado em 2 OS reais; **achou e corrigiu 1 bug real** (rótulo de "Fotos"/"Checklist" não mudava quando pendente — ver relatório) |

## Notas
- Todas as 17 RPCs e as 2 escritas diretas em tabela permanecem chamadas
  exatamente como hoje — só muda de onde na UI são disparadas.
- Itens 36–38 são blocos novos pedidos explicitamente pelo pedido OS-UX-02
  (progressive disclosure / ação principal / pendências); não substituem
  nenhuma funcionalidade existente, só reorganizam a apresentação de dados
  já carregados.
- Custo/preço não tinha gate de RBAC no frontend antes desta etapa e continua
  sem gate novo — só deixa de ficar no centro da tela por default (fica
  dentro dos dialogs de detalhe/apoio), conforme item 16 do pedido.
