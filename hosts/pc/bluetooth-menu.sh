#!/usr/bin/env bash

show_error() {
    printf '%s\n' "$1" | fuzzel --dmenu --prompt 'Bluetooth error: ' || true
}

run_action() {
    local output

    if ! output=$(bluetoothctl "$@" 2>&1); then
        show_error "$output"
    fi
}

get_property() {
    local info=$1
    local property=$2

    if grep -q "${property}: yes" <<< "$info"; then
        printf 'yes\n'
    else
        printf 'no\n'
    fi
}

toggle_property() {
    local info=$1
    local property=$2
    local command=$3

    if [[ $(get_property "$info" "$property") == yes ]]; then
        run_action "$command" off
    else
        run_action "$command" on
    fi
}

device_menu() {
    local address=$1
    local name=$2
    local info choice

    while true; do
        if ! info=$(bluetoothctl info "$address"); then
            show_error "Could not read device information."
            return
        fi

        local options=(
            "Connected: $(get_property "$info" Connected)"
            "Paired: $(get_property "$info" Paired)"
            "Trusted: $(get_property "$info" Trusted)"
            'Back'
        )

        if ! choice=$(printf '%s\n' "${options[@]}" | fuzzel --dmenu --index --prompt "$name: "); then
            return
        fi

        case "$choice" in
            0)
                if [[ $(get_property "$info" Connected) == yes ]]; then
                    run_action disconnect "$address"
                else
                    run_action connect "$address"
                fi
                ;;
            1)
                if [[ $(get_property "$info" Paired) == yes ]]; then
                    run_action remove "$address"
                    return
                else
                    run_action --timeout 30 --agent NoInputNoOutput pair "$address"
                fi
                ;;
            2)
                if [[ $(get_property "$info" Trusted) == yes ]]; then
                    run_action untrust "$address"
                else
                    run_action trust "$address"
                fi
                ;;
            *)
                return
                ;;
        esac
    done
}

if [[ ${1:-} == --status ]]; then
    if bluetoothctl show | grep -q 'Powered: yes'; then
        bluetoothctl devices Connected
    else
        printf 'Bluetooth off\n'
    fi
    exit 0
fi

while true; do
    if ! controller=$(bluetoothctl show); then
        show_error 'No Bluetooth controller found.'
        exit 1
    fi

    options=(
        "Power: $(get_property "$controller" Powered)"
        "Scan for devices"
        "Pairable: $(get_property "$controller" Pairable)"
        "Discoverable: $(get_property "$controller" Discoverable)"
    )

    mapfile -t devices < <(bluetoothctl devices)

    for device in "${devices[@]}"; do
        read -r _ address name <<< "$device"
        options+=("$name [$address]")
    done

    if ! choice=$(printf '%s\n' "${options[@]}" | fuzzel --dmenu --index --prompt 'Bluetooth: '); then
        exit 0
    fi

    case "$choice" in
        0)
            if [[ $(get_property "$controller" Powered) == no ]]; then
                rfkill unblock bluetooth
            fi
            toggle_property "$controller" Powered power
            ;;
        1)
            run_action --timeout 5 scan on
            ;;
        2)
            toggle_property "$controller" Pairable pairable
            ;;
        3)
            toggle_property "$controller" Discoverable discoverable
            ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 4 && choice < ${#options[@]} )); then
                read -r _ address name <<< "${devices[choice - 4]}"
                device_menu "$address" "$name"
            fi
            ;;
    esac
done
