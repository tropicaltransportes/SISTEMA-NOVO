<script setup>
import { ref } from 'vue'
import Papa from 'papaparse'
import { supabase } from '../../lib/supabaseClient'
import { useToast } from 'primevue/usetoast'
import FileUpload from 'primevue/fileupload'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Button from 'primevue/button'
import Message from 'primevue/message'

const toast = useToast()

const linhasClientes = ref([])
const linhasVeiculos = ref([])
const importandoClientes = ref(false)
const importandoVeiculos = ref(false)

function parseCsv(file, onComplete) {
  Papa.parse(file, {
    header: true,
    skipEmptyLines: true,
    complete: (resultado) => onComplete(resultado.data),
    error: (erro) => toast.add({ severity: 'error', summary: 'Erro ao ler CSV', detail: erro.message, life: 5000 }),
  })
}

function selecionarClientesCsv(event) {
  const arquivo = event.files[0]
  if (arquivo) parseCsv(arquivo, (linhas) => (linhasClientes.value = linhas))
}

function selecionarVeiculosCsv(event) {
  const arquivo = event.files[0]
  if (arquivo) parseCsv(arquivo, (linhas) => (linhasVeiculos.value = linhas))
}

async function importarClientes() {
  importandoClientes.value = true
  const payload = linhasClientes.value
    .filter((l) => l.nome)
    .map((l) => ({
      tipo: (l.tipo || 'externo').trim().toLowerCase(),
      nome: l.nome.trim(),
      documento: l.documento?.trim() || null,
      telefone: l.telefone?.trim() || null,
      email: l.email?.trim() || null,
    }))

  const { error } = await supabase.from('clientes').insert(payload)
  importandoClientes.value = false

  if (error) {
    toast.add({ severity: 'error', summary: 'Erro na importação de clientes', detail: error.message, life: 6000 })
    return
  }
  toast.add({ severity: 'success', summary: `${payload.length} clientes importados`, life: 4000 })
  linhasClientes.value = []
}

async function importarVeiculos() {
  importandoVeiculos.value = true

  const { data: clienteInterno } = await supabase.from('clientes').select('id').eq('tipo', 'interno').limit(1).single()
  const { data: clientesExistentes } = await supabase.from('clientes').select('id, documento').is('deleted_at', null)
  const mapaDocumentos = new Map((clientesExistentes ?? []).filter((c) => c.documento).map((c) => [c.documento, c.id]))

  const payload = []
  const semCliente = []
  for (const linha of linhasVeiculos.value) {
    if (!linha.placa) continue
    const documento = linha.cliente_documento?.trim()
    const clienteId = documento ? mapaDocumentos.get(documento) : clienteInterno?.id
    if (!clienteId) {
      semCliente.push(linha.placa)
      continue
    }
    payload.push({
      cliente_id: clienteId,
      placa: linha.placa.trim().toUpperCase(),
      prefixo: linha.prefixo?.trim() || null,
      modelo: linha.modelo?.trim() || null,
      ano: linha.ano ? Number(linha.ano) : null,
    })
  }

  if (payload.length > 0) {
    const { error } = await supabase.from('veiculos').insert(payload)
    if (error) {
      importandoVeiculos.value = false
      toast.add({ severity: 'error', summary: 'Erro na importação de veículos', detail: error.message, life: 6000 })
      return
    }
  }

  importandoVeiculos.value = false
  toast.add({ severity: 'success', summary: `${payload.length} veículos importados`, life: 4000 })
  if (semCliente.length > 0) {
    toast.add({
      severity: 'warn',
      summary: `${semCliente.length} veículos ignorados`,
      detail: `cliente_documento não encontrado: ${semCliente.join(', ')}`,
      life: 8000,
    })
  }
  linhasVeiculos.value = []
}
</script>

<template>
  <div class="pagina-importacao">
    <h2>Importação Inicial</h2>
    <Message severity="info" :closable="false">
      Importação única de dados existentes (frota própria e clientes). Use apenas na configuração inicial do sistema —
      não substitui o cadastro manual do dia a dia.
    </Message>

    <section class="secao">
      <h3>Clientes</h3>
      <p class="ajuda">CSV com colunas: <code>nome, documento, telefone, email, tipo</code> (tipo: interno ou externo — padrão externo).</p>
      <FileUpload
        mode="basic"
        accept=".csv"
        :auto="true"
        chooseLabel="Selecionar CSV de Clientes"
        customUpload
        @select="selecionarClientesCsv"
      />
      <DataTable v-if="linhasClientes.length" :value="linhasClientes" class="preview" :rows="5" paginator>
        <Column field="nome" header="Nome" />
        <Column field="documento" header="Documento" />
        <Column field="telefone" header="Telefone" />
        <Column field="tipo" header="Tipo" />
      </DataTable>
      <Button
        v-if="linhasClientes.length"
        label="Importar Clientes"
        icon="pi pi-upload"
        :loading="importandoClientes"
        @click="importarClientes"
      />
    </section>

    <section class="secao">
      <h3>Veículos</h3>
      <p class="ajuda">
        CSV com colunas: <code>placa, prefixo, modelo, ano, cliente_documento</code>. Deixe
        <code>cliente_documento</code> em branco para vincular à frota própria.
      </p>
      <FileUpload
        mode="basic"
        accept=".csv"
        :auto="true"
        chooseLabel="Selecionar CSV de Veículos"
        customUpload
        @select="selecionarVeiculosCsv"
      />
      <DataTable v-if="linhasVeiculos.length" :value="linhasVeiculos" class="preview" :rows="5" paginator>
        <Column field="placa" header="Placa" />
        <Column field="prefixo" header="Prefixo" />
        <Column field="modelo" header="Modelo" />
        <Column field="ano" header="Ano" />
        <Column field="cliente_documento" header="Documento do Cliente" />
      </DataTable>
      <Button
        v-if="linhasVeiculos.length"
        label="Importar Veículos"
        icon="pi pi-upload"
        :loading="importandoVeiculos"
        @click="importarVeiculos"
      />
    </section>
  </div>
</template>

<style scoped>
.pagina-importacao {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}
.secao {
  background: white;
  border: 1px solid #e5e7eb;
  border-radius: 10px;
  padding: 1.25rem;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  align-items: flex-start;
}
.ajuda {
  font-size: 0.85rem;
  color: #6b7280;
  margin: 0;
}
.preview {
  width: 100%;
}
</style>
