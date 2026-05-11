#!/bin/bash

# Setup GitHub Actions for automatic iOS build

echo "🚀 GitHub Actions Setup for BarcodeScanner"
echo "=========================================="
echo ""

# Check if git is initialized
if [ ! -d ".git" ]; then
    echo "❌ Git not initialized"
    echo "Run: git init"
    exit 1
fi

echo "✅ Git repository found"
echo ""

# Check if .github/workflows exists
if [ ! -d ".github/workflows" ]; then
    echo "❌ Workflows directory not found"
    exit 1
fi

echo "✅ Workflows directory found:"
ls -la .github/workflows/

echo ""
echo "📋 Next steps:"
echo ""
echo "1️⃣  Create GitHub repository on https://github.com/new"
echo ""
echo "2️⃣  Add remote:"
echo "   git remote add origin https://github.com/YOUR_USERNAME/barcode-scanner.git"
echo ""
echo "3️⃣  Create Expo token:"
echo "   npm install -g eas-cli"
echo "   eas login"
echo "   eas credentials"
echo ""
echo "4️⃣  Add GitHub Secret:"
echo "   Settings → Secrets and variables → Actions"
echo "   New secret: EXPO_TOKEN = <your-token>"
echo ""
echo "5️⃣  Push code:"
echo "   git add ."
echo "   git commit -m 'Initial commit'"
echo "   git branch -M main"
echo "   git push -u origin main"
echo ""
echo "6️⃣  Watch build:"
echo "   GitHub → Actions → Build iOS with EAS"
echo ""
echo "7️⃣  Download .ipa:"
echo "   https://expo.dev/builds"
echo ""
echo "✨ Happy building! 🎉"
