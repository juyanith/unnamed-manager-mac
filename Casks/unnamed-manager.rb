# The Homebrew cask. The release workflow updates version and sha256 on every tag.
#   brew tap juyanith/unnamed-manager https://github.com/juyanith/unnamed-manager-mac
#   brew install --cask unnamed-manager
cask "unnamed-manager" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/juyanith/unnamed-manager-mac/releases/download/v#{version}/UnnamedManager-#{version}.zip"
  name "Unnamed Manager"
  desc "Keyboard manager for apps and windows, in the menu bar"
  homepage "https://github.com/juyanith/unnamed-manager-mac"

  app "UnnamedManager.app"

  # Quit the running copy before an upgrade or uninstall replaces it.
  # brew upgrade reopens the apps it quit, so an update restarts the app.
  # (Install steps run in a sandbox where open can't start an app.)
  uninstall quit: "net.unnamed.manager"

  postflight_steps do
    # The app is signed with the project's own certificate, not notarized, so
    # Gatekeeper would block it. Clear the download mark Homebrew adds.
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/UnnamedManager.app"]
  end
end
