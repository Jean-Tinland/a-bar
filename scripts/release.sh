#!/bin/bash

# a-bar Release Script
# Usage: ./scripts/release.sh <version> <build_number>
# Example: ./scripts/release.sh 1.1.0 2

set -e

VERSION=$1
BUILD_NUMBER=$2

if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
    echo "Usage: $0 <version> <build_number>"
    echo "Example: $0 1.1.0 2"
    exit 1
fi

echo "Building a-bar v$VERSION (build $BUILD_NUMBER)"

# Configuration
APP_NAME="a-bar"
SCHEME="a-bar"
PROJECT="a-bar.xcodeproj"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "Archiving..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -archivePath "$ARCHIVE_PATH" \
    -configuration Release \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

echo "Extracting app from archive..."
mkdir -p "$EXPORT_PATH"
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_PATH/"

echo "Creating zip..."
cd "$EXPORT_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "../$APP_NAME.zip"
cd -

echo "Build complete!"
echo "   Archive: $ARCHIVE_PATH"
echo "   App: $EXPORT_PATH/$APP_NAME.app"
echo "   Zip: $ZIP_PATH"
echo ""
echo "Next steps:"
echo "   1. Create GitHub release with tag v$VERSION"
echo "   2. Upload $ZIP_PATH to the release"
echo "   3. Update appcast.xml with new version info"
echo "   4. Upload appcast.xml to the release"
