#!/bin/zsh
# Snapshots of every Bindings page and Settings in light and dark, against a test config in /tmp.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=bindings,settings tools/snap.sh
#        tools/snap.sh -AppleShowScrollBars Always     see the scroll bars as people with a mouse see them
set -u
app=${0:A:h}/../build/UnnamedManager.app/Contents/MacOS/UnnamedManager
config=/tmp/UnnamedManager-test.json
shots=/tmp/UnnamedManager-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/net.unnamed.manager.savedState
rm -f $config
rm -rf $shots
APP_STORE=$config APP_SNAPSHOT=$shots $app "$@"
