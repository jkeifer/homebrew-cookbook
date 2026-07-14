class Gribe < Formula
  desc "Transcribe audio locally on Apple Silicon"
  homepage "https://github.com/jkeifer/transgribe"
  url "https://github.com/jkeifer/transgribe/releases/download/v0.2.0/gribe"
  version "0.2.0"
  sha256 "0d976195f0d82a13d6aa2d78333a448ad173859db4d8aba974da4cc5463ce7b9"
  license "MIT"

  depends_on :macos
  depends_on arch: :arm64

  def install
    bin.install "gribe"
    generate_completions_from_executable(bin/"gribe", "--generate-completion-script")
  end

  test do
    assert_match "gribe", shell_output("#{bin}/gribe version")
  end
end
