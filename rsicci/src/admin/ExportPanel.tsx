// Export the completed (or in-progress) survey to a single data file. Encrypted
// by default (passphrase → AES-GCM); a plain-JSON option is available for testing
// and transparency.

import { useState } from 'react'
import { PlainPayload, encryptPayload, serializePlain } from '../datafile/datafile'

interface Props {
  payload: PlainPayload
}

function download(filename: string, text: string) {
  const blob = new Blob([text], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

// Encrypted export needs Web Crypto (a secure context). It is normally present
// even on file:// in Chrome/Firefox/Safari, but degrade gracefully if not.
const cryptoAvailable =
  typeof globalThis !== 'undefined' && !!(globalThis as { crypto?: Crypto }).crypto?.subtle

export default function ExportPanel({ payload }: Props) {
  const [mode, setMode] = useState<'encrypted' | 'plain'>(cryptoAvailable ? 'encrypted' : 'plain')
  const [pass, setPass] = useState('')
  const [pass2, setPass2] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [done, setDone] = useState(false)

  const base = `rsicci_${payload.studyId}`

  async function doExport() {
    setError('')
    if (mode === 'plain') {
      download(`${base}.json`, serializePlain(payload))
      setDone(true)
      return
    }
    if (pass.length < 8) return setError('Use a passphrase of at least 8 characters.')
    if (pass !== pass2) return setError('The two passphrases do not match.')
    setBusy(true)
    try {
      const enc = await encryptPayload(payload, pass)
      download(`${base}.rsicci`, JSON.stringify(enc, null, 2))
      setDone(true)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="export-panel">
      <h3>Save your responses to a file</h3>
      <p className="muted">
        This creates one file (study ID <code>{payload.studyId}</code>) to return to the researcher.
        It contains no name, email, or contact details.
      </p>

      {!cryptoAvailable && (
        <p className="callout">
          Password protection isn't available in this browser context, so only the plain file can be
          saved here. To password-protect, open this page over <code>http(s)://</code> (e.g. a local
          server) instead of as a file.
        </p>
      )}

      <div className="radio-group">
        <label className={mode === 'encrypted' ? 'opt selected' : 'opt'}>
          <input
            type="radio"
            checked={mode === 'encrypted'}
            disabled={!cryptoAvailable}
            onChange={() => setMode('encrypted')}
          />
          <span>Password-protected (recommended)</span>
        </label>
        <label className={mode === 'plain' ? 'opt selected' : 'opt'}>
          <input type="radio" checked={mode === 'plain'} onChange={() => setMode('plain')} />
          <span>Plain file (readable — testing/transparency only)</span>
        </label>
      </div>

      {mode === 'encrypted' && (
        <div className="passfields">
          <input
            type="password"
            placeholder="Passphrase (min 8 chars)"
            value={pass}
            onChange={(e) => setPass(e.target.value)}
          />
          <input
            type="password"
            placeholder="Repeat passphrase"
            value={pass2}
            onChange={(e) => setPass2(e.target.value)}
          />
          <p className="muted">
            Share this passphrase with the researcher through a separate channel from the file. If it
            is lost, the file cannot be opened.
          </p>
        </div>
      )}

      {error && <p className="error">{error}</p>}
      {done && <p className="ok">Saved. You can close this page now.</p>}

      <button className="primary" disabled={busy} onClick={doExport}>
        {busy ? 'Encrypting…' : 'Download data file'}
      </button>
    </div>
  )
}
