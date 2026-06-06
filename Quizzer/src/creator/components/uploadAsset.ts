import type { AssetRef } from '../../shared/model';

/** Read a picked File into an inline (base64 data-URI) AssetRef. */
export function fileToAssetRef(file: File): Promise<AssetRef> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(reader.error ?? new Error('Read failed'));
    reader.onload = () =>
      resolve({
        kind: 'inline',
        mime: file.type || 'application/octet-stream',
        dataUri: String(reader.result),
        name: file.name,
      });
    reader.readAsDataURL(file);
  });
}
