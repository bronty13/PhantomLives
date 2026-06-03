// Ambient declaration for MediaStreamTrackProcessor — part of the
// "MediaStreamTrack Insertable Media Processing using Streams" spec
// (Chromium 94+, hence WebView2 on Windows). It is NOT yet in TypeScript's
// bundled lib.dom.d.ts, so we declare the slice we use. WebCodecs proper
// (VideoEncoder/AudioEncoder/VideoFrame/AudioData/EncodedVideoChunk…) IS in
// lib.dom and needs no shim.
interface MediaStreamTrackProcessorInit {
  track: MediaStreamTrack;
  maxBufferSize?: number;
}

declare class MediaStreamTrackProcessor<T = AudioData> {
  constructor(init: MediaStreamTrackProcessorInit);
  readonly readable: ReadableStream<T>;
}
