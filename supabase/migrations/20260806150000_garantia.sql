-- Fase 4: retorno de garantia — OS vinculada à original (os_origem_id, já
-- presente desde a Fase 2), sem cobrança ao cliente, dentro do prazo de 90
-- dias da liberação original.

-- OS de garantia externa não tem orçamento (valor R$ 0,00 ao cliente) —
-- relaxa a constraint pra aceitar os_origem_id como alternativa a orcamento_id.
alter table ordens_servico drop constraint os_externa_exige_orcamento;
alter table ordens_servico add constraint os_externa_exige_orcamento
  check (tipo <> 'externa' or orcamento_id is not null or os_origem_id is not null);

-- Cria a OS de garantia (copiando veículo/cliente/tipo/checklist da original)
-- e marca a original como reaberta_garantia. Bloqueia garantia-de-garantia
-- (evita encadear e estender o prazo indefinidamente) e fora do prazo de 90
-- dias da liberação original.
create or replace function rpc_criar_os_garantia(p_os_origem_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orig record;
  v_novo_id uuid;
begin
  if current_perfil() not in ('encarregado', 'administrador_tecnico') then
    raise exception 'Perfil sem permissão para abrir OS de garantia';
  end if;

  select * into v_orig from ordens_servico where id = p_os_origem_id for update;
  if v_orig.id is null then
    raise exception 'Ordem de serviço não encontrada';
  end if;
  if v_orig.status <> 'liberada' then
    raise exception 'Somente OS liberada pode gerar garantia';
  end if;
  if v_orig.os_origem_id is not null then
    raise exception 'Não é possível abrir garantia a partir de outra OS de garantia';
  end if;
  if v_orig.data_liberacao is null or now() > v_orig.data_liberacao + interval '90 days' then
    raise exception 'Prazo de garantia (90 dias da liberação) expirado';
  end if;

  insert into ordens_servico (veiculo_id, cliente_id, tipo, checklist_template_id, os_origem_id, criado_por)
  values (v_orig.veiculo_id, v_orig.cliente_id, v_orig.tipo, v_orig.checklist_template_id, p_os_origem_id, auth.uid())
  returning id into v_novo_id;

  update ordens_servico set status = 'reaberta_garantia' where id = p_os_origem_id;

  return v_novo_id;
end;
$$;

-- Liberação (3ª versão): a condição financeira da Fase 3 só se aplica a OS
-- externa que NÃO seja garantia. OS de garantia (os_origem_id preenchido)
-- libera sem cobrança, já que o valor ao cliente é R$ 0,00 — o custo real
-- de peças/mão de obra já foi registrado normalmente via rpc_baixar_peca_os.
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

  if v_os.tipo = 'externa' and v_os.os_origem_id is null then
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
