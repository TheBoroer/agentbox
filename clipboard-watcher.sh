#!/usr/bin/env bash
# Host-side clipboard watcher for AgentBox.
# Monitors the system clipboard for image data and writes PNG to a shared
# directory that the container-side xclip shim reads from.
#
# Also adds the file path as text to the clipboard when an image-only item is
# detected. This is necessary because Claude Code's empty-paste → image check
# is macOS-only, but its file-path detection works on all platforms. Without
# the text, the terminal sends an empty paste and Claude Code never checks xclip.
#
# Supports macOS (NSPasteboard) and Windows via WSL2 (PowerShell).

set -euo pipefail

clipboard_dir="$1"
clipboard_file="${clipboard_dir}/clipboard.png"

mkdir -p "$clipboard_dir"

cleanup() {
    rm -f "$clipboard_file"
    rm -f "${clipboard_dir}/watcher.ps1"
    exit 0
}

trap cleanup SIGTERM SIGINT EXIT

# --- Platform detection and function definitions ---

if [[ "$OSTYPE" == darwin* ]]; then
    POLL_INTERVAL=0.5

    check_clipboard() {
        osascript <<'APPLESCRIPT' 2>/dev/null
use framework "AppKit"
set pb to current application's NSPasteboard's generalPasteboard()
set cc to pb's changeCount() as integer
set hasImage to false
set pngType to current application's NSPasteboardTypePNG
set tiffType to current application's NSPasteboardTypeTIFF
if ((pb's types()'s containsObject:pngType) as boolean) or ((pb's types()'s containsObject:tiffType) as boolean) then
    set hasImage to true
end if
return (cc as text) & " " & (hasImage as text)
APPLESCRIPT
    }

    save_clipboard() {
        osascript - "$1" <<'APPLESCRIPT' 2>/dev/null
use framework "AppKit"
use framework "Foundation"
on run argv
    set pb to current application's NSPasteboard's generalPasteboard()
    set imgData to pb's dataForType:(current application's NSPasteboardTypePNG)
    if imgData is missing value then
        set tiffData to pb's dataForType:(current application's NSPasteboardTypeTIFF)
        if tiffData is not missing value then
            set theRep to current application's NSBitmapImageRep's imageRepWithData:tiffData
            set imgData to theRep's representationUsingType:(current application's NSBitmapImageFileTypePNG) |properties|:(missing value)
        end if
    end if
    if imgData is not missing value then
        imgData's writeToFile:(item 1 of argv) atomically:true
    end if
end run
APPLESCRIPT
    }

    augment_clipboard() {
        osascript - "$1" <<'APPLESCRIPT' 2>/dev/null
use framework "AppKit"
use framework "Foundation"
on run argv
    set filePath to item 1 of argv
    set pb to current application's NSPasteboard's generalPasteboard()

    if (pb's stringForType:(current application's NSPasteboardTypeString)) is not missing value then
        return ""
    end if

    set pngData to pb's dataForType:(current application's NSPasteboardTypePNG)
    set tiffData to pb's dataForType:(current application's NSPasteboardTypeTIFF)
    if pngData is missing value and tiffData is missing value then return ""

    set pbItem to current application's NSPasteboardItem's alloc()'s init()
    pbItem's setString:filePath forType:(current application's NSPasteboardTypeString)
    if pngData is not missing value then
        pbItem's setData:pngData forType:(current application's NSPasteboardTypePNG)
    end if
    if tiffData is not missing value then
        pbItem's setData:tiffData forType:(current application's NSPasteboardTypeTIFF)
    end if
    pb's clearContents()
    pb's writeObjects:{pbItem}

    return (pb's changeCount() as integer) as text
end run
APPLESCRIPT
    }

elif [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
    POLL_INTERVAL=1

    if ! command -v powershell.exe &>/dev/null; then
        echo "powershell.exe not found in PATH" >&2
        exit 1
    fi

    clipboard_file_win=$(wslpath -w "$clipboard_file")
    ps_script="${clipboard_dir}/watcher.ps1"
    ps_script_win=$(wslpath -w "$ps_script")

    # Single PS script handles check + save + augment per iteration to
    # minimize the ~300ms PowerShell startup overhead.
    cat > "$ps_script" << 'PS1'
param(
    [string]$LastSeq,
    [string]$WinPath,
    [string]$LinuxPath
)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Clipboard {
    [DllImport("user32.dll")]
    public static extern uint GetClipboardSequenceNumber();
}
"@

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$seq = [Win32Clipboard]::GetClipboardSequenceNumber()

if ("$seq" -eq $LastSeq) {
    Write-Output "$seq false"
    exit
}

$img = [System.Windows.Forms.Clipboard]::GetImage()
if ($img -eq $null) {
    Write-Output "$seq false"
    exit
}

$img.Save($WinPath, [System.Drawing.Imaging.ImageFormat]::Png)

if (-not [System.Windows.Forms.Clipboard]::ContainsText()) {
    $data = New-Object System.Windows.Forms.DataObject
    $data.SetImage($img)
    $data.SetText($LinuxPath)
    [System.Windows.Forms.Clipboard]::SetDataObject($data, $true)
    $seq = [Win32Clipboard]::GetClipboardSequenceNumber()
}

$img.Dispose()
Write-Output "$seq true"
PS1

    check_clipboard() {
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps_script_win" "$last_change_count" "$clipboard_file_win" "$clipboard_file" 2>/dev/null | tr -d '\r'
    }

    # save + augment handled inside the PowerShell script
    save_clipboard() { :; }
    augment_clipboard() { :; }

else
    echo "Unsupported platform: clipboard bridge requires macOS or WSL2" >&2
    exit 1
fi

# --- Main loop (platform-agnostic) ---

last_change_count=""

while true; do
    info=$(check_clipboard) || { sleep "$POLL_INTERVAL"; continue; }

    cc="${info%% *}"
    has_image="${info##* }"

    if [[ "$cc" != "$last_change_count" ]]; then
        last_change_count="$cc"
        if [[ "$has_image" == "true" ]]; then
            save_clipboard "$clipboard_file" >/dev/null || true
            new_cc=$(augment_clipboard "$clipboard_file") || true
            if [[ -n "$new_cc" ]]; then
                last_change_count="$new_cc"
            fi
        else
            rm -f "$clipboard_file"
        fi
    fi

    sleep "$POLL_INTERVAL"
done
