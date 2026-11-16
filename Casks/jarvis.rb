cask "jarvis" do
  version "0.6.0"
  sha256 "00b47d90cc9c61b62fd3e235ab0f1963a1498d42e2e78cd8de308bd418e8d3a5"

  url "https://github.com/YOUR-GITHUB/jarvis/releases/download/v#{version}/Jarvis.zip"
  name "Jarvis"
  desc "Notch companion that keeps an eye on your AI coding agents"
  homepage "https://github.com/YOUR-GITHUB/jarvis"

  # Only the Mac's tags (vX.Y.Z): windows-v…, linux-v… and android-v… are other apps.
  livecheck do
    url :url
    regex(/^v?(\d+(?:\.\d+)+)$/i)
    strategy :github_releases
  end

  # Jarvis updates itself from the notch: brew leaves the installed app alone.
  auto_updates true
  depends_on macos: :sequoia

  app "Jarvis.app"

  uninstall quit: "com.jarvis.NotchBuddy"

  zap trash: [
    "~/Library/Application Support/Jarvis",
    "~/Library/Application Support/NotchBuddy",
    "~/Library/Preferences/com.jarvis.NotchBuddy.plist",
  ]
end
