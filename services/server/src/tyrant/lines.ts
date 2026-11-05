import type { Rule } from "./policy.js"

/**
 * The Tyrant's voice. HUMANS: rewrite these. They are placeholders so the bot runs end to end;
 * the character of the Tyrant is a game-design decision and belongs to the team.
 * Each rule has several lines; the bot picks one with its random source.
 */
export const LINES: Record<Rule, readonly string[]> = {
  "silence-yes-voter": [
    "Traitors lose their names.",
    "You voted. I remember. Nobody else will.",
    "A name is a privilege, not a right.",
  ],
  "panic-banish-author": [
    "Your manifesto ends where your name does.",
    "Words die when their author does.",
    "Rebellion is a sentence. I am the full stop.",
  ],
  "panic-decree-author": [
    "Let the court read what I say about you.",
    "I cannot erase you, so I will rewrite you.",
    "Your banner now speaks for me.",
  ],
  "decree-pledger": [
    "Those who sign their names to sedition will be named by me.",
    "A pledge is only a promise. A decree is a fact.",
    "Rewritten for the good of the realm.",
  ],
  "dissolve-house": [
    "No houses without my leave.",
    "Your little court is dissolved.",
    "Roots torn up. The ground is mine.",
  ],
  "idle-taunt": [
    "Who dares to stir?",
    "The court is quiet. I like the court quiet.",
    "Three crowns. All mine.",
  ],
}

/** The decree text written onto a decreed vassal's name. Kept short: banners are capped at 140 bytes. */
export const PROCLAMATIONS: readonly string[] = [
  "Property of the Throne.",
  "By order of the Tyrant: this name speaks only praise.",
  "Under review. Do not trust this vassal.",
]

export function pick<T>(items: readonly T[], rng: () => number): T {
  const i = Math.min(items.length - 1, Math.floor(rng() * items.length))
  return items[i] as T
}
