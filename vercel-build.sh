#!/bin/bash
set -e

echo "=== MURMUR CI/CD: Building Flutter Web for Vercel ==="

# 1. Install Flutter SDK if not present in build environment
if [ ! -d "flutter-sdk" ]; then
  echo "==> Downloading Flutter SDK (stable channel)..."
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable flutter-sdk
else
  echo "==> Using cached Flutter SDK."
fi

export PATH="$PATH:$(pwd)/flutter-sdk/bin"

flutter --version

# 2. Get dependencies
echo "==> Resolving Flutter package dependencies..."
flutter pub get

# 3. Build Web release with optional environment variable overrides
echo "==> Compiling Flutter Web release..."
DART_DEFINES=""

if [ -n "$FIREBASE_API_KEY" ]; then
  DART_DEFINES="$DART_DEFINES --dart-define=FIREBASE_API_KEY=$FIREBASE_API_KEY"
fi
if [ -n "$FIREBASE_APP_ID" ]; then
  DART_DEFINES="$DART_DEFINES --dart-define=FIREBASE_APP_ID=$FIREBASE_APP_ID"
fi
if [ -n "$FIREBASE_PROJECT_ID" ]; then
  DART_DEFINES="$DART_DEFINES --dart-define=FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID"
fi
if [ -n "$FIREBASE_MESSAGING_SENDER_ID" ]; then
  DART_DEFINES="$DART_DEFINES --dart-define=FIREBASE_MESSAGING_SENDER_ID=$FIREBASE_MESSAGING_SENDER_ID"
fi
if [ -n "$FIREBASE_AUTH_DOMAIN" ]; then
  DART_DEFINES="$DART_DEFINES --dart-define=FIREBASE_AUTH_DOMAIN=$FIREBASE_AUTH_DOMAIN"
fi
if [ -n "$FIREBASE_STORAGE_BUCKET" ]; then
  DART_DEFINES="$DART_DEFINES --dart-define=FIREBASE_STORAGE_BUCKET=$FIREBASE_STORAGE_BUCKET"
fi

flutter build web --release $DART_DEFINES

echo "=== Build finished successfully! Output generated in build/web ==="
