-- Fase 3: agora que o módulo financeiro existe, a liberação de OS externa
-- passa a exigir uma condição financeira satisfeita, em vez de bloquear
-- incondicionalmente (comportamento da Fase 2).

create or replace function rpc_liberar_os(p_os_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_os record;
  v_cobranca record;
  v_condicao_ok boolean;
begin
  if current_perfil() not in ('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para liberar OS';
  end if;

  select * into v_os from ordens_servico where id = p_os_id for update;
  if v_os.id is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_os.status <> 'concluida' then
    raise exception 'Somente OS concluída pode ser liberada';
  end if;

  if v_os.tipo = 'externa' then
    select c.* into v_cobranca
      from cobranca_origens co
      join cobrancas c on c.id = co.cobranca_id
      where co.os_id = p_os_id and c.status <> 'cancelada'
      order by c.criado_em desc
      limit 1;

    if v_cobranca.id is null then
      raise exception 'OS externa exige cobrança gerada antes da liberação';
    end if;

    v_condicao_ok := v_cobranca.status = 'quitada'
      or exists (select 1 from parcelas where cobranca_id = v_cobranca.id)
      or exists (select 1 from termos_ciencia_debito where cobranca_id = v_cobranca.id);

    if not v_condicao_ok then
      raise exception 'Condição financeira pendente: parcele, quite a cobrança ou registre o Termo de Ciência de Débito';
    end if;
  end if;

  update ordens_servico set status = 'liberada', data_liberacao = now() where id = p_os_id;
end;
$$;
