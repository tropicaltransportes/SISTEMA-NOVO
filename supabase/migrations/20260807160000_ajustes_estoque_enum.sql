-- Fase 5: ajustes manuais de estoque (entrada sem nota fiscal / correção de
-- contagem física de inventário). Precisa ficar em migration própria: o
-- Postgres não permite usar um valor de enum recém-adicionado na mesma
-- transação em que ele foi criado.
alter type origem_movimento add value 'ajuste_estoque';
