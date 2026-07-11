cask "modulr" do
  version "1.0"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/johnshields/modulr/releases/download/v#{version}/Modulr-#{version}.dmg"
  name "Modulr"
  desc "DJ track analyser and library manager"
  homepage "https://github.com/johnshields/modulr"

  license :mit

  depends_on macos: :sonoma
  depends_on formula: "ffmpeg"
  depends_on formula: "python@3.12"

  app "Modulr.app"

  zap trash: [
    "~/Library/Preferences/com.fromlost.modulr.plist",
    "~/Library/Saved Application State/com.fromlost.modulr.savedState",
  ]
end
