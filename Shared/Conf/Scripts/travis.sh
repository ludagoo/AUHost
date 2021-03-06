#!/bin/bash

# Support for Gems installed with --user-install. [ Frequently Asked Questions - RubyGems Guides ]( http://guides.rubygems.org/faqs/ )
if which ruby >/dev/null && which gem >/dev/null; then
    export PATH="$PATH:$(ruby -rubygems -e 'puts Gem.user_dir')/bin"
fi

fastlane clean
fastlane ci
