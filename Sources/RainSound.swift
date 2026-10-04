import AVFoundation
import CoreAudio

/// Sonido de lluvia sintetizado en tiempo real (sin ficheros de audio):
/// - murmullo: ruido blanco filtrado, más brillante cuanto más llueve;
/// - cuerpo: ruido marrón grave para la lluvia fuerte;
/// - gotas: impactos cortos con un filtro resonante, a un ritmo que sube con la intensidad;
/// - truenos: ruido muy grave con una envolvente larga, unos segundos después del relámpago.
///
/// Se silencia solo mientras otra app usa el micrófono (p. ej. en una llamada). Para saberlo
/// pregunta a Core Audio si algún proceso tiene la entrada abierta; nunca abre el micrófono.
final class RainSound {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let synth = RainSynth()
    private var micTimer: Timer?
    private var configObserver: NSObjectProtocol?
    private(set) var isPlaying = false

    /// De 0 a 1, la misma escala que la intensidad de la lluvia.
    var intensity: Double = 0.5 { didSet { synth.targetIntensity = Float(intensity) } }
    /// De 0 a 1.
    var volume: Double = 0.5 { didSet { synth.targetVolume = Float(volume * volume) } }
    /// De 0 a 1: cuánto suena «bajo el agua» (sigue al nivel de la inundación).
    var muffle: Double = 0 { didSet { synth.targetMuffle = Float(muffle) } }

    init() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // Cambió la salida (auriculares, AirPods…): se rehace el grafo con la nueva frecuencia.
            guard let self, self.isPlaying else { return }
            self.isPlaying = false
            self.play()
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    func play() {
        guard !isPlaying else { return }
        if let source {
            engine.detach(source)
        }
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        synth.prepare(sampleRate: Float(sampleRate))

        let synth = self.synth
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        source = node

        do {
            try engine.start()
            isPlaying = true
        } catch {
            NSLog("RainDesktop: no se pudo iniciar el audio: \(error)")
            return
        }
        updateDucking()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.updateDucking() }
        RunLoop.main.add(timer, forMode: .common)
        micTimer = timer
    }

    func stop() {
        micTimer?.invalidate()
        micTimer = nil
        guard isPlaying else { return }
        isPlaying = false
        engine.stop()
    }

    /// Programa un trueno; el retraso aleatorio lo pone el propio sintetizador.
    func thunder() {
        guard isPlaying else { return }
        synth.requestThunder()
    }

    private var ducked: Bool?

    private func updateDucking() {
        let recording = Self.otherAppIsRecording()
        if recording != ducked {
            ducked = recording
            NSLog("RainDesktop: %@", recording ? "micrófono en uso, lluvia en silencio" : "sonido de lluvia activo")
        }
        synth.targetDuck = recording ? 0 : 1
    }

    // MARK: - Micrófono en uso

    /// Servicios del sistema que tienen el micrófono abierto siempre («Oye Siri», Reconocimiento
    /// de sonidos…). No indican una llamada, así que no silencian la lluvia.
    private static let alwaysListening: Set<String> = [
        "com.apple.CoreSpeech", "com.apple.corespeechd", "com.apple.assistantd",
        "com.apple.SiriNCService", "com.apple.accessibility.heard",
    ]

    private static func otherAppIsRecording() -> Bool {
        guard #available(macOS 14.2, *) else { return false }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return false }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        for process in processes {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &runningSize, &running) == noErr,
                  running != 0 else { continue }

            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(process, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid == ownPID {
                continue
            }
            if let bundleID = bundleIdentifier(of: process), alwaysListening.contains(bundleID) {
                continue
            }
            return true
        }
        return false
    }

    @available(macOS 14.2, *)
    private static func bundleIdentifier(of process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}

/// Estado del sintetizador. `render` corre en el hilo de audio en tiempo real: no reserva memoria
/// ni bloquea. Los parámetros `target*` los escribe el hilo principal y aquí se suavizan.
private final class RainSynth {
    var targetIntensity: Float = 0.5
    var targetVolume: Float = 0.25
    var targetDuck: Float = 1
    var targetMuffle: Float = 0
    private var muffle: Float = 0
    private var muffleL: Float = 0, muffleR: Float = 0

    private var thunderRequests = 0
    private var thunderHandled = 0
    func requestThunder() { thunderRequests &+= 1 }

    private var sampleRate: Float = 48_000
    private var intensity: Float = 0
    private var volume: Float = 0
    private var duck: Float = 1
    private var smoothing: Float = 0.0005

    private var rng: UInt32 = 0x9E37_79B9

    // Murmullo
    private var washLowL: Float = 0, washLowR: Float = 0
    private var washHighL: Float = 0, washHighR: Float = 0
    private var hpCoef: Float = 0
    // Cuerpo
    private var brownL: Float = 0, brownR: Float = 0
    private var bodyLowL: Float = 0, bodyLowR: Float = 0
    private var bodyCoef: Float = 0

    // Gotas: banco fijo de voces con un filtro de variable de estado cada una.
    private struct Voice {
        var env: Float = 0, decay: Float = 0, f: Float = 0, q: Float = 0
        var low: Float = 0, band: Float = 0, panL: Float = 0, panR: Float = 0
    }
    private var voices = [Voice](repeating: Voice(), count: 24)
    private var nextVoice = 0

    // Trueno
    private var thunderDelay = -1
    private var thunderEnv: Float = 0
    private var thunderAttack = false
    private var thunderPeak: Float = 0
    private var thunderLow: Float = 0, thunderLow2: Float = 0
    private var thunderMod: Float = 0
    private var thunderAttackCoef: Float = 0, thunderDecayCoef: Float = 0

    func prepare(sampleRate: Float) {
        self.sampleRate = sampleRate
        smoothing = 1 - exp(-1 / (0.08 * sampleRate))
        hpCoef = Self.onePole(cutoff: 250, sampleRate: sampleRate)
        bodyCoef = Self.onePole(cutoff: 500, sampleRate: sampleRate)
        thunderAttackCoef = 1 - exp(-1 / (0.25 * sampleRate))
        thunderDecayCoef = exp(-1 / (2.8 * sampleRate))
    }

    private static func onePole(cutoff: Float, sampleRate: Float) -> Float {
        1 - exp(-2 * .pi * cutoff / sampleRate)
    }

    /// Ruido blanco uniforme en [-1, 1] (xorshift).
    @inline(__always) private func noise() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(rng) / Float(UInt32.max) * 2 - 1
    }

    @inline(__always) private func random01() -> Float { noise() * 0.5 + 0.5 }

    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        if thunderRequests != thunderHandled {
            thunderHandled = thunderRequests
            if thunderDelay < 0 && thunderEnv < 0.05 {
                thunderDelay = Int((0.6 + random01() * 2.4) * sampleRate)
                thunderPeak = 0.6 + random01() * 0.4
            }
        }

        // Los parámetros que dependen de la intensidad se recalculan una vez por bloque.
        let i = intensity
        let washCoef = Self.onePole(cutoff: 2200 + 4500 * i, sampleRate: sampleRate)
        let washGain: Float = 0.12 + 0.55 * i
        let bodyGain: Float = 1.6 * i * i
        let dropRate: Float = 25 + 900 * i * i
        let dropChance = dropRate / sampleRate
        // Bajo el agua: paso bajo que va de ~16 kHz (seco) a ~400 Hz (pantalla llena).
        muffle += (targetMuffle - muffle) * min(1, Float(frames) / (0.05 * sampleRate))
        let muffleCoef = Self.onePole(cutoff: 16_000 * pow(400 / 16_000, muffle), sampleRate: sampleRate)

        for n in 0..<frames {
            intensity += (targetIntensity - intensity) * smoothing
            volume += (targetVolume - volume) * smoothing
            duck += (targetDuck - duck) * smoothing * 0.25

            // Murmullo: paso bajo (brillo según intensidad) y paso alto para quitar graves.
            let wl = noise(), wr = noise()
            washLowL += washCoef * (wl - washLowL)
            washLowR += washCoef * (wr - washLowR)
            washHighL += hpCoef * (washLowL - washHighL)
            washHighR += hpCoef * (washLowR - washHighR)
            var l = (washLowL - washHighL) * washGain
            var r = (washLowR - washHighR) * washGain

            // Cuerpo grave.
            brownL = (brownL + 0.02 * noise()) * 0.997
            brownR = (brownR + 0.02 * noise()) * 0.997
            bodyLowL += bodyCoef * (brownL - bodyLowL)
            bodyLowR += bodyCoef * (brownR - bodyLowR)
            l += bodyLowL * bodyGain
            r += bodyLowR * bodyGain

            // Gotas.
            if random01() < dropChance {
                let freq: Float = 900 + random01() * random01() * 5200
                let pan = random01()
                voices[nextVoice] = Voice(
                    env: 0.15 + random01() * 0.5,
                    decay: exp(-1 / ((0.003 + random01() * 0.012) * sampleRate)),
                    f: 2 * sin(.pi * min(freq, sampleRate * 0.2) / sampleRate),
                    q: 0.12 + random01() * 0.2,
                    low: 0, band: 0,
                    panL: (1 - pan).squareRoot(), panR: pan.squareRoot()
                )
                nextVoice = (nextVoice + 1) % voices.count
            }
            for v in 0..<voices.count where voices[v].env > 0.0005 {
                let input = noise() * voices[v].env
                voices[v].low += voices[v].f * voices[v].band
                let high = input - voices[v].low - voices[v].q * voices[v].band
                voices[v].band += voices[v].f * high
                voices[v].env *= voices[v].decay
                let out = voices[v].band * 0.5
                l += out * voices[v].panL
                r += out * voices[v].panR
            }

            // Trueno.
            if thunderDelay > 0 {
                thunderDelay -= 1
                if thunderDelay == 0 {
                    thunderDelay = -1
                    thunderAttack = true
                }
            }
            if thunderAttack {
                thunderEnv += (thunderPeak - thunderEnv) * thunderAttackCoef
                if thunderEnv > thunderPeak * 0.95 { thunderAttack = false }
            } else {
                thunderEnv *= thunderDecayCoef
            }
            if thunderEnv > 0.0005 {
                thunderLow += 0.012 * (noise() - thunderLow)
                thunderLow2 += 0.012 * (thunderLow - thunderLow2)
                thunderMod += 0.0004 * (random01() - thunderMod)
                let rumble = thunderLow2 * thunderEnv * (0.4 + 1.6 * thunderMod) * 9
                l += rumble
                r += rumble
            }

            muffleL += muffleCoef * (l - muffleL)
            muffleR += muffleCoef * (r - muffleR)
            let gain = volume * duck * 1.8
            left[n] = tanhf(muffleL * gain)
            right[n] = tanhf(muffleR * gain)
        }
    }
}
