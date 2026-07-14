class Gribe < Formula
  desc "Transcribe audio locally on Apple Silicon"
  homepage "https://github.com/jkeifer/transgribe"
  url "https://github.com/jkeifer/transgribe/releases/download/v0.1.0/gribe"
  version "0.1.0"
  sha256 "2f0d1b090487dfaf2bb22dea8b6fb71e36dbc9912a2f8a6fdfcb3d921cc5ae93"
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
