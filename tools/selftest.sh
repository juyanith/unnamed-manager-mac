#!/bin/zsh
# Runs the in-app self-test against a fresh config in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/net.unnamed.manager.savedState
config=/tmp/UnnamedManager-self.json
rm -f $config
APP_STORE=$config ${0:A:h}/../build/UnnamedManager.app/Contents/MacOS/UnnamedManager --selftest
