-- Fase 4: índice pro filtro de período "recebido no mês" do Dashboard
-- Executivo (demais filtros do dashboard já cobertos por índices das Fases
-- 1-3: idx_os_status, idx_parcelas_status_vencimento, idx_pecas_ruptura).
create index idx_recebimentos_data on recebimentos (data_recebimento);
