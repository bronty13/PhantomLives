import { describe, it, expect } from 'vitest'
import {
  PlainPayload,
  encryptPayload,
  decryptPayload,
  serializePlain,
  parsePlain,
  loadDataFile,
} from '../src/datafile/datafile'

const sample: PlainPayload = {
  format: 'rsicci-plain-1',
  instrumentVersion: 'Draft v0.1 — research-development only',
  studyId: 'ABC123',
  methodCondition: 'wording-a',
  startedAt: 1000,
  completedAt: 2000,
  moduleJOptIn: false,
  answers: {
    INT_ROMANCE_CONNECTION_APPEAL: { value: 3, displayed: true, shownAt: 1, answeredAt: 2 },
    TOP01_ROLE: { value: 'both or versatile', displayed: true },
    TOP01_DISCLOSURE: { value: ['close friend(s)', 'online community'], displayed: true },
    DFI_SAFETY: { value: null, displayed: true },
  },
  qa: { totalMs: 1000 },
}

describe('plain round-trip', () => {
  it('serialize → parse preserves the payload', () => {
    expect(parsePlain(serializePlain(sample))).toEqual(sample)
  })
  it('parsePlain rejects a non-plain file', () => {
    expect(() => parsePlain('{"format":"something-else"}')).toThrow(/plain R-SICCI/)
  })
})

describe('encrypted round-trip', () => {
  it('encrypt → decrypt with the right passphrase recovers the payload', async () => {
    const enc = await encryptPayload(sample, 'correct horse battery staple')
    expect(enc.format).toBe('rsicci-enc-1')
    expect(enc.ciphertext).not.toContain('ABC123') // study id not in clear
    const back = await decryptPayload(enc, 'correct horse battery staple')
    expect(back).toEqual(sample)
  })

  it('the wrong passphrase fails cleanly', async () => {
    const enc = await encryptPayload(sample, 'right-pass')
    await expect(decryptPayload(enc, 'wrong-pass')).rejects.toThrow(/wrong passphrase/i)
  })

  it('each export uses a fresh salt + iv', async () => {
    const a = await encryptPayload(sample, 'p')
    const b = await encryptPayload(sample, 'p')
    expect(a.kdf.salt).not.toBe(b.kdf.salt)
    expect(a.iv).not.toBe(b.iv)
    expect(a.ciphertext).not.toBe(b.ciphertext)
  })
})

describe('loadDataFile auto-detects format', () => {
  it('detects plain and returns the payload directly', () => {
    const r = loadDataFile(serializePlain(sample))
    expect(r.encrypted).toBe(false)
    expect(r.payload).toEqual(sample)
  })
  it('detects encrypted and exposes a decrypt() thunk', async () => {
    const enc = await encryptPayload(sample, 'pw')
    const r = loadDataFile(JSON.stringify(enc))
    expect(r.encrypted).toBe(true)
    expect(await r.decrypt!('pw')).toEqual(sample)
  })
  it('rejects unrecognized JSON', () => {
    expect(() => loadDataFile('{"hello":1}')).toThrow(/Unrecognized/)
  })
})
