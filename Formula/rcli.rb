class Rcli < Formula
  desc "On-device voice AI for macOS — STT, LLM, TTS, 40 actions, and local RAG"
  homepage "https://github.com/RunanywhereAI/RCLI"
  url "https://github.com/RunanywhereAI/RCLI/releases/download/v0.1.3/rcli-0.1.3-Darwin-arm64.tar.gz"
  sha256 "03cace858e34b5ce0ddafce71b18edbd598e54066ca4048e4150ec0a3e9cea0a"
  license "MIT"
  version "0.1.3"

  depends_on :macos
  depends_on arch: :arm64

  def install
    bin.install "bin/rcli"
    lib.install Dir["lib/*.dylib"]
  end

  def post_install
    ohai "Run 'rcli setup' to download AI models (~1GB, one-time)"
  end

  def caveats
    <<~EOS
      RCLI requires Apple Silicon (M1+) and ~1GB of AI models.

      Get started:
        rcli setup              # download models (~1GB, one-time)
        rcli                    # interactive mode (push-to-talk + text)
        rcli actions            # see all 40 available actions
        rcli ask "open Safari"  # one-shot voice command

      Voice mode:
        rcli listen             # continuous hands-free voice control

      Model management:
        rcli models             # manage all AI models (LLM, STT, TTS)
        rcli upgrade-llm        # download larger/smarter LLMs
        rcli voices             # switch TTS voices
        rcli upgrade-stt        # download Parakeet TDT (1.9% WER, +640MB)
        rcli cleanup            # remove unused models to free disk space

      RAG (query your docs locally):
        rcli rag ingest ~/Documents
        rcli rag query "summarize the meeting notes"

      Benchmarks:
        rcli bench              # run all benchmarks (STT, LLM, TTS, E2E)
    EOS
  end

  test do
    assert_match "RCLI", shell_output("#{bin}/rcli --help")
  end
end
