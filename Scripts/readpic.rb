cask "readpic" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/sunux/readpic/releases/download/v#{version}/Readpic.dmg"
  name "Readpic"
  desc "Fast, native macOS image viewer"
  homepage "https://github.com/sunux/readpic"

  depends_on macos: ">= 15.6"

  app "Readpic.app"

  zap trash: [
    "~/Library/Caches/com.readpic",
    "~/Library/Preferences/com.readpic.plist",
  ]
end
