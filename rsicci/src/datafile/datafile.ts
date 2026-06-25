// The travelling data file: export from the participant's copy, import into the
// researcher's scoring copy. Two on-disk shapes:
//
//   • rsicci-plain-1  — readable JSON (for testing / transparency)
//   • rsicci-enc-1    — AES-GCM payload, key derived from a passphrase via PBKDF2
//
// The file deliberately contains NO direct identifiers — only a generated study
// ID, the instrument version, the method condition, the answers (value +
// display-state), and timing/QA. Recruitment/contact data lives elsewhere, per
// the instrument's data-separation rule.

import { AnswerValue } from '../instrument/coding'

export interface StoredAnswer {
  value: AnswerValue
  /** Was the item shown to the participant? (drives eligibility denominators) */
  displayed: boolean
  shownAt?: number
  answeredAt?: number
}

export interface PlainPayload {
  format: 'rsicci-plain-1'
  instrumentVersion: string
  studyId: string
  methodCondition: string
  startedAt: number | null
  completedAt: number | null
  moduleJOptIn: boolean
  answers: Record<string, StoredAnswer>
  qa: {
    attention?: AnswerValue
    /** Total elapsed survey time in ms, and per-module dwell times. */
    totalMs?: number
    moduleMs?: Record<string, number>
  }
}

export interface EncryptedFile {
  format: 'rsicci-enc-1'
  kdf: { name: 'PBKDF2'; hash: 'SHA-256'; iterations: number; salt: string }
  iv: string
  ciphertext: string
}

const PBKDF2_ITERATIONS = 210_000

// ---- base64 helpers (browser + Node both expose atob/btoa on globalThis) -----

function bytesToB64(bytes: Uint8Array): string {
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin)
}

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

function subtle(): SubtleCrypto {
  const c = (globalThis as { crypto?: Crypto }).crypto
  if (!c?.subtle) throw new Error('Web Crypto API is unavailable in this environment.')
  return c.subtle
}

// Copy bytes into a fresh, plain ArrayBuffer. Web Crypto wants ArrayBuffer-backed
// BufferSource, while TS 5.7 types byte views over the wider ArrayBufferLike.
function buf(u: Uint8Array): ArrayBuffer {
  const out = new ArrayBuffer(u.byteLength)
  new Uint8Array(out).set(u)
  return out
}

function randomBytes(n: number): Uint8Array {
  const out = new Uint8Array(n)
  ;(globalThis as { crypto: Crypto }).crypto.getRandomValues(out)
  return out
}

// ---- Plain export / import --------------------------------------------------

export function serializePlain(payload: PlainPayload): string {
  return JSON.stringify(payload, null, 2)
}

export function parsePlain(text: string): PlainPayload {
  const obj = JSON.parse(text)
  if (obj?.format !== 'rsicci-plain-1') {
    throw new Error('Not a plain R-SICCI data file (expected format "rsicci-plain-1").')
  }
  return obj as PlainPayload
}

// ---- Encrypted export / import ----------------------------------------------

async function deriveKey(password: string, salt: Uint8Array, iterations: number): Promise<CryptoKey> {
  const baseKey = await subtle().importKey('raw', buf(new TextEncoder().encode(password)), 'PBKDF2', false, ['deriveKey'])
  return subtle().deriveKey(
    { name: 'PBKDF2', salt: buf(salt), iterations, hash: 'SHA-256' },
    baseKey,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  )
}

export async function encryptPayload(payload: PlainPayload, password: string): Promise<EncryptedFile> {
  if (!password) throw new Error('A passphrase is required to encrypt the data file.')
  const salt = randomBytes(16)
  const iv = randomBytes(12)
  const key = await deriveKey(password, salt, PBKDF2_ITERATIONS)
  const plaintext = new TextEncoder().encode(serializePlain(payload))
  const cipher = await subtle().encrypt({ name: 'AES-GCM', iv: buf(iv) }, key, buf(plaintext))
  return {
    format: 'rsicci-enc-1',
    kdf: { name: 'PBKDF2', hash: 'SHA-256', iterations: PBKDF2_ITERATIONS, salt: bytesToB64(salt) },
    iv: bytesToB64(iv),
    ciphertext: bytesToB64(new Uint8Array(cipher)),
  }
}

export async function decryptPayload(file: EncryptedFile, password: string): Promise<PlainPayload> {
  if (file?.format !== 'rsicci-enc-1') {
    throw new Error('Not an encrypted R-SICCI data file (expected format "rsicci-enc-1").')
  }
  const salt = b64ToBytes(file.kdf.salt)
  const iv = b64ToBytes(file.iv)
  const key = await deriveKey(password, salt, file.kdf.iterations)
  let plaintext: ArrayBuffer
  try {
    plaintext = await subtle().decrypt({ name: 'AES-GCM', iv: buf(iv) }, key, buf(b64ToBytes(file.ciphertext)))
  } catch {
    throw new Error('Could not decrypt — wrong passphrase or the file is corrupted.')
  }
  return parsePlain(new TextDecoder().decode(plaintext))
}

// ---- Unified import (auto-detect plain vs encrypted) ------------------------

export interface ImportResult {
  encrypted: boolean
  /** Present immediately for plain files; for encrypted files, call decrypt(). */
  payload?: PlainPayload
  decrypt?: (password: string) => Promise<PlainPayload>
}

export function loadDataFile(text: string): ImportResult {
  let obj: { format?: string }
  try {
    obj = JSON.parse(text)
  } catch {
    throw new Error('File is not valid JSON.')
  }
  if (obj?.format === 'rsicci-enc-1') {
    const file = obj as unknown as EncryptedFile
    return { encrypted: true, decrypt: (password) => decryptPayload(file, password) }
  }
  if (obj?.format === 'rsicci-plain-1') {
    return { encrypted: false, payload: obj as unknown as PlainPayload }
  }
  throw new Error('Unrecognized file — not an R-SICCI data file.')
}
