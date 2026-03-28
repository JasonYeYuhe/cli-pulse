cask "cli-pulse-bar" do
  version "0.1.0"
  sha256 :no_check  # Update with actual SHA256 after release

  url "https://github.com/jasonyeyuhe/cli-pulse/releases/download/v#{version}/CLI.Pulse.Bar-v#{version}.dmg"
  name "CLI Pulse Bar"
  desc "macOS menu bar app for monitoring AI coding tool usage"
  homepage "https://github.com/jasonyeyuhe/cli-pulse"

  depends_on macos: ">= :ventura"

  app "CLI Pulse Bar.app"

  zap trash: [
    "~/Library/Preferences/com.clipulse.bar.plist",
    "~/Library/Caches/com.clipulse.bar",
  ]
end
