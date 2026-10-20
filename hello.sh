#!/bin/sh
SIZE=1
NORMAL_SPEED=0.1
FINAL_SPEED=0.08

show_animation() {
    frame=1
    total_frames=5

    get_terminal_size() {
        terminal_width=$(tput cols 2>/dev/null)
        terminal_height=$(tput lines 2>/dev/null)

        case "$terminal_width" in
            ''|*[!0-9]*) terminal_width=80 ;;
        esac

        case "$terminal_height" in
            ''|*[!0-9]*) terminal_height=24 ;;
        esac

        available_width=$((terminal_width - 2))
        [ "$available_width" -gt 0 ] || available_width=1
    }

    # Resize ASCII art horizontally and vertically..
    resize_art() {
        printf '%s\n' "$1" |
        awk -v scale="$SIZE" '
        BEGIN {
            if (scale <= 0 || scale > 1) scale = 0.5
        }
        {
            lines[NR] = $0
            if (length($0) > max_width)
                max_width = length($0)
        }
        END {
            if (max_width == 0) exit

            out_height = int(NR * scale + 0.5)
            out_width = int(max_width * scale + 0.5)

            if (out_height < 1) out_height = 1
            if (out_width < 1) out_width = 1

            for (y = 0; y < out_height; y++) {
                src_y = int(y / scale) + 1
                if (src_y > NR) src_y = NR

                line = lines[src_y]
                result = ""

                for (x = 0; x < out_width; x++) {
                    src_x = int(x / scale) + 1
                    ch = substr(line, src_x, 1)

                    if (ch == "") ch = " "
                    result = result ch
                }

                sub(/[[:space:]]+$/, "", result)
                print result
            }
        }'
    }

    while [ "$frame" -le "$total_frames" ]; do
        case "$frame" in
            1)
                art=$(cat <<'EOF'
 _           _ _
| |         | | |
| |__  _____| | | ___
|  _ \| ___ | | |/ _ \
| | | | ____| | | |_| |
|_| |_|_____)\_)_)___/
EOF
)
                speed=$NORMAL_SPEED
                ;;
            2)
                art=$(cat <<'EOF'
                   _           _
                  | |         | |
 ____  _____  ____| |__  _____| |__  _____
|    \| ___ |/ ___)  _ \(____ |  _ \(____ |
| | | | ____| |   | | | / ___ | |_) ) ___ |
|_|_|_|_____)_|   |_| |_\_____|____/\_____|
EOF
)
                speed=$NORMAL_SPEED
                ;;
            3)
                art=$(cat <<'EOF'
                         _
                        (_)
  ____  ____ _____  ____ _ _____  ___
 / _  |/ ___|____ |/ ___) (____ |/___)
( (_| | |   / ___ ( (___| / ___ |___ |
 \___ |_|   \_____|\____)_\_____(___/
(_____|
EOF
)
                speed=$NORMAL_SPEED
                ;;
            4)
                art=$(cat <<'EOF'
 ____  _____ ____  _____  ___ _| |_ _____
|  _ \(____ |    \(____ |/___|_   _) ___ |
| | | / ___ | | | / ___ |___ | | |_| ____|
|_| |_\_____|_|_|_\_____(___/   \__)_____)
EOF
)
                speed=$NORMAL_SPEED
                ;;
            5)
                art=$(cat <<'EOF'
 _____  ___  ___ _____| | _____ ____  _   _
(____ |/___)/___|____ | |(____ |    \| | | |
/ ___ |___ |___ / ___ | |/ ___ | | | | |_| |
\_____(___/(___/\_____|\_)_____|_|_|_|____/

       _        _ _
      | |      (_) |
 _____| | _____ _| |  _ _   _ ____
(____ | |(____ | | |_/ ) | | |    \
/ ___ | |/ ___ | |  _ (| |_| | | | |
\_____|\_)_____|_|_| \_)____/|_|_|_|
EOF
)
                speed=$FINAL_SPEED
                ;;
        esac

        # Apply size adjustment to the current frame
        art=$(resize_art "$art")

        get_terminal_size

        line_count=$(printf '%s\n' "$art" | awk 'END { print NR }')

        step=1
        while [ "$step" -le "$line_count" ]; do
            clear
            get_terminal_size

            printf 'Preparing Environment......\n\n'

            if [ $((frame % 2)) -eq 1 ]; then
                direction=top
            else
                direction=bottom
            fi

            printf '%s\n' "$art" |
            awk -v step="$step" \
                -v total="$line_count" \
                -v direction="$direction" \
                -v width="$available_width" '
                {
                    if ((direction == "top" && NR <= step) ||
                        (direction == "bottom" && NR > total - step)) {
                        print substr($0, 1, width)
                    } else {
                        print ""
                    }
                }
            '

            sleep "$speed"
            step=$((step + 1))
        done

        frame=$((frame + 1))
    done

    clear
}

show_animation
sleep 0.2