class Rcli < Formula
  desc "On-device voice AI for macOS — STT, LLM, TTS, 43 actions, and local RAG"
  homepage "https://github.com/RunanywhereAI/RCLI"
  url "https://github.com/RunanywhereAI/RCLI/releases/download/v0.2.3/rcli-0.2.3-Darwin-arm64.tar.gz"
  sha256 "4c24a637c4afceebf0eff978001f8f31c684f4020425db86dfe7268381c661c3"
  license "MIT"
  version "0.2.3"

  depends_on :macos
  depends_on arch: :arm64

  def install
    bin.install "bin/rcli"
    lib.install Dir["lib/*.dylib"]
  end

  def post_install
    ohai "Run 'rcli setup' to download AI models and choose your engine"
  end

  def caveats
    <<~EOS
      RCLI requires Apple Silicon (M1+).

      Get started:
        rcli setup              # choose engine + download models (one-time)
        rcli                    # interactive mode (push-to-talk + text)
        rcli ask "open Safari"  # one-shot voice command

      Engine options (selected during setup):
        Open Source   llama.cpp + sherpa-onnx (~1 GB)
        MetalRT       GPU-accelerated engine (~0.9 GB) — 550 tok/s
        Both          recommended (~1.9 GB)

      MetalRT (GPU acceleration):
        rcli metalrt install    # install/update MetalRT engine
        rcli metalrt status     # check MetalRT installation

      Model management:
        rcli models             # manage all AI models (LLM, STT, TTS)
        rcli cleanup            # remove unused models to free disk space

      Benchmarks:
        rcli bench              # run all benchmarks (STT, LLM, TTS, E2E)
    EOS
  end

  test do
    assert_match "RCLI", shell_output("#{bin}/rcli --help")
  end
end
