import Foundation
import AVFoundation

/// Command-line interface entry point. Dispatched from `MainEntry`
/// when argv[1] looks like a CLI subcommand.
///
/// Usage:
///
///   purplevoice clean <input> [options]
///   purplevoice help
///   purplevoice version
///
/// Options (all default to the GUI's persisted preferences when
/// omitted, so power users can run `purplevoice clean foo.m4a` and
/// get exactly what the GUI would have produced):
///
///   -o, --output <path>            Override the output path. Without
///                                   this, lands in ~/Downloads/PurpleVoice/.
///   -p, --profile <name>           light | medium | aggressive
///       --no-enhance               Disable the dynamics chain.
///   -e, --engine <name>            ffmpeg | deepfilter
///       --lufs <preset>            off | podcast | streaming | broadcast
///       --de-esser / --no-de-esser
///       --de-clicker / --no-de-clicker
///       --stereo / --mono
///       --dereverb / --no-dereverb (DeepFilterNet only)
///       --trim <start>:<end>       Seconds; either side may be empty.
///   -f, --format <name>            m4a | mp3 | wav
///       --quiet                    No progress reporting.
///
/// Fine-tuning (overrides profile defaults; pass any subset):
///       --highpass-hz <N>          High-pass cutoff (default: 80)
///       --denoise-db <N>           afftdn noise reduction (default: 8/12/20)
///       --de-esser-intensity <N>   0–1; only meaningful with --de-esser
///       --compressor-threshold-db <N>   acompressor threshold (default: -22)
///       --compressor-ratio <N>     N:1 ratio (default: 3)
///       --limiter-ceiling <N>      alimiter limit, 0–1 (default: 0.97)
enum CLI {

    static func run(args: [String]) async {
        guard let first = args.first else {
            printUsage()
            return
        }
        switch first {
        case "help", "-h", "--help":
            printUsage()
        case "version", "-v", "--version":
            print("PurpleVoice \(AppVersion.short) (build \(AppVersion.build))")
        case "presets":
            printPresets()
        case "clean":
            await runClean(args: Array(args.dropFirst()))
        default:
            fputs("Unknown command: \(first)\n\n", stderr)
            printUsage()
            exit(2)
        }
    }

    private static func printUsage() {
        print("""
        PurpleVoice — voice isolation & enhancement.

        Usage:
          purplevoice clean <input> [options]
          purplevoice presets
          purplevoice help
          purplevoice version

        Options:
          -o, --output <path>          Output file path (default: ~/Downloads/PurpleVoice/)
              --preset <name>          Start from a saved preset (see `purplevoice presets`);
                                       any other flags below override the preset
          -p, --profile <name>         light | medium | aggressive (default: medium)
              --no-enhance             Skip the dynamics chain (compression/limiter)
          -e, --engine <name>          ffmpeg | deepfilter (default: ffmpeg)
              --lufs <preset>          off | podcast | streaming | broadcast (default: off)
              --de-esser               Enable sibilance reduction
              --de-clicker             Enable click / pop removal
              --stereo                 Preserve stereo (default: downmix to mono)
              --dereverb               Reduce reverb (DeepFilterNet engine only)
              --trim <start>:<end>     Trim window in seconds (e.g. 1.5:30.0, :15, 5:)
          -f, --format <name>          m4a | mp3 | wav (default: m4a)
              --quiet                  Suppress progress output

        Fine-tuning (pass any subset; each overrides its profile default):
              --highpass-hz <N>                  High-pass cutoff Hz (default 80)
              --denoise-db <N>                   afftdn noise reduction (default 8/12/20 per profile)
              --de-esser-intensity <N>           0–1 (default 0.4; only with --de-esser)
              --compressor-threshold-db <N>      acompressor threshold (default -22)
              --compressor-ratio <N>             N:1 ratio (default 3)
              --limiter-ceiling <N>              alimiter limit 0–1 (default 0.97)

        Examples:
          purplevoice clean memo.m4a
          purplevoice clean talk.mp4 -o talk_clean.wav -p aggressive --lufs podcast
          purplevoice clean interview.wav --engine deepfilter --dereverb --stereo
          purplevoice clean memo.m4a --preset Podcast
          purplevoice clean memo.m4a --preset Podcast --denoise-db 18
        """)
    }

    /// `purplevoice presets` — list the available presets (built-in +
    /// any the user saved in the app). Names with spaces need quoting
    /// when passed to `--preset`.
    private static func printPresets() {
        print("Built-in presets:")
        for p in Preset.builtIns { print("  \(p.name)") }
        let user = PresetStore().userPresets
        if !user.isEmpty {
            print("\nYour presets:")
            for p in user { print("  \(p.name)") }
        }
        print("\nApply one with: purplevoice clean <input> --preset \"<name>\"")
    }

    private static func runClean(args: [String]) async {
        var input: String?
        var output: String?
        var profile: ProcessingProfile = .medium
        var enhancement: Bool = true
        var engine: ProcessingEngine = .ffmpegOnly
        var lufs: LoudnessTarget = .none
        var deEsser: Bool = false
        var deClicker: Bool = false
        var preserveStereo: Bool = false
        var dereverb: Bool = false
        var trimStart: Double?
        var trimEnd: Double?
        var format: OutputFormat = .m4a
        var quiet: Bool = false
        var tuning = FilterTuning.inherited

        // `--preset` seeds the defaults before the regular flags are
        // parsed, so any explicit flag (in any position) overrides the
        // preset. Resolve it up front and apply it as the base.
        if let presetName = valueAfter("--preset", in: args) {
            guard let preset = resolvePreset(named: presetName) else {
                bail("Unknown preset: \(presetName). Run `purplevoice presets` to list them.")
            }
            profile        = preset.profile
            enhancement    = preset.enhancementEnabled
            engine         = preset.engine
            lufs           = preset.loudnessTarget
            deEsser        = preset.deEsserEnabled
            deClicker      = preset.deClickerEnabled
            preserveStereo = preset.preserveStereo
            dereverb       = preset.dereverbEnabled
            tuning         = preset.tuning
        }

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--preset":
                // Already applied as the base above; just consume its
                // value here so it isn't treated as the input file.
                i += 1
            case "-o", "--output":
                i += 1; output = args[safe: i]
            case "-p", "--profile":
                i += 1
                guard let v = args[safe: i],
                      let p = ProcessingProfile(rawValue: v) else {
                    bail("--profile must be one of: light, medium, aggressive")
                }
                profile = p
            case "--no-enhance":
                enhancement = false
            case "-e", "--engine":
                i += 1
                switch args[safe: i] ?? "" {
                case "ffmpeg":     engine = .ffmpegOnly
                case "deepfilter": engine = .deepFilterNet
                default: bail("--engine must be one of: ffmpeg, deepfilter")
                }
            case "--lufs":
                i += 1
                switch args[safe: i] ?? "" {
                case "off":       lufs = .none
                case "podcast":   lufs = .podcast
                case "streaming": lufs = .streaming
                case "broadcast": lufs = .broadcast
                default: bail("--lufs must be one of: off, podcast, streaming, broadcast")
                }
            case "--de-esser":      deEsser = true
            case "--no-de-esser":   deEsser = false
            case "--de-clicker":    deClicker = true
            case "--no-de-clicker": deClicker = false
            case "--stereo":        preserveStereo = true
            case "--mono":          preserveStereo = false
            case "--dereverb":      dereverb = true
            case "--no-dereverb":   dereverb = false
            case "--trim":
                i += 1
                guard let v = args[safe: i],
                      let parsed = parseTrim(v) else {
                    bail("--trim must look like <start>:<end> in seconds (either side may be empty)")
                }
                trimStart = parsed.start
                trimEnd = parsed.end
            case "-f", "--format":
                i += 1
                guard let v = args[safe: i],
                      let f = OutputFormat(rawValue: v) else {
                    bail("--format must be one of: m4a, mp3, wav")
                }
                format = f
            case "--quiet":
                quiet = true
            case "--highpass-hz":
                i += 1; tuning.highpassHz = parseDouble(args[safe: i],
                                                        flag: arg,
                                                        range: FilterTuning.Bounds.highpassHz)
            case "--denoise-db":
                i += 1; tuning.afftdnNR = parseDouble(args[safe: i],
                                                      flag: arg,
                                                      range: FilterTuning.Bounds.afftdnNR)
            case "--de-esser-intensity":
                i += 1; tuning.deEsserIntensity = parseDouble(args[safe: i],
                                                              flag: arg,
                                                              range: FilterTuning.Bounds.deEsserIntensity)
            case "--compressor-threshold-db":
                i += 1; tuning.compressorThresholdDB = parseDouble(args[safe: i],
                                                                    flag: arg,
                                                                    range: FilterTuning.Bounds.compressorThresholdDB)
            case "--compressor-ratio":
                i += 1; tuning.compressorRatio = parseDouble(args[safe: i],
                                                              flag: arg,
                                                              range: FilterTuning.Bounds.compressorRatio)
            case "--limiter-ceiling":
                i += 1; tuning.limiterCeiling = parseDouble(args[safe: i],
                                                             flag: arg,
                                                             range: FilterTuning.Bounds.limiterCeiling)
            default:
                if arg.hasPrefix("-") {
                    bail("Unknown flag: \(arg)")
                }
                if input != nil {
                    bail("Multiple inputs not supported. Pass one file at a time.")
                }
                input = arg
            }
            i += 1
        }

        guard let input else {
            bail("Missing input file. Try `purplevoice help`.")
        }
        let sourceURL = URL(fileURLWithPath: input)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            bail("Input not found: \(sourceURL.path)")
        }

        let outputURL: URL
        if let output {
            outputURL = URL(fileURLWithPath: output)
            let dir = outputURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir,
                                                      withIntermediateDirectories: true)
        } else {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads/PurpleVoice",
                                        isDirectory: true)
            try? FileManager.default.createDirectory(at: dir,
                                                      withIntermediateDirectories: true)
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            outputURL = dir.appendingPathComponent(
                "\(stem)_clean.\(format.fileExtension)"
            )
        }

        let options = ProcessingOptions(
            profile: profile,
            enhancementEnabled: enhancement,
            engine: engine,
            loudnessTarget: lufs,
            deEsserEnabled: deEsser,
            deClickerEnabled: deClicker,
            preserveStereo: preserveStereo,
            dereverbEnabled: dereverb,
            outputFormat: format,
            deepFilterPathOverride: nil,
            trimStart: trimStart,
            trimEnd: trimEnd,
            tuning: tuning
        )

        let clip = Clip(sourceURL: sourceURL)
        let processor = ClipProcessor()
        let lastPrinted = LastPrintedPercent()

        if !quiet {
            print("Cleaning \(sourceURL.lastPathComponent) → \(outputURL.lastPathComponent)")
        }
        let quietCapture = quiet
        do {
            try await processor.process(
                clip: clip,
                options: options,
                outputURL: outputURL
            ) { p in
                guard !quietCapture else { return }
                let pct = Int(p * 100)
                if lastPrinted.update(to: pct) {
                    fputs("\rProgress: \(pct)%  ", stderr)
                }
            }
            if !quiet {
                fputs("\rProgress: 100%       \n", stderr)
                print("Done: \(outputURL.path)")
            } else {
                print(outputURL.path)
            }
        } catch let err as ClipProcessorError {
            fputs("\nError: \(err.userMessage)\n", stderr)
            exit(1)
        } catch {
            fputs("\nError: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    /// Parse `--trim` syntax. Accepted forms:
    ///   "1.5:30.0"  → start=1.5, end=30.0
    ///   ":15"       → start=nil, end=15
    ///   "5:"        → start=5, end=nil
    static func parseTrim(_ raw: String) -> (start: Double?, end: Double?)? {
        let parts = raw.split(separator: ":",
                               maxSplits: 1,
                               omittingEmptySubsequences: false)
                       .map(String.init)
        guard parts.count == 2 else { return nil }
        let start: Double? = parts[0].isEmpty
            ? nil
            : Double(parts[0])
        let end: Double? = parts[1].isEmpty
            ? nil
            : Double(parts[1])
        // Reject "::" or "abc:5" type inputs where one side was
        // provided but failed to parse.
        if !parts[0].isEmpty && start == nil { return nil }
        if !parts[1].isEmpty && end == nil { return nil }
        if let s = start, let e = end, s >= e { return nil }
        return (start, end)
    }

    /// Return the token immediately following the first occurrence of
    /// `flag` in `args`, or nil if `flag` is absent or trailing.
    static func valueAfter(_ flag: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    /// Resolve a preset by name for the CLI — user presets (from the
    /// shared app UserDefaults) take precedence over a built-in of the
    /// same name, matching the GUI's `PresetStore`.
    static func resolvePreset(named name: String) -> Preset? {
        PresetStore().preset(named: name)
    }

    private static func bail(_ msg: String) -> Never {
        fputs("Error: \(msg)\n", stderr)
        exit(2)
    }

    /// Parse a Double argument, validating against the documented
    /// sensible range. Exits with an error message on bad input —
    /// no silent clamping (would surprise users debugging their
    /// chain).
    static func parseDouble(_ raw: String?,
                            flag: String,
                            range: ClosedRange<Double>) -> Double {
        guard let raw, let v = Double(raw) else {
            bail("\(flag) requires a number")
        }
        guard range.contains(v) else {
            bail("\(flag) must be in [\(range.lowerBound)…\(range.upperBound)]; got \(v)")
        }
        return v
    }

    /// Simple debounce helper so we don't reflow stderr on every
    /// ffmpeg progress tick.
    private final class LastPrintedPercent {
        private var last: Int = -1
        func update(to pct: Int) -> Bool {
            guard pct != last else { return false }
            last = pct
            return true
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
