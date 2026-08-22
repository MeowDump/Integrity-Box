#!/system/bin/sh

WEBROOT="/data/adb/modules/playintegrityfix/webroot"
MODERN_SRC="$WEBROOT/common_scripts/UI"
FLAG_DIR="/data/adb/Box-Brain"

FILES="index.html script.js style.css"
sleep 2

if [ -f "$FLAG_DIR/modern" ]; then
    for f in $FILES; do
        if [ -f "$WEBROOT/$f" ] && [ ! -f "$WEBROOT/$f.bak" ]; then
            mv "$WEBROOT/$f" "$WEBROOT/$f.bak"
        fi
        if [ -f "$MODERN_SRC/$f" ]; then
            cp -f "$MODERN_SRC/$f" "$WEBROOT/$f"
        fi
    done
elif [ -f "$FLAG_DIR/classic" ]; then
    for f in $FILES; do
        if [ -f "$WEBROOT/$f.bak" ]; then
            if [ -f "$WEBROOT/$f" ]; then
                mv -f "$WEBROOT/$f" "$MODERN_SRC/$f"
            fi
            mv "$WEBROOT/$f.bak" "$WEBROOT/$f"
        fi
    done
fi

am force-stop com.android.webview 2>/dev/null
am force-stop com.google.android.webview 2>/dev/null
