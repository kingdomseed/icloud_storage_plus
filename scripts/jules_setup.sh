#!/bin/bash
set -e

# Avoid interactive prompts
export DEBIAN_FRONTEND=noninteractive

echo "🚀 Starting Jules Environment Setup..."

# 1. Install Linux dependencies
# These are the requirements for Linux (from Flutter docs)
echo "📦 Installing Linux dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq curl git unzip xz-utils zip libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev

# 2. INSTALL STANDARD FLUTTER SDK
# We install the 'stable' channel to a standard location.
if [ ! -d "$HOME/flutter" ]; then
  echo "🦋 Cloning Flutter SDK (stable)..."
  git clone https://github.com/flutter/flutter.git -b stable "$HOME/flutter"
else
  echo "✅ Flutter SDK already exists."
fi

# Pre-download development binaries to speed up first run
echo "📥 Precaching Flutter artifacts..."
"$HOME/flutter/bin/flutter" precache

# 3. CONFIGURE PATH
# We add standard Flutter bin to the path.
# We put standard Flutter FIRST so 'flutter' commands always use the official SDK.
HOME_FLUTTER_BIN="$HOME/flutter/bin"

export PATH="$HOME_FLUTTER_BIN:$PATH"

# Persist to .bashrc
if ! grep -q "$HOME_FLUTTER_BIN" "$HOME/.bashrc"; then
  echo "🔧 Updating .bashrc..."
  echo "export PATH=\"$HOME_FLUTTER_BIN:\$PATH\"" >> "$HOME/.bashrc"
fi

# 4. VALIDATION
echo "🏥 Running Doctors..."
# This will now work for 'analyze', 'test', etc.
flutter doctor -v

# 5. CLEANUP (Required for Jules Snapshot)
# Revert the 'chmod +x' on this script to ensure git status is clean.
echo "🧹 Cleaning up git state..."
git checkout .

echo "🎉 Setup complete! Flutter is ready."
