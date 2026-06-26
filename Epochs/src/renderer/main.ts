// Placeholder renderer. Its job for now is to PROVE the renderer can import and
// use the pure engine module (the area VP table) — the real map view comes later.
import './style.css'
import { EPOCHS, type EpochId } from '../shared/types'
import { AREA_NAMES, AREA_VALUES, areaValue } from '../shared/data/areaValues'

const ROMAN = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII']

function toRoman(n: number): string {
  return ROMAN[n] ?? String(n)
}

function render(): void {
  const app = document.getElementById('app')
  if (!app) return

  const header = EPOCHS.map((e) => `<th>${toRoman(e)}</th>`).join('')
  const rows = Object.keys(AREA_VALUES)
    .map((id) => {
      const cells = EPOCHS.map((e: EpochId) => {
        const v = areaValue(id, e)
        return `<td class="${v === 0 ? 'zero' : ''}">${v === 0 ? '·' : v}</td>`
      }).join('')
      return `<tr><th class="area">${AREA_NAMES[id]}</th>${cells}</tr>`
    })
    .join('')

  app.innerHTML = `
    <main>
      <h1>Epochs</h1>
      <p class="tagline">A strategy game of empires that rise and fall across seven epochs.</p>
      <p class="status">Engine scaffold v0.1 — rules core wired; map &amp; AI under construction.</p>
      <h2>Area scoring values by epoch</h2>
      <table class="vp">
        <thead><tr><th class="area">Area</th>${header}</tr></thead>
        <tbody>${rows}</tbody>
      </table>
      <p class="note">Values shown are <em>presence</em> (base). Dominance doubles, control triples.</p>
    </main>
  `
}

render()
