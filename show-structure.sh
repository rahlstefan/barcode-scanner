#!/bin/bash

# Script to display project structure
# Usage: bash show-structure.sh

echo "📁 BarcodeScanner Project Structure"
echo "=================================="
echo ""

tree -L 3 -I 'node_modules|.expo|dist|build|.git' \
  --charset ascii \
  --dirsfirst \
  . 2>/dev/null || find . -type f -not -path '*/node_modules/*' -not -path '*/.expo/*' | head -50

echo ""
echo "📊 File Statistics"
echo "===================="
echo ""
echo "TypeScript files:"
find src -name "*.ts" -o -name "*.tsx" 2>/dev/null | wc -l

echo "Swift files:"
find modules -name "*.swift" 2>/dev/null | wc -l

echo "Configuration files:"
ls -1 | grep -E "\.json$|\.js$|\.md$|\.yml$|\.yaml$" | wc -l

echo ""
echo "📄 Documentation"
echo "================"
ls -1 *.md 2>/dev/null | sed 's/^/  - /'

echo ""
echo "✅ Project ready for:"
echo "  • npm start (Expo Dev)"
echo "  • npm run prebuild (Native build)"
echo "  • npm run ios (Direct iOS run)"
