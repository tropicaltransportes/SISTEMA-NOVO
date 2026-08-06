# ERP Oficina — Tropical Transportes

Sistema novo e independente do dashboard PCM (Google Sheets/Apps Script) para controlar o ciclo completo de manutenção
da oficina: solicitações, orçamentos, ordens de serviço, estoque, venda avulsa, financeiro, garantia e indicadores.

Ver o desenho arquitetural completo em [`docs/plano-arquitetura.md`](docs/plano-arquitetura.md) (decisões, modelo de
dados, máquinas de estado, matriz RBAC/RLS, plano de fases, riscos e pendências).

**Status atual: Fase 1 — Fundação** (Auth, perfis, RLS base, cadastro de clientes/veículos, estoque com custo médio
ponderado móvel e RPC anti-negativação, importação inicial via CSV).

## Estrutura do repositório

```
supabase/migrations/   Migrations SQL versionadas (aplicar via Supabase CLI)
frontend/               Aplicação Vue 3 + Vite (SPA)
```

## 1. Criar o projeto Supabase

1. Crie um projeto gratuito em https://supabase.com.
2. Em **Project Settings → API**, copie a `Project URL` e a `anon public key`.
3. Instale a Supabase CLI (via `npx`, sem instalação global):
   ```bash
   npx supabase login
   npx supabase link --project-ref SEU-PROJECT-REF
   ```
4. Aplique as migrations:
   ```bash
   npx supabase db push
   ```
   Isso cria: enum de perfis, tabela `profiles` (com trigger de auto-criação no signup), `clientes`, `veiculos`,
   `pecas`, `estoque_movimentos`, `notas_fiscais_entrada`/`nf_entrada_itens`, e as RPCs de confirmação/estorno de NF
   e baixa de estoque — todas já com RLS habilitado.

## 2. Criar os primeiros usuários

Convide os usuários pelo painel do Supabase (**Authentication → Users → Invite user**). Cada convite dispara o
trigger `on_auth_user_created`, que cria automaticamente a linha em `profiles` com `perfil = 'executor'`. Para ajustar
o perfil real de cada pessoa (encarregado, suporte_administrativo, diretoria, administrador_tecnico), rode no SQL
Editor do Supabase (como `administrador_tecnico` inicial, use o SQL Editor com a service role):

```sql
update profiles set perfil = 'administrador_tecnico' where id = 'UUID-DO-USUARIO';
```

## 3. Configurar e rodar o frontend

```bash
cd frontend
cp .env.example .env
# edite .env com a Project URL e a anon key do passo 1
npm install
npm run dev
```

Acesse http://localhost:5173 e entre com um usuário convidado no passo 2.

## 4. Importação inicial de dados (uso único)

Com um usuário `suporte_administrativo` ou `administrador_tecnico`, acesse **Importação Inicial** no menu e envie:

- **CSV de Clientes**: colunas `nome, documento, telefone, email, tipo` (`tipo`: `interno` ou `externo`, padrão `externo`).
- **CSV de Veículos**: colunas `placa, prefixo, modelo, ano, cliente_documento`. Deixe `cliente_documento` em branco
  para vincular o veículo à frota própria (cliente interno, já semeado pela migration).

Essa tela é só para a carga inicial — o cadastro do dia a dia é feito nas telas de Clientes/Veículos.

## 5. Riscos de infraestrutura (free tier) — mitigar antes de ir a produção

- **Pausa por inatividade**: projetos Supabase gratuitos pausam após ~7 dias sem requisições e não retomam sozinhos.
  Configure um ping agendado (ex: GitHub Actions `schedule` diário fazendo um `select` simples).
- **Backup**: o free tier não inclui Point-in-Time Recovery. Agende um `pg_dump` lógico (ex: GitHub Actions) para um
  armazenamento externo gratuito, com retenção rotativa.
- **Storage**: cota de 1GB — comprima fotos/comprovantes no upload antes de gravar no Supabase Storage.

## Próximas fases

Ver seção "Plano de Implementação" em `docs/plano-arquitetura.md`: Fase 2 (Solicitações/Orçamentos/OS/Venda Avulsa),
Fase 3 (Financeiro) e Fase 4 (Garantia + Dashboard Executivo).
