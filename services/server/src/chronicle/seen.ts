import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"

/** Persisted set of source-log ids already written to the Chronicle, so restarts never duplicate. */
export class SeenStore {
  private seen: Set<string>
  constructor(private readonly path: string) {
    try {
      this.seen = new Set(JSON.parse(readFileSync(path, "utf8")) as string[])
    } catch {
      this.seen = new Set()
    }
  }
  has(key: string): boolean {
    return this.seen.has(key)
  }
  /** Marks keys as written and saves to disk. Call only after the Arkiv write succeeded. */
  add(keys: readonly string[]): void {
    for (const k of keys) this.seen.add(k)
    mkdirSync(dirname(this.path), { recursive: true })
    writeFileSync(this.path, JSON.stringify([...this.seen]))
  }
  get size(): number {
    return this.seen.size
  }
}
