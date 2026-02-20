#!/usr/bin/env bash
# This script is executed automatically once when a new sandbox is created.
# All commands here are executed on behalf of the local user (sandbox).

echo "🚀 Running user sandbox setup..."

echo "Installing NVM..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash

echo "📦 Installing Claude..."
curl -fsSL https://claude.ai/install.sh | bash

# You can add installation of other utilities here (e.g., Node.js, npm packages, pip, etc.)
# npm install -g typescript
# pip install --user requests

echo "✅ User setup completed!"