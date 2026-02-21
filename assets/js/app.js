// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let Hooks = {}

Hooks.AggregatedTradeList = {
  mounted() {
    this._init()
  },
  updated() {
    // Reinitialize after DOM patches (bindings are removed on replace)
    this._teardown()
    this._init()
  },
  destroyed() {
    this._teardown()
  },
  _init() {
    if (this._bound) return
    const root = this.el
    const table = root.querySelector('table')
    if (!table) return
    const tbody = table.querySelector('tbody')
    if (!tbody) return

    const headerBtns = table.querySelectorAll('thead [data-sort-key]')

    const arrowClosed = '▸'
    const arrowOpen = '▾'

    const updateButtonState = (btn, expanded) => {
      btn.setAttribute('aria-expanded', expanded ? 'true' : 'false')
      const icon = btn.querySelector('[data-toggle-icon]')
      if (icon) icon.textContent = expanded ? arrowOpen : arrowClosed
    }

    const getMainRows = () => Array.prototype.slice.call(
      tbody.querySelectorAll('tr[data-row-type="main"]')
    )
    const getDetailRow = (id) => tbody.querySelector(`tr[data-row-type="detail"][data-parent="${id}"]`)

    const collapseDetailRows = () => {
      tbody.querySelectorAll('tr[data-row-type="detail"]').forEach(row => row.classList.add('hidden'))
      tbody.querySelectorAll('[data-row-toggle]').forEach(btn => updateButtonState(btn, false))
    }

    // Toggle handler (event delegation on tbody)
    this._toggleHandler = (ev) => {
      // Ignore clicks on links, buttons, inputs to prevent accidental toggles
      const interactive = ev.target.closest('a, button, input, select, textarea, [role="button"]')
      if (interactive) return

      // Prefer an explicit toggle button if the click was on it
      let btn = ev.target.closest('[data-row-toggle]')

      // If not on the button, allow clicking the whole main row to toggle
      if (!btn) {
        const mainRow = ev.target.closest('tr[data-row-type="main"]')
        if (!mainRow) return
        const rowId = mainRow.getAttribute('data-row-id')
        if (!rowId) return
        btn = mainRow.querySelector('[data-row-toggle]')
        if (!btn) return
        // provide visual affordance for clickability
        mainRow.style.cursor = 'pointer'
      }

      if (!btn || btn.disabled) return
      const targetId = btn.dataset.rowToggle
      if (!targetId) return
      const detailRow = getDetailRow(targetId)
      if (!detailRow) return
      const isHidden = detailRow.classList.contains('hidden')
      if (isHidden) {
        detailRow.classList.remove('hidden')
        updateButtonState(btn, true)
      } else {
        detailRow.classList.add('hidden')
        updateButtonState(btn, false)
      }
    }
    tbody.addEventListener('click', this._toggleHandler)

    // Sorting handler (optional: if header buttons exist)
    const numKeys = { date: true, duration: true, pl: true }
    const cmp = (a, b, dir, key) => {
      let av = a.dataset[key] || ''
      let bv = b.dataset[key] || ''
      if (numKeys[key]) {
        const an = parseFloat(av) || 0
        const bn = parseFloat(bv) || 0
        return dir === 'asc' ? an - bn : bn - an
      } else {
        av = av.toString()
        bv = bv.toString()
        const r = av.localeCompare(bv)
        return dir === 'asc' ? r : -r
      }
    }
    const setArrows = (activeKey, dir) => {
      headerBtns.forEach(btn => {
        const arrow = btn.querySelector('[data-sort-arrow]')
        if (!arrow) return
        if (btn.dataset.sortKey === activeKey) {
          arrow.classList.remove('hidden')
          arrow.textContent = dir === 'desc' ? '▼' : '▲'
        } else {
          arrow.classList.add('hidden')
        }
      })
    }
    const applySort = (key, dir) => {
      const rows = getMainRows()
      rows.sort((r1, r2) => cmp(r1, r2, dir, key))
      rows.forEach(row => {
        tbody.appendChild(row)
        const detail = getDetailRow(row.dataset.rowId)
        if (detail) tbody.appendChild(detail)
      })
      root.dataset.currentSortKey = key
      root.dataset.currentSortDir = dir
      setArrows(key, dir)
      collapseDetailRows()
    }

    this._sortHandlers = []
    headerBtns.forEach(btn => {
      const handler = () => {
        const key = btn.dataset.sortKey
        const currentKey = root.dataset.currentSortKey || 'date'
        const currentDir = root.dataset.currentSortDir || 'desc'
        const dir = (key === currentKey) ? (currentDir === 'desc' ? 'asc' : 'desc') : 'asc'
        applySort(key, dir)
      }
      btn.addEventListener('click', handler)
      this._sortHandlers.push([btn, handler])
    })

    // Initialize visual arrow state and ensure details collapsed
    const initKey = root.dataset.currentSortKey || 'date'
    const initDir = root.dataset.currentSortDir || 'desc'
    setArrows(initKey, initDir)
    collapseDetailRows()

    this._bound = true
  },
  _teardown() {
    if (!this._bound) return
    const table = this.el.querySelector('table')
    const tbody = table && table.querySelector('tbody')
    if (tbody && this._toggleHandler) {
      tbody.removeEventListener('click', this._toggleHandler)
    }
    if (this._sortHandlers) {
      this._sortHandlers.forEach(([btn, handler]) => btn.removeEventListener('click', handler))
    }
    this._toggleHandler = null
    this._sortHandlers = []
    this._bound = false
  }
}

// Keeps an <input type="range"> and <input type="number"> inside the same container in sync.
// The number input holds the form value (has a name attribute); the range is for dragging.
Hooks.RangeNumberSync = {
  mounted()  { this._setup() },
  updated()  { this._setup() },
  _setup() {
    const range  = this.el.querySelector('input[type="range"]')
    const number = this.el.querySelector('input[type="number"]')
    if (!range || !number) return

    const round2 = (v) => {
      const n = parseFloat(v)
      return isNaN(n) ? 1 : Math.round(n * 100) / 100
    }

    const syncFromRange  = () => { number.value = round2(range.value).toFixed(2) }
    const syncFromNumber = () => {
      const v = round2(number.value)
      range.value  = v
      number.value = v.toFixed(2)
    }

    // Remove old listeners before re-attaching (safe on updated())
    if (this._range === range) return
    this._range  = range
    this._number = number
    range.addEventListener('input',  syncFromRange)
    number.addEventListener('input',  syncFromNumber)
    number.addEventListener('change', syncFromNumber)
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

