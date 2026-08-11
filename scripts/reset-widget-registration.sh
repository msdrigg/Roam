#!/bin/zsh
# Reset macOS widget state after dev builds break the desktop widgets.
#
# TestFlight Roam (/Applications/Roam.app), Xcode DerivedData builds, and any
# other built copies of Roam.app all register RoamWidgets.appex with
# LaunchServices. Duplicate registrations make chronod fail cache validation
# ("Bundle version did not match; LaunchServices DB may need to be rebuilt")
# and widgets render stale or empty. This unregisters every copy except
# /Applications/Roam.app, re-registers that one, and restarts the widget
# infrastructure (chronod / NotificationCenter respawn on their own).

set -euo pipefail

LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
CANONICAL=/Applications/Roam.app

if [[ ! -d "$CANONICAL" ]]; then
    echo "error: $CANONICAL not found" >&2
    exit 1
fi

echo "Searching for registered copies of com.msdrigg.roam..."
mdfind "kMDItemCFBundleIdentifier == 'com.msdrigg.roam'" | while read -r path; do
    if [[ "$path" != "$CANONICAL" ]]; then
        echo "  unregistering: $path"
        "$LSREG" -u "$path" || true
    fi
done

echo "Re-registering $CANONICAL"
"$LSREG" -f "$CANONICAL"

echo "Restarting chronod and NotificationCenter (widgets will flicker)..."
killall chronod NotificationCenter 2>/dev/null || true

echo "Done. Registered RoamWidgets paths:"
"$LSREG" -dump | grep "RoamWidgets.appex" | grep "path:" | sed 's/^ *path: */  /'
