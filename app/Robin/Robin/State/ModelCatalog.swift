import Foundation

enum ModelCatalog {
    static let all: [ModelCatalogEntry] = [
        // MARK: - LLM Models
        ModelCatalogEntry(
            id: "lfm2-1.2b", name: "Liquid LFM2 1.2B Tool",
            sizeBytes: 731_000_000, type: .llm,
            description: "Default, excellent tool calling",
            source: .remote(URL(string: "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf")!),
            localPath: "lfm2-1.2b-tool-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: true),
        ModelCatalogEntry(
            id: "lfm2-350m", name: "Liquid LFM2 350M",
            sizeBytes: 219_000_000, type: .llm,
            description: "Ultra-fast, basic tool calling",
            source: .remote(URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf")!),
            localPath: "LFM2-350M-Q4_K_M.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "lfm2.5-1.2b", name: "Liquid LFM2.5 1.2B Instruct",
            sizeBytes: 731_000_000, type: .llm,
            description: "Newer LFM, good tool calling",
            source: .remote(URL(string: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf")!),
            localPath: "LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "lfm2-2.6b", name: "Liquid LFM2 2.6B",
            sizeBytes: 1_480_000_000, type: .llm,
            description: "Larger LFM, good tool calling",
            source: .remote(URL(string: "https://huggingface.co/LiquidAI/LFM2-2.6B-GGUF/resolve/main/LFM2-2.6B-Q4_K_M.gguf")!),
            localPath: "LFM2-2.6B-Q4_K_M.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "qwen3-0.6b", name: "Qwen3 0.6B",
            sizeBytes: 456_000_000, type: .llm,
            description: "Fast, basic tool calling",
            source: .remote(URL(string: "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/qwen3-0.6b-q4_k_m.gguf")!),
            localPath: "qwen3-0.6b-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "qwen3.5-0.8b", name: "Qwen3.5 0.8B",
            sizeBytes: 600_000_000, type: .llm,
            description: "Compact Qwen, basic tool calling",
            source: .remote(URL(string: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf")!),
            localPath: "qwen3.5-0.8b-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "qwen3.5-2b", name: "Qwen3.5 2B",
            sizeBytes: 1_200_000_000, type: .llm,
            description: "Balanced Qwen, good tool calling",
            source: .remote(URL(string: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf")!),
            localPath: "qwen3.5-2b-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "qwen3-4b", name: "Qwen3 4B",
            sizeBytes: 2_500_000_000, type: .llm,
            description: "Large Qwen, good tool calling",
            source: .remote(URL(string: "https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf")!),
            localPath: "qwen3-4b-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "qwen3.5-4b", name: "Qwen3.5 4B",
            sizeBytes: 2_700_000_000, type: .llm,
            description: "Smartest, excellent tool calling",
            source: .remote(URL(string: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf")!),
            localPath: "qwen3.5-4b-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: true),
        ModelCatalogEntry(
            id: "llama3.2-3b", name: "Llama 3.2 3B Instruct",
            sizeBytes: 1_800_000_000, type: .llm,
            description: "Meta Llama, good tool calling",
            source: .remote(URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")!),
            localPath: "llama-3.2-3b-instruct-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: false),

        // MARK: - STT Models
        ModelCatalogEntry(
            id: "whisper-base", name: "Whisper base.en",
            sizeBytes: 140_000_000, type: .stt,
            description: "Offline transcription, ~5% WER",
            source: .bundled,
            localPath: "whisper-base.en",
            archiveDirName: "sherpa-onnx-whisper-base.en", isRecommended: true),
        ModelCatalogEntry(
            id: "parakeet-tdt", name: "Parakeet TDT 0.6B v3",
            sizeBytes: 640_000_000, type: .stt,
            description: "Best accuracy, ~1.9% WER",
            source: .remote(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2")!),
            localPath: "parakeet-tdt",
            archiveDirName: "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
            isRecommended: true),

        // MARK: - TTS Models
        ModelCatalogEntry(
            id: "piper-lessac", name: "Piper Lessac (English)",
            sizeBytes: 60_000_000, type: .tts,
            description: "Default English voice",
            source: .bundled,
            localPath: "piper-voice",
            archiveDirName: "vits-piper-en_US-lessac-medium", isRecommended: true),
        ModelCatalogEntry(
            id: "piper-amy", name: "Piper Amy (English)",
            sizeBytes: 60_000_000, type: .tts,
            description: "Alternative English voice",
            source: .remote(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-amy-medium.tar.bz2")!),
            localPath: "piper-amy",
            archiveDirName: "vits-piper-en_US-amy-medium",
            isRecommended: false),
        ModelCatalogEntry(
            id: "kitten-nano", name: "KittenTTS Nano (English)",
            sizeBytes: 90_000_000, type: .tts,
            description: "8 voices, great quality",
            source: .remote(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kitten-nano-en-v0_1-fp16.tar.bz2")!),
            localPath: "kitten-nano-en-v0_1-fp16",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "matcha-ljspeech", name: "Matcha LJSpeech (English)",
            sizeBytes: 100_000_000, type: .tts,
            description: "Great quality",
            source: .remote(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/matcha-icefall-en_US-ljspeech.tar.bz2")!),
            localPath: "matcha-icefall-en_US-ljspeech",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "kokoro-en", name: "Kokoro English v0.19",
            sizeBytes: 310_000_000, type: .tts,
            description: "11 voices, excellent quality",
            source: .remote(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2")!),
            localPath: "kokoro-en-v0_19",
            archiveDirName: nil, isRecommended: true),
        ModelCatalogEntry(
            id: "kokoro-multi", name: "Kokoro Multi-lang v1.1",
            sizeBytes: 500_000_000, type: .tts,
            description: "103 voices, Chinese + English",
            source: .remote(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_1.tar.bz2")!),
            localPath: "kokoro-multi-lang-v1_1",
            archiveDirName: nil, isRecommended: false),
    ]

    static func models(ofType type: ModelType) -> [ModelCatalogEntry] {
        all.filter { $0.type == type }
            .sorted { ($0.isRecommended ? 0 : 1) < ($1.isRecommended ? 0 : 1) }
    }
}
