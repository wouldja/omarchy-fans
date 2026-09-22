.pragma library

var modes = [
  { value: "auto", label: "Auto" },
  { value: "quiet", label: "Cool & quiet" },
  { value: "performance", label: "Performance" },
  { value: "curve", label: "Fan curve" },
  { value: "manual", label: "Manual" }
]

var points = [45, 60, 72, 82, 92]

function clamp(value, min, max) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return min
  return Math.max(min, Math.min(max, n))
}

function defaultDuties() {
  return [25, 45, 65, 85, 100]
}

function defaultState() {
  return {
    available: false,
    mode: "auto",
    manual: 40,
    duties: defaultDuties(),
    cpuTemp: 0,
    gpuTemp: 0,
    cpuRpm: 0,
    gpuRpm: 0,
    hwDuty: 0,
    duty: 0
  }
}

function normalizeDuties(value) {
  var duties = defaultDuties()
  if (!value || !value.length) return duties
  for (var i = 0; i < points.length; i++)
    duties[i] = clamp(value[i] === undefined ? duties[i] : value[i], 0, 100)
  return duties
}

function parseState(raw) {
  var base = defaultState()
  var data = raw
  if (typeof raw === "string") {
    if (!raw || raw.trim().length === 0) return base
    try {
      data = JSON.parse(raw)
    } catch (e) {
      return base
    }
  }
  if (!data || typeof data !== "object") return base

  base.available = data.available === true
  base.mode = typeof data.mode === "string" ? data.mode : "auto"
  base.manual = clamp(data.manual === undefined ? 40 : data.manual, 25, 100)
  base.duties = normalizeDuties(data.duties)
  base.cpuTemp = clamp(data.cpuTemp || 0, 0, 125)
  base.gpuTemp = clamp(data.gpuTemp || 0, 0, 125)
  base.cpuRpm = clamp(data.cpuRpm || 0, 0, 20000)
  base.gpuRpm = clamp(data.gpuRpm || 0, 0, 20000)
  base.hwDuty = clamp(data.hwDuty || 0, 0, 100)
  base.duty = clamp(data.duty || 0, 0, 100)
  return base
}

function curveText(duties) {
  var parts = []
  var values = normalizeDuties(duties)
  for (var i = 0; i < points.length; i++)
    parts.push(points[i] + ":" + values[i])
  return parts.join(" ")
}

function statePayload(state) {
  return JSON.stringify({
    mode: state.mode,
    manual: clamp(state.manual, 25, 100),
    duties: normalizeDuties(state.duties)
  })
}

function modeLabel(mode) {
  for (var i = 0; i < modes.length; i++) {
    if (modes[i].value === mode) return modes[i].label
  }
  return "Auto"
}

function blurb(mode) {
  if (mode === "quiet")
    return "Fans stay quiet while the machine is cool, then climb. The quiet power profile is selected."
  if (mode === "performance")
    return "Fans come up early. The performance profile is selected."
  if (mode === "curve")
    return "Set a speed for each temperature. At 95°C the fans go to full speed."
  if (mode === "manual")
    return "Holds one speed until you change it or return to Auto."
  return "The laptop controls the fans."
}

function heroMeta(state) {
  if (!state.available) return "Driver not loaded"
  var temp = state.cpuTemp > 0 ? state.cpuTemp + "°C" : "—°C"
  var rpm = state.cpuRpm > 0 ? "  ·  " + state.cpuRpm + " rpm" : ""
  return modeLabel(state.mode) + "  ·  " + temp + rpm
}
