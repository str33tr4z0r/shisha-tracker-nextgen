<template>
  <div :class="{ 'min-h-screen p-6': true, 'bg-gray-50 text-gray-800': !isDark, 'bg-gray-900 text-gray-100': isDark }">
    <div class="max-w-4xl mx-auto">
      <header class="flex items-center justify-between mb-6">
        <div class="flex items-center gap-4">
          <h1 class="text-2xl font-semibold">Shisha Tracker</h1>
          <div class="relative">
            <input
              v-model="searchQuery"
              placeholder="Suche Name, Geschmack oder Hersteller..."
              class="p-2 border rounded pl-8 text-sm w-64"
              aria-label="Suche"
            />
            <svg class="w-4 h-4 absolute left-2 top-2 text-gray-400" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden>
              <path d="M21 21l-4.35-4.35" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
              <circle cx="11" cy="11" r="6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <button @click="toggleDark" :class="['px-3 py-1 border rounded text-sm', isDark ? 'btn-secondary' : 'btn']">
            {{ isDark ? 'Light' : 'Dark' }} Mode
          </button>
        </div>
      </header>

      <section class="mb-6">
        <form @submit.prevent="createShisha" class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <input v-model="newShisha.name" placeholder="Name" class="p-2 border rounded" />
          <input v-model="newShisha.flavor" placeholder="Geschmack" class="p-2 border rounded" />
          <input v-model="newShisha.manufacturer" placeholder="Hersteller" class="p-2 border rounded col-span-2" />
          <div class="col-span-2 flex gap-2">
            <button type="submit" class="bg-blue-600 text-white px-4 py-2 rounded">Erstellen</button>
            <button type="button" class="bg-gray-200 px-4 py-2 rounded" @click="load()">Refresh</button>
          </div>
        </form>
      </section>

      <section>
        <ul class="grid gap-4">
          <li v-for="s in filteredShishas" :key="s.id" :class="['p-4 rounded shadow', isDark ? 'bg-gray-800 text-gray-100' : 'bg-white text-gray-900']">
            <div class="flex justify-between items-start">
              <div>
                <h2 class="font-medium text-lg">{{ s.name }}</h2>
                <p :class="['text-sm', isDark ? 'text-gray-300' : 'text-gray-600']">Geschmack: {{ s.flavor }}</p>
                <p :class="['text-sm', isDark ? 'text-gray-300' : 'text-gray-600']">Hersteller: {{ s.manufacturer.name }}</p>
              </div>
              <div class="text-sm component-muted flex items-center gap-3">
                <span>{{ s.ratings?.length || 0 }} Bewertungen</span>
                <button @click="markSmoked(s.id)" class="bg-yellow-500 text-white px-3 py-1 rounded text-sm">
                  Geraucht ({{ s.smokedCount || 0 }})
                </button>
                <button @click="deleteShisha(s.id)" class="bg-red-600 text-white px-3 py-1 rounded text-sm">
                  Löschen
                </button>
              </div>
            </div>
            <div class="mt-3">
              <details>
                <summary :class="['cursor-pointer text-sm', isDark ? 'text-blue-300' : 'text-blue-600']">Kommentare & Bewertungen</summary>
                <div class="mt-2 space-y-3">
                  <div class="flex items-center justify-between">
                    <div class="text-sm">
                      <span class="font-semibold">Durchschnitt:</span>
                      <span v-if="s.ratings && s.ratings.length">
                        {{ ((s.ratings.reduce((a: number, b: Rating) => a + (b.score || 0), 0) / s.ratings.length) / 2).toFixed(1) }} / 5
                      </span>
                      <span v-else> Keine Bewertungen</span>
                      <span class="ml-2 text-gray-500">({{ s.ratings?.length || 0 }})</span>
                    </div>
                    <div class="flex items-center gap-2">
                      <!-- Rating control moved to the input section below (Name → Score → Kommentar) -->
                      <span class="text-sm text-gray-500">Bitte unten Name, Wertung und Kommentar eingeben</span>
                    </div>
                  </div>

                  <div>
                    <div>
                      <span class="font-semibold text-sm">Alle Bewertungen:</span>
                      <ul class="mt-1 space-y-1">
                        <li v-for="(r, ridx) in s.ratings || []" :key="'r-'+ridx" :class="['text-sm', isDark ? 'text-gray-200' : 'text-gray-700']">
                          - {{ r.user }} — {{ (r.score / 2).toFixed(1) }}
                          <span v-if="r.timestamp" class="text-xs text-gray-500">— {{ formatTime(r.timestamp) }}</span>
                        </li>
                        <li v-if="!(s.ratings && s.ratings.length)" class="text-sm text-gray-500">Keine Bewertungen vorhanden</li>
                      </ul>
                    </div>

                    <div class="mt-2">
                      <span class="font-semibold text-sm">Kommentare:</span>
                      <ul class="mt-1 space-y-1">
                        <li v-for="(c, idx) in s.comments" :key="idx" :class="['text-sm', isDark ? 'text-gray-200' : 'text-gray-700']">- {{ c.user }} — {{ userScore(s, c.user) }} — {{ c.message }}</li>
                        <li v-if="!(s.comments && s.comments.length)" class="text-sm text-gray-500">Keine Kommentare</li>
                      </ul>
                    </div>
                  </div>

                  <div class="grid grid-cols-1 sm:grid-cols-4 gap-2">
                    <input v-model="commentUser[s.id]" placeholder="Name" class="p-2 border rounded sm:col-span-1" />
                    <div class="p-2 border rounded sm:col-span-1 flex items-center justify-center">
                      <StarRating v-model="ratingInputs[s.id]" />
                    </div>
                    <textarea v-model="commentText[s.id]" placeholder="Kommentar..." class="p-2 border rounded sm:col-span-2"></textarea>
                  </div>
                  <div class="flex items-center gap-3 mt-2">
                    <button
                      @click="submitReview(s.id)"
                      :disabled="!commentUser[s.id] || !commentUser[s.id].trim() || (ratingInputs[s.id] ?? 0) < 0.5"
                      class="bg-indigo-600 text-white px-4 py-2 rounded text-sm disabled:opacity-50"
                    >
                      Absenden
                    </button>
                    <span class="text-sm text-gray-500">Minimale Wertung: 0.5 Sterne — Name erforderlich</span>
                  </div>
                </div>
              </details>
            </div>
          </li>
        </ul>
      </section>

      <footer class="mt-6">
        <div :class="['max-w-4xl mx-auto text-center mb-1', isDark ? 'text-gray-300 font-semibold text-sm' : 'text-gray-600 font-semibold text-sm']">
          Pod: {{ runtimeInfo.pod || 'local' }} — Host: {{ (runtimeInfo.hostname || '').slice(0,12) }}
        </div>
 
        <div :class="['max-w-4xl mx-auto text-center mb-1 text-sm', isDark ? 'text-gray-300' : 'text-gray-600']">
          <div><strong>Backend Container:</strong> {{ (backendContainerID || runtimeInfo.container_id || runtimeInfo.hostname || '').slice ? ( (backendContainerID || runtimeInfo.container_id || runtimeInfo.hostname || '').slice(0,12) ) : (backendContainerID || runtimeInfo.container_id || runtimeInfo.hostname || '') }}</div>
        </div>
 
        <!-- CouchDB cluster status -->
        <div class="max-w-4xl mx-auto mt-2 mb-2 text-sm p-3 rounded" :class="isDark ? 'bg-gray-800 text-gray-200' : 'bg-white text-gray-800'">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <!-- status icon -->
              <template v-if="couchClusterError">
                <svg class="w-4 h-4 text-red-500" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden>
                  <path d="M12 9v4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                  <path d="M12 17h.01" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
              </template>
              <template v-else-if="!couchCluster">
                <svg class="w-4 h-4 text-gray-400 animate-pulse" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden>
                  <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
              </template>
              <template v-else-if="couchCluster.cluster">
                <svg class="w-4 h-4 text-green-500" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden>
                  <path d="M20 6L9 17l-5-5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
              </template>
              <template v-else>
                <svg class="w-4 h-4 text-yellow-600" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden>
                  <path d="M12 9v4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                  <path d="M12 17h.01" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
              </template>

              <div class="text-sm font-medium">CouchDB Cluster</div>
            </div>

            <div class="text-sm">
              <span v-if="couchClusterError" class="couch-error">{{ couchClusterError }}</span>
              <span v-else-if="!couchCluster" class="text-gray-500">Loading…</span>
              <span v-else>
                <span class="badge" :class="couchCluster.cluster ? 'badge-green' : 'badge-yellow'">
                  {{ couchCluster.cluster ? 'Clustered' : 'Not clustered' }}
                </span>
              </span>
            </div>
          </div>

          <div class="mt-2 text-xs">
            <div v-if="couchCluster">
              <div>
                <strong>Cluster nodes:</strong>
                <span v-if="couchCluster.cluster_nodes && couchCluster.cluster_nodes.length">{{ couchCluster.cluster_nodes.join(', ') }}</span>
                <span v-else class="text-gray-500">-</span>
              </div>
              <div class="mt-1">
                <strong>All nodes:</strong>
                <span v-if="couchCluster.all_nodes && couchCluster.all_nodes.length">{{ couchCluster.all_nodes.join(', ') }}</span>
                <span v-else class="text-gray-500">-</span>
              </div>
              <div class="mt-1">
                <strong>Expected replicas:</strong>
                <span class="ml-1">{{ couchCluster.expected_replicas || 0 }}</span>
                <span v-if="couchCluster.expected_replicas && couchCluster.cluster_nodes && couchCluster.cluster_nodes.length !== couchCluster.expected_replicas" class="ml-2 badge badge-yellow">Mismatch</span>
              </div>
            </div>
            <div v-else-if="couchClusterError" class="mt-1 text-xs">
              <span class="couch-error">Unable to load cluster status</span>
            </div>
          </div>
        </div>
 
        <div
          :class="['max-w-4xl mx-auto text-center text-sm', isDark ? 'footer-link footer-glow' : 'text-gray-500 opacity-80']"
          :role="isDark ? 'link' : undefined"
          :tabindex="isDark ? 0 : -1"
          @click="isDark ? openSpotify() : null"
          @keydown.enter.prevent="isDark ? openSpotify() : null"
        >
          Created by Manuel und Ricardo - Powered by Meldestein
        </div>
      </footer>

    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import StarRating from './components/StarRating.vue'
 
interface Manufacturer { id: number; name: string }
interface Rating { user: string; score: number; timestamp?: number }
interface Comment { user: string; message: string }
interface Shisha { id: number; name: string; flavor: string; manufacturer: Manufacturer; ratings?: Rating[]; comments?: Comment[]; smokedCount?: number }
 
interface CouchCluster {
  cluster: boolean
  cluster_nodes: string[]
  all_nodes: string[]
  expected_replicas: number
}
 
const API = import.meta.env.VITE_API_URL || '/api'
 
const shishas = ref<Shisha[]>([])
const newShisha = ref({ name: '', flavor: '', manufacturer: '' })
 
// per-shisha local inputs
const ratingInputs = ref<Record<number, number>>({})
const commentText = ref<Record<number, string>>({})
const commentUser = ref<Record<number, string>>({})
const isDark = ref<boolean>(false)
const searchQuery = ref<string>('')
const runtimeInfo = ref<{ pod?: string; hostname?: string; container_id?: string }>({})
const backendContainerID = ref<string>('')

// CouchDB cluster state
const couchCluster = ref<CouchCluster | null>(null)
const couchClusterError = ref<string>('')
 
const filteredShishas = computed(() => {
  const q = (searchQuery.value || '').toLowerCase().trim()
  if (!q) return shishas.value
  return shishas.value.filter((s: Shisha) => {
    const name = (s.name || '').toLowerCase()
    const flavor = (s.flavor || '').toLowerCase()
    const manu = (s.manufacturer?.name || '').toLowerCase()
    return name.includes(q) || flavor.includes(q) || manu.includes(q)
  })
})
 
function flavorEmoji(flavor?: string) {
  if (!flavor) return ''
  const f = flavor.toLowerCase()
  const map: Record<string,string> = {
    'mint': '🌿','minze':'🌿',
    'apple': '🍎','apfel':'🍎',
    'grape': '🍇','traube':'🍇',
    'lemon': '🍋','zitrone':'🍋',
    'watermelon':'🍉','wassermelone':'🍉',
    'peach':'🍑','pfirsich':'🍑',
    'cola':'🥤',
    'vanilla':'🍨','vanille':'🍨',
    'coffee':'☕','kaffee':'☕',
    'berry':'🫐','beere':'🫐',
    'orange':'🍊'
  }
  for (const k of Object.keys(map)) {
    if (f.includes(k)) return map[k]
  }
  return ''
}
 
function formatTime(ts?: number) {
  if (!ts) return ''
  return new Date(ts * 1000).toLocaleString()
}
 
async function load() {
  const res = await fetch(`${API}/shishas`)
  shishas.value = await res.json()
  // ensure inputs exist for listed shishas
  shishas.value.forEach((s: Shisha) => {
    if (ratingInputs.value[s.id] === undefined) ratingInputs.value[s.id] = 0.5
    if (commentText.value[s.id] === undefined) commentText.value[s.id] = ''
    if (commentUser.value[s.id] === undefined) commentUser.value[s.id] = ''
    if (s.smokedCount === undefined) s.smokedCount = 0
  })
}
 
function userScore(shisha: Shisha, user: string): string {
  // show the latest rating by this user (reverse search)
  const r = [...(shisha.ratings || [])].reverse().find(rt => rt.user === user)
  if (!r) return '-'
  // backend stores integer score (half-stars * 2) — convert to 0..5 scale
  return (r.score / 2).toFixed(1)
}
 
async function submitReview(id: number) {
  const name = (commentUser.value[id] || '').trim()
  if (!name) {
    alert('Bitte einen Namen angeben, um die Bewertung/den Kommentar zu speichern.')
    return
  }
  const value = ratingInputs.value[id] ?? 0
  if (value < 0.5) {
    alert('Die minimale Bewertung ist 0.5 Sterne.')
    return
  }
 
  // send rating first
  const ratingPayload = { user: name, score: Math.round(value * 2) } // backend expects int (half-stars * 2)
  const ratingRes = await fetch(`${API}/shishas/${id}/ratings`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(ratingPayload),
  })
  if (!ratingRes.ok) {
    console.error('rating failed', await ratingRes.text())
    alert('Fehler beim Speichern der Bewertung.')
    return
  }
 
  // send comment if provided
  const txt = (commentText.value[id] || '').trim()
  if (txt) {
    const commentPayload = { user: name, message: txt }
    const commentRes = await fetch(`${API}/shishas/${id}/comments`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(commentPayload),
    })
    if (!commentRes.ok) {
      console.error('comment failed', await commentRes.text())
      alert('Fehler beim Speichern des Kommentars.')
      return
    }
    commentText.value[id] = ''
  }
 
  // reload list to show both rating and comment
  await load()
}
 
async function submitComment(id: number) {
  const name = (commentUser.value[id] || '').trim()
  if (!name) {
    alert('Bitte einen Namen angeben, um einen Kommentar zu speichern.')
    return
  }
  const txt = (commentText.value[id] || '').trim()
  if (!txt) return
  const payload = { user: name, message: txt }
  const res = await fetch(`${API}/shishas/${id}/comments`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
  if (res.ok) {
    commentText.value[id] = ''
    await load()
  } else {
    console.error('comment failed', await res.text())
  }
}
 
async function markSmoked(id: number) {
  const res = await fetch(`${API}/shishas/${id}/smoked`, { method: 'POST' })
  if (res.ok) {
    const data = await res.json()
    const idx = shishas.value.findIndex((s: Shisha) => s.id === id)
    if (idx >= 0) shishas.value[idx].smokedCount = data.smokedCount
  } else {
    console.error('smoked increment failed', await res.text())
  }
}
 
async function createShisha() {
  const payload = {
    name: newShisha.value.name,
    flavor: newShisha.value.flavor,
    manufacturer: { id: 0, name: newShisha.value.manufacturer },
    ratings: [],
    comments: [],
    smokedCount: 0,
  }
  const res = await fetch(`${API}/shishas`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
  if (res.ok) {
    newShisha.value = { name: '', flavor: '', manufacturer: '' }
    await load()
  } else {
    console.error('create failed', await res.text())
  }
}
 
async function deleteShisha(id: number) {
  if (!confirm('Shisha wirklich löschen?')) return
  try {
    const res = await fetch(`${API}/shishas/${id}`, { method: 'DELETE' })
    if (res.ok) {
      shishas.value = shishas.value.filter((s: Shisha) => s.id !== id)
    } else {
      console.error('delete failed', await res.text())
      alert('Fehler beim Löschen der Shisha.')
    }
  } catch (err) {
    console.error('delete error', err)
    alert('Fehler beim Löschen der Shisha.')
  }
}
 
function openSpotify() {
  // only open when dark mode is active
  if (!isDark.value) return
  window.open('https://open.spotify.com/track/3aQQugKq0iSULrO4A8qEsN?si=e076eb414b6647c8', '_blank', 'noopener')
}
 
function toggleDark() {
  isDark.value = !isDark.value
  try {
    localStorage.setItem('shisha-dark', isDark.value ? '1' : '0')
  } catch (_) {}
  // keep document element class in sync for any global styling/plugins
  if (isDark.value) document.documentElement.classList.add('dark')
  else document.documentElement.classList.remove('dark')
}
 
async function loadCluster() {
  try {
    const r = await fetch(`${API}/couchdb/cluster`)
    if (!r.ok) {
      couchCluster.value = null
      couchClusterError.value = `HTTP ${r.status}`
      return
    }
    const json = await r.json()
    couchCluster.value = json as CouchCluster
    couchClusterError.value = ''
  } catch (e) {
    couchCluster.value = null
    couchClusterError.value = 'failed to fetch cluster status'
    console.warn('loadCluster error', e)
  }
}
 
onMounted(async () => {
  const stored = (typeof localStorage !== 'undefined' && localStorage.getItem('shisha-dark')) || '0'
  isDark.value = stored === '1'
  if (isDark.value) document.documentElement.classList.add('dark')
 
  // fetch runtime info (pod name / hostname) from backend
  try {
    const r = await fetch(`${API}/info`)
    if (r.ok) {
      runtimeInfo.value = await r.json()
      // debug: log runtime info to console for easier troubleshooting
      console.log('runtimeInfo', runtimeInfo.value)
    }
  } catch (_) {}
 
  // fetch backend container id explicitly (lightweight endpoint)
  try {
    const r2 = await fetch(`${API}/container-id`)
    if (r2.ok) {
      const body = await r2.json()
      backendContainerID.value = body?.container_id || ''
      // keep runtimeInfo.container_id in sync if empty
      if (!runtimeInfo.value.container_id) runtimeInfo.value.container_id = backendContainerID.value
      console.log('backendContainerID', backendContainerID.value)
    }
  } catch (e) {
    console.warn('failed to fetch backend container-id', e)
  }
 
  await load()
  // load CouchDB cluster status after initial data fetch
  await loadCluster()
})
</script>
 
<style>
/* minimal global styling; Tailwind ist primär */
footer { text-align:center; margin-top:1.5rem; }

/* footer link highlight + glow in dark mode */
/* non-active (light) state */
.text-gray-500.opacity-80 { opacity: 0.9; }

/* pointer only when interactive */
.footer-link { cursor: pointer; outline: none; }

/* improved dark-mode contrast: stronger color, subtle background and clearer shadow */
.dark .footer-link.footer-glow {
  color: var(--star-color);
  background: rgba(255,215,0,0.06);
  padding: 0.125rem 0.4rem;
  border-radius: 0.25rem;
  box-shadow: 0 6px 18px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.02);
  text-shadow: 0 0 10px rgba(245,158,11,0.95), 0 0 24px rgba(245,158,11,0.45);
}

/* slight focus outline for keyboard users in dark mode */
.dark .footer-link.footer-glow:focus {
  box-shadow: 0 0 0 3px rgba(245,158,11,0.12), 0 6px 18px rgba(0,0,0,0.5);
  outline: none;
}

/* Cluster status badges and error styling */
.badge {
  display: inline-block;
  padding: 0.125rem 0.5rem;
  border-radius: 9999px;
  font-weight: 600;
  font-size: 0.75rem;
  line-height: 1;
  vertical-align: middle;
}
.badge-green { background: rgba(16,185,129,0.12); color: #10B981; border: 1px solid rgba(16,185,129,0.2); }
.badge-yellow { background: rgba(234,179,8,0.08); color: #EAB308; border: 1px solid rgba(234,179,8,0.12); }
.badge-red { background: rgba(239,68,68,0.08); color: #EF4444; border: 1px solid rgba(239,68,68,0.12); }

.couch-error {
  color: #EF4444;
  font-weight: 600;
  background: rgba(239,68,68,0.04);
  padding: 0.125rem 0.4rem;
  border-radius: 0.25rem;
  border: 1px solid rgba(239,68,68,0.08);
  display: inline-block;
  font-size: 0.85rem;
}
</style>