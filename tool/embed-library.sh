#!/bin/bash
# Writes `lib/Forge.yaml`, Forge's library, and `lib/Native.interface.warpt`,
# the declarations of the native verbs it is written over, into a Swift
# source, so the grammar a workflow uses arrives with the binary rather than
# off a disk the daemon may not have. `lib/Compaction.prompt.md`, the prompt
# that asks a conversation for its summary, goes into a source of its own.
#
# The files are the source; these are copies of them. `ForgeVocabularyTests`
# and `SummaryCompactionTests` hold each file to its copy, so a file edited
# without running this is a red test.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
library="$root/lib/Forge.yaml"
interface="$root/lib/Native.interface.warpt"
written="$root/package/Sources/Forge/Service/Host/Vocabulary/Library.swift"

literal() {
    echo "    static let $1 = \"\"\""
    /usr/bin/sed -e 's/\\/\\\\/g' -e 's/"""/\\"\\"\\"/g' -e 's/^/        /' "$2"
    echo "        \"\"\""
}

{
    echo "//"
    echo "//  Library.swift"
    echo "//  Forge"
    echo "//"
    echo "//  Written by tool/embed-library.sh. Edit the files in lib and run it again."
    echo "//"
    echo ""
    echo "import Foundation"
    echo ""
    echo "// The texts of \`lib/Forge.yaml\` and \`lib/Native.interface.warpt\`, as they"
    echo "// stand in the repository."
    echo "enum Library {"
    literal text "$library"
    echo ""
    literal nativeInterface "$interface"
    echo "}"
} > "$written"

echo "$written"

prompt="$root/lib/Compaction.prompt.md"
written="$root/package/Sources/Forge/Service/Agent/Agent/CompactionPrompt.swift"

{
    echo "//"
    echo "//  CompactionPrompt.swift"
    echo "//  Forge"
    echo "//"
    echo "//  Written by tool/embed-library.sh. Edit the file in lib and run it again."
    echo "//"
    echo ""
    echo "import Foundation"
    echo ""
    echo "// The text of \`lib/Compaction.prompt.md\`, as it stands in the repository."
    echo "enum CompactionPrompt {"
    literal text "$prompt"
    echo "}"
} > "$written"

echo "$written"
