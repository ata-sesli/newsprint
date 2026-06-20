cask "newsprint" do
  version "1.0.2"
  sha256 "7026df85f6e695f3f7ba66c41b6a29855063ef43cc1c7ea3fe13158a5e705e68"

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
