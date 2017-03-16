#!/bin/bash
if [[ $# -ne 3 && $# -ne 2 ]]; then
  cat <<EOF
Usage:

  $0 RCP_FILE OUTPUT_FILE [JDK_FILE]

1. Extracts RCP_FILE into a temporary directory
2. Creates symlinks Contents/bin/*.dylib -> *.jnilib
3. If JDK_FILE is given, extracts JDK_FILE under Contents/
4. Builds help indices using hiutil if help is present under Contents/Resources/
5. Sets executable permissions on Contents/MacOS/* and appropriate Contents/bin/ files
6. Zips the result into OUTPUT_FILE

IMPORTANT: All arguments must use absolute paths because the script changes the current directory several times!
EOF
  exit 1
fi

set -o errexit # Exit immediately on any error

# Arguments
RCP_FILE="$1"
OUTPUT_FILE="$2"
JDK_FILE="$3"

EXPLODED=$(mktemp -d) || exit 1

echo "Unzipping $RCP_FILE to $EXPLODED..."
unzip -q -o "$RCP_FILE" -d "$EXPLODED"
BUILD_NAME=$(ls "$EXPLODED")
CONTENTS="$EXPLODED/$BUILD_NAME/Contents"

echo 'Creating symlinks from *.jnilib to *.dylib:'
for f in "$CONTENTS/bin"/*.jnilib; do
  b="$(basename "$f" .jnilib)"
  echo "  $f -> $b.dylib"
  ln -sf "$b.jnilib" "$(dirname "$f")/$b.dylib"
done
echo 'Done creating symlinks'

if [[ -n "$JDK_FILE" ]]; then
  if [[ ! -f "$JDK_FILE" ]]; then
    echo "$JDK_FILE is not a file"
    exit 1
  fi
  echo "Modifying Info.plist"
  sed -i .bak -e 's/1.6\*/1.6\+/' "$CONTENTS/Info.plist"
  sed -i .bak -e 's/NoJavaDistribution/custom-jdk-bundled/' "$CONTENTS/Info.plist"

  # TODO This command appears to be useless, it only inserts a blank line into the file.
  sed -i .bak -e '/public.app-category.developer-tools/G' "$CONTENTS/Info.plist"

  sed -i .bak -e '/public.app-category.developer-tools/a\'$'\n''<key>NSSupportsAutomaticGraphicsSwitching</key><true/>' "$CONTENTS/Info.plist"
  rm -f "$CONTENTS/Info.plist.bak"
  echo "Info.plist has been modified"

  echo "Extracting JDK: $JDK_FILE to $CONTENTS"
  pushd "$CONTENTS"
  COPY_EXTENDED_ATTRIBUTES_DISABLE=true COPYFILE_DISABLE=true tar xvf "$JDK_FILE" --exclude='._jdk' || exit 1
  echo "JDK has been extracted"
  popd
fi

HELP_FILE=$(ls "$CONTENTS/Resources/" | grep -i help) || HELP_FILE=''
HELP_DIR="$CONTENTS/Resources/$HELP_FILE/Contents/Resources/English.lproj/"

if [[ -d "$HELP_DIR" ]]; then
    echo "Building help indices for $HELP_DIR"
    hiutil -Cagvf "$HELP_DIR/search.helpindex" "$HELP_DIR"
fi

# Make sure JetBrainsMacApplication.p12 is imported into local KeyChain
#security unlock-keychain -p <password> /Users/builduser/Library/Keychains/login.keychain
#codesign -v --deep -s "Developer ID Application: JetBrains" "$EXPLODED/$BUILD_NAME"
#echo "signing is done"
#echo "check sign"
#codesign -v "$EXPLODED/$BUILD_NAME" -vvvvv
#echo "check sign done"

chmod a+x "$CONTENTS"/MacOS/*
chmod a+x "$CONTENTS"/bin/*.py
chmod a+x "$CONTENTS"/bin/fs*
chmod a+x "$CONTENTS"/bin/restarter

echo "Zipping $BUILD_NAME to $OUTPUT_FILE"
pushd "$EXPLODED"
ditto -c -k --sequesterRsrc --keepParent "$BUILD_NAME" "$OUTPUT_FILE"
popd
rm -rf "$EXPLODED"
