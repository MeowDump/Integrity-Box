#!/system/bin/sh

popup() {
    am start -a android.intent.action.MAIN -e mona "$@" -n meow.helper/.MainActivity &>/dev/null
    sleep 0.5
}

if mv /data/adb/tricky_store/keybox.xml.md /data/adb/tricky_store/keybox.xml 2>/dev/null; then
    popup "Keybox has been updated"
else
    nohup am start -a android.intent.action.VIEW -d https://youtu.be/xvFZjo5PgG0?si=QyzSGTIFrXfj-luA >/dev/null 2>&1 &
    popup "You're not using AOSP keybox"
fi

[ -f /data/adb/tricky_store/keybox.md ] && rm -f /data/adb/tricky_store/keybox.md

exit 0