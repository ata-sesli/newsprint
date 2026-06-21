cask "newsprint" do
  version "1.0.3"
  sha256 "c05c6eb8ee4a95d9cd1e7cf55076c105e50735858902de264ed59c9e071b9b94"

  url "https://github.com/ata-sesli/newsprint/releases/download/v#{version}/Newsprint-#{version}.zip"
  name "Newsprint"
  desc "Local-first menu bar news reader"
  homepage "https://github.com/ata-sesli/newsprint"

  depends_on macos: ">= :sonoma"

  app "Newsprint.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Newsprint.app"],
                   sudo: false
  end

  uninstall quit: "local.newsprint.app"

  zap trash: [
    "~/Library/Application Support/newsprint",
    "~/Library/Caches/local.newsprint.app",
    "~/Library/HTTPStorages/local.newsprint.app",
    "~/Library/Preferences/local.newsprint.app.plist",
    "~/Library/Saved Application State/local.newsprint.app.savedState",
    "~/Library/WebKit/local.newsprint.app",
  ]

  caveats <<~EOS
    Newsprint is currently unsigned. This cask removes the quarantine
    attribute after installation so macOS can launch it normally.
  EOS
end
