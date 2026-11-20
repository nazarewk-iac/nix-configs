import { Plugin } from "@opencode/plugin"

// `kdn.image-budget` keeps every outgoing request inside a provider's image budget.
//
// ## The problem it solves
//
// A gateway caps how many images one request may carry. The observed caps are 30 (requesty, the
// OpenCode gateway) and 50 (Azure, the OpenCode gateway). OpenCode caps image *bytes*
// (`media.image.max_base64_bytes`, 5 MiB by default) and never the image *count*, and it does not
// classify an image-count rejection as context overflow. So a session that collects screenshots —
// a NanoKVM loop, a repeated `read` of a PNG, a multi-page PDF — reaches the cap, and from then on
// every request fails with the same 400. That includes `/compact`, the only recovery path,
// because a compaction request carries the same images. The session is bricked.
//
// ## What this plugin does
//
// The `context` hook runs after OpenCode assembles a request and before the provider sees it. The
// plugin walks the messages, keeps the newest images inside a count budget and a byte budget, and
// replaces each older image with one short text line that names the file. The prune is outgoing
// context only: the stored transcript keeps every image, so the next request starts from the same
// history and prunes again.
//
// A compaction or title request carries no images at all. A summary does not need pixels, and a
// compaction that still carries 69 images fails exactly like the request it was meant to rescue.
//
// ## How it learns the cap
//
// The cap is not in the model metadata and it differs per gateway and per route. When a request
// fails with an image-count error, the `retry` hook parses the cap out of the message
// (`Too many images in request: 69 > 30`), stores it per provider and model, and asks for one
// immediate retry. The retry rebuilds the request, so the new budget applies and the request
// passes. The learned cap survives a restart in the plugin storage.
//
// ## Configuration
//
// Values come from the plugin `options` in `opencode.json(c)`, then from the environment, then
// from the defaults below. A provider or a model overrides the global numbers:
//
// ```jsonc
// {
//   "plugins": [{
//     "package": "file:///…/kdn-image-budget.ts",
//     "options": {
//       "maxImages": 8,
//       "maxBytes": "8MiB",
//       "compaction": { "maxImages": 0 },
//       "providers": { "litellm": { "maxImages": 32, "maxBytes": "32MiB" } },
//       "models": { "requesty/deepseek-v4.1-flash-1017": { "maxImages": 6 } }
//     }
//   }]
// }
// ```
//
// A local llama.cpp server has no image-count cap, so `maxImages` there is a cost decision, not a
// safety one: every image costs roughly 1k tokens of the context window. A remote gateway needs
// the count budget; a local model needs the byte and token budget more than the count.

const MIB = 1024 * 1024

const ENV_MAX_IMAGES = "KDN_IMAGE_BUDGET_MAX_IMAGES"
const ENV_MAX_BYTES = "KDN_IMAGE_BUDGET_MAX_BYTES"
const ENV_DEBUG = "KDN_IMAGE_BUDGET_DEBUG"

// The defaults. Eight images is the rolling window the community plugins settled on, and it costs
// roughly 8k tokens of the context window. It sits far below every known gateway cap, so a fresh
// install never hits a 400.
const DEFAULT_BUDGET: Budget = { maxImages: 8, maxBytes: 8 * MIB }

// A compaction or title request keeps no image. Both must always pass, whatever the history holds.
const NO_IMAGES: Budget = { maxImages: 0, maxBytes: 0 }

// The retry hook learns the cap from these messages. Each one is a real gateway wording.
const CAP_PATTERNS: RegExp[] = [
  /too many images in request:\s*\d+\s*>\s*(\d+)/i,
  /request contains\s+\d+\s+images?,\s*exceeding the maximum of\s+(\d+)/i,
  /exceeded maximum number of images\s*\(\s*(\d+)\s*\)/i,
  /maximum of\s+(\d+)\s+images?\s+per\s+request/i,
]

type Budget = { maxImages: number; maxBytes: number }

type Options = {
  maxImages?: unknown
  maxBytes?: unknown
  compaction?: { maxImages?: unknown; maxBytes?: unknown }
  providers?: Record<string, BudgetOptions | undefined>
  models?: Record<string, BudgetOptions | undefined>
  debug?: unknown
}

type BudgetOptions = { maxImages?: unknown; maxBytes?: unknown }

// The `kdn.opencode` aspect replaces this literal with the numbers from `kdn.opencode.imageBudget`.
// A standalone copy of this file keeps the defaults below, so the source stays valid TypeScript on
// its own and the unit tests exercise the same code the aspect generates.
const EMBEDDED_OPTIONS: Options = /* @KDN_IMAGE_BUDGET_OPTIONS@ */ {}

// One image that the plugin can replace. `replace` puts the placeholder in the exact position the
// image held, so the transcript order is preserved for the model.
type Slot = {
  mime: string
  name: string | undefined
  bytes: number
  replace: (text: string) => void
}

type Stats = { total: number; kept: number; pruned: number; bytes: number }

// ---------------------------------------------------------------------------------------------
// Value parsing
// ---------------------------------------------------------------------------------------------

// A size is a number of bytes or a string such as `8MiB`, `8MB`, `512KB` or `1000`. Binary units
// win: `MB` means 1024 * 1024 here, because every value this plugin handles is a memory or payload
// size and the binary unit is the one people mean.
export function parseSize(value: unknown): number | undefined {
  if (typeof value === "number") {
    if (!Number.isFinite(value) || value < 0) return undefined
    return Math.floor(value)
  }
  if (typeof value !== "string") return undefined
  const match = /^\s*(\d+(?:\.\d+)?)\s*(b|kb|kib|mb|mib|gb|gib)?\s*$/i.exec(value)
  if (!match) return undefined
  const amount = Number(match[1])
  if (!Number.isFinite(amount)) return undefined
  const unit = (match[2] ?? "b").toLowerCase()
  const factor =
    unit === "b" ? 1 : unit === "kb" || unit === "kib" ? 1024 : unit === "mb" || unit === "mib" ? MIB : 1024 * MIB
  return Math.floor(amount * factor)
}

function parseCount(value: unknown): number | undefined {
  const size = parseSize(value)
  return size === undefined ? undefined : Math.floor(size)
}

function merge(base: Budget, ...layers: (BudgetOptions | undefined)[]): Budget {
  const out = { ...base }
  for (const layer of layers) {
    if (!layer) continue
    const images = parseCount(layer.maxImages)
    if (images !== undefined) out.maxImages = images
    const bytes = parseSize(layer.maxBytes)
    if (bytes !== undefined) out.maxBytes = bytes
  }
  return out
}

export function isImageMime(mime: unknown): boolean {
  return typeof mime === "string" && mime.toLowerCase().startsWith("image/")
}

// The wire cost of a `data:` URI is its Base64 payload, not the decoded image. That payload is what
// the request body carries, so it is the number the byte budget must count.
export function payloadBytes(uri: unknown, data?: unknown): number {
  if (typeof data === "string") return data.length
  if (typeof uri !== "string" || !uri.startsWith("data:")) return 0
  const comma = uri.indexOf(",")
  return comma < 0 ? 0 : uri.length - comma - 1
}

function humanBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < MIB) return `${Math.round(bytes / 1024)} KiB`
  return `${(bytes / MIB).toFixed(1)} MiB`
}

// ---------------------------------------------------------------------------------------------
// Collecting the images
// ---------------------------------------------------------------------------------------------

// OpenCode 2.2.5 hands the hook provider-shaped messages: `{ role, content: Part[] }`, where a part
// is `text`, `reasoning`, `tool-call` or `tool-result`, and a tool result nests its content one
// level deeper:
//
//   { type: "tool-result", name: "read", result: { type: "content", value: [
//       { type: "text", text: "Image read successfully" },
//       { type: "file", uri: "data:image/jpeg;base64,…", mime: "image/jpeg", name: "/tmp/a.jpg" },
//   ] } }
//
// A prompt attachment arrives as a `file` part in a `user` message. The domain shape — an assistant
// message whose `tool` part holds `state.content` — is handled too, so a future release that hands
// the hook the domain messages keeps working. Anything else is left alone: an unknown shape passes
// through untouched, which is the safe failure.
function isImagePart(part: any): boolean {
  if (!part || typeof part !== "object") return false
  if (part.type === "file") return isImageMime(part.mime)
  if (part.type === "image") return true
  if (part.type === "media") return part.mediaType === undefined || isImageMime(part.mediaType)
  return false
}

function partMime(part: any): string {
  if (typeof part.mime === "string") return part.mime
  if (typeof part.mediaType === "string") return part.mediaType
  return "image"
}

function partBytes(part: any): number {
  if (typeof part.uri === "string") return payloadBytes(part.uri)
  if (typeof part.data === "string") return part.data.length
  if (typeof part.image === "string") return payloadBytes(part.image, part.image.startsWith("data:") ? undefined : part.image)
  return 0
}

function partName(part: any): string | undefined {
  return typeof part.name === "string" ? part.name : undefined
}

// Every image the plugin can reach, oldest first, each with a `replace` that puts the placeholder
// in the exact position the image held.
export function collect(messages: readonly any[]): Slot[] {
  const slots: Slot[] = []

  const slotFor = (part: any, replace: (text: string) => void): Slot => ({
    mime: partMime(part),
    name: partName(part),
    bytes: partBytes(part),
    replace,
  })

  const walk = (content: any[]) => {
    for (let index = 0; index < content.length; index++) {
      const part = content[index]
      if (!part || typeof part !== "object") continue

      if (isImagePart(part)) {
        slots.push(slotFor(part, (text) => { content[index] = { type: "text", text } }))
        continue
      }

      // A tool result nests its own content array. `result` is the 2.2.5 name; `output` is the
      // upstream AI SDK name, kept for a rename that does not break this plugin.
      const nested = part.type === "tool-result" ? part.result ?? part.output : part.type === "tool" ? part.state : undefined
      if (nested && Array.isArray(nested.value)) walk(nested.value)
      else if (nested && Array.isArray(nested.content)) walk(nested.content)
    }
  }

  for (const message of messages) {
    if (!message || typeof message !== "object") continue

    // The domain shape for a prompt attachment: `{ type: "user", text, files: [...] }`.
    if (message.type === "user" && Array.isArray(message.files)) {
      for (const attachment of message.files.slice()) {
        if (!attachment || !isImageMime(attachment.mime)) continue
        const slot = slotFor(attachment, (text) => {
          const index = message.files.indexOf(attachment)
          if (index >= 0) message.files.splice(index, 1)
          message.text = typeof message.text === "string" && message.text.length > 0 ? `${message.text}\n${text}` : text
        })
        slots.push(slot)
      }
    }

    if (Array.isArray(message.content)) walk(message.content)
  }

  return slots
}

// A placeholder keeps the two facts the model needs: which file it was, and that a re-read brings it
// back. The image itself is gone, so the wording must not pretend otherwise.
export function placeholder(slot: Slot): string {
  const what = slot.name ? `${slot.name} (${slot.mime}, ${humanBytes(slot.bytes)})` : `${slot.mime}, ${humanBytes(slot.bytes)}`
  return `[image omitted from this request by the image budget: ${what}. Read the file again to look at it.]`
}

// Keep the newest images that fit both budgets, and replace every other one. The newest image is
// always kept, even when it alone exceeds the byte budget: an empty window is worse than a large
// one, and a single image never trips a count cap.
export function prune(messages: readonly any[], budget: Budget): Stats {
  const slots = collect(messages)
  const total = slots.length
  const keep = new Array<boolean>(total).fill(false)
  let kept = 0
  let bytes = 0

  for (let index = total - 1; index >= 0; index--) {
    if (kept >= budget.maxImages) break
    const slot = slots[index]
    if (kept > 0 && bytes + slot.bytes > budget.maxBytes) break
    keep[index] = true
    kept++
    bytes += slot.bytes
  }

  for (let index = 0; index < total; index++) {
    if (keep[index]) continue
    slots[index].replace(placeholder(slots[index]))
  }

  return { total, kept, pruned: total - kept, bytes }
}

// ---------------------------------------------------------------------------------------------
// Learning the cap from a rejection
// ---------------------------------------------------------------------------------------------

export function parseCap(message: unknown): number | undefined {
  if (typeof message !== "string") return undefined
  for (const pattern of CAP_PATTERNS) {
    const match = pattern.exec(message)
    if (!match) continue
    const cap = Number(match[1])
    if (Number.isFinite(cap) && cap > 0) return Math.floor(cap)
  }
  return undefined
}

function modelKey(model: any): string | undefined {
  if (!model || typeof model !== "object") return undefined
  const providerID = typeof model.providerID === "string" ? model.providerID : undefined
  const id = typeof model.id === "string" ? model.id : typeof model.modelID === "string" ? model.modelID : undefined
  if (!providerID || !id) return undefined
  return `${providerID}/${id}`
}

// ---------------------------------------------------------------------------------------------
// The plugin
// ---------------------------------------------------------------------------------------------

export default Plugin.define({
  id: "kdn.image-budget",
  async setup(ctx: any) {
    const options: Options = { ...EMBEDDED_OPTIONS, ...(ctx.options ?? {}) }
    const debug = options.debug === true || process.env[ENV_DEBUG] === "1"

    // The learned caps. A cap is a property of the gateway route, so it is keyed by provider and
    // model, and it is stored so a restart does not have to learn it again.
    const learned = new Map<string, number>()
    try {
      const page = await ctx.storage.scan({ prefix: "cap/", limit: 500 })
      for (const entry of page.entries ?? []) {
        const key = String(entry.key).slice("cap/".length)
        if (typeof entry.value === "number" && entry.value > 0) learned.set(key, entry.value)
      }
    } catch (error) {
      if (debug) console.error(`kdn.image-budget: could not read the learned caps: ${String(error)}`)
    }

    const log = (text: string) => {
      if (debug) console.log(`kdn.image-budget: ${text}`)
    }

    // The budget for one request. The layers run from the broadest to the narrowest, then the
    // learned cap wins over every configured number: a configured 24 must not survive a gateway
    // that answered `> 10`.
    const budgetFor = (model: any, kind: "context" | "generate" | "compaction" | "title"): Budget => {
      if (kind === "compaction" || kind === "title") {
        return merge(NO_IMAGES, options.compaction)
      }

      const providerID = model && typeof model.providerID === "string" ? model.providerID : undefined
      const key = modelKey(model)
      let budget = merge(DEFAULT_BUDGET, {
        maxImages: process.env[ENV_MAX_IMAGES],
        maxBytes: process.env[ENV_MAX_BYTES],
      })
      budget = merge(budget, options)
      if (providerID) budget = merge(budget, options.providers?.[providerID])
      if (key) budget = merge(budget, options.models?.[key])

      const cap = key ? learned.get(key) : undefined
      if (cap !== undefined) {
        // Two images of margin: some gateways count an image the client cannot see, and the count
        // includes any image in the system prompt or in an attachment.
        budget.maxImages = Math.min(budget.maxImages, Math.max(1, cap - 2))
      }
      return budget
    }

    const apply = (event: any, kind: "context" | "generate" | "compaction" | "title") => {
      try {
        if (!Array.isArray(event.messages) || event.messages.length === 0) return
        const budget = budgetFor(event.model, kind)
        const stats = prune(event.messages, budget)
        if (stats.pruned > 0) {
          log(
            `${kind} request: kept ${stats.kept}/${stats.total} images (${humanBytes(stats.bytes)}), ` +
              `replaced ${stats.pruned}, budget ${budget.maxImages} images / ${humanBytes(budget.maxBytes)}`,
          )
        }
      } catch (error) {
        // A prune failure must never break a request: an unpruned request is the state before this
        // plugin existed, which is better than a request that never leaves the process.
        console.error(`kdn.image-budget: prune failed for a ${kind} request: ${String(error)}`)
      }
    }

    // Each hook registers on its own. A renamed or removed hook in a future release must cost that
    // one hook, never the whole plugin: the `context` prune is the safety net, and it must survive a
    // `title` or `retry` rename.
    const register = async (name: string, handler: (event: any) => unknown) => {
      try {
        await ctx.session.hook(name, handler)
      } catch (error) {
        console.error(`kdn.image-budget: could not register the ${name} hook: ${String(error)}`)
      }
    }

    await register("context", (event: any) => apply(event, "context"))
    await register("generate", (event: any) => apply(event, "generate"))
    await register("compaction", (event: any) => apply(event, "compaction"))
    await register("title", (event: any) => apply(event, "title"))

    // The retry hook. It runs after OpenCode classifies a failure and before any retry is
    // scheduled, so it is the only place that can turn a bricked session back into a working one
    // without the user sending another prompt.
    const forced = new Set<string>()
    await register("retry", async (event: any) => {
      try {
        const cap = parseCap(event.error?.message)
        if (cap === undefined) return

        const key = modelKey(event.model)
        if (key && learned.get(key) !== cap) {
          learned.set(key, cap)
          log(`learned the image cap ${cap} for ${key}`)
          try {
            await ctx.storage.set(`cap/${key}`, cap)
          } catch (error) {
            log(`could not store the cap for ${key}: ${String(error)}`)
          }
        }

        // One forced retry per session and cap. The retry rebuilds the request, so the new budget
        // applies; a second failure means the cap is not the whole story, and the error goes back
        // to the user instead of a loop.
        const guard = `${event.sessionID}/${cap}`
        if (forced.has(guard)) return
        if (typeof event.attempt === "number" && event.attempt > 2) return
        forced.add(guard)
        event.decision = { retry: true, delay: 0 }
      } catch (error) {
        console.error(`kdn.image-budget: retry hook failed: ${String(error)}`)
      }
    })
  },
})
