#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="build"
CONFIG_FILE="${CONFIG_DIR}/config.json"
DEFAULT_ARCH="x86_64"
DEFAULT_SERIAL="false"

if ! command -v dialog >/dev/null 2>&1; then
    echo "The 'dialog' utility is required to configure build options." >&2
    echo "Please install dialog (e.g. sudo apt install dialog) and rerun 'zig build config'." >&2
    exit 1
fi

mkdir -p "${CONFIG_DIR}"

current_arch="${DEFAULT_ARCH}"
serial_enabled="${DEFAULT_SERIAL}"

if [[ -f "${CONFIG_FILE}" ]]; then
    if extracted=$(grep -Eo '"architecture"[[:space:]]*:[[:space:]]*"[^"]+"' "${CONFIG_FILE}" | sed 's/.*"\([^"]*\)"/\1/' | tail -n1); then
        if [[ -n "${extracted}" ]]; then
            current_arch="${extracted}"
        fi
    fi

    if grep -Eq '"serial"[[:space:]]*:[[:space:]]*true' "${CONFIG_FILE}"; then
        serial_enabled="true"
    elif grep -Eq '"serial"[[:space:]]*:[[:space:]]*false' "${CONFIG_FILE}"; then
        serial_enabled="false"
    fi
fi

while true; do
    arch_desc="Target architecture (current: ${current_arch})"
    debug_status="Serial: ${serial_enabled}"
    debug_desc="Debug outputs (${debug_status})"

    selection=$(dialog \
        --clear \
        --stdout \
        --title "CaladanOS Configuration" \
        --menu "Select a category to configure" 18 70 6 \
        "architecture" "${arch_desc}" \
        "debug" "${debug_desc}" \
        "save" "Save and exit" \
    ) || { dialog --clear; exit 0; }

    case "${selection}" in
        architecture)
            arch_choice=$(dialog \
                --clear \
                --stdout \
                --title "Target Architecture" \
                --default-item "${current_arch}" \
                --menu "Select target architecture" 15 60 4 \
                "x86_64" "64-bit x86 architecture" \
            ) || continue
            current_arch="${arch_choice}"
            ;;
        debug)
            default_state="OFF"
            if [[ "${serial_enabled}" == "true" ]]; then
                default_state="ON"
            fi

            selection=$(dialog \
                --clear \
                --stdout \
                --separate-output \
                --title "Debug Options" \
                --checklist "Select debug features to enable" 18 70 6 \
                "serial" "Write kernel logs to serial COM1" "${default_state}" \
            ) || continue

            serial_enabled="false"
            if [[ -n "${selection}" ]]; then
                while IFS= read -r option; do
                    if [[ "${option}" == "serial" ]]; then
                        serial_enabled="true"
                    fi
                done <<<"${selection}"
            fi
            ;;
        save)
            {
                printf '{\n'
                printf '    "architecture": "%s",\n' "${current_arch}"
                printf '    "debug": {\n'
                printf '        "serial": %s\n' "${serial_enabled}"
                printf '    }\n'
                printf '}\n'
            } > "${CONFIG_FILE}"

            dialog --clear --msgbox "Saved configuration" 6 40
            clear
            exit 0
            ;;
        *)
            ;;
    esac
done
