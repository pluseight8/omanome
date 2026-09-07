#!/usr/bin/env bash
# Event-driven input/display hotplug stream. This is deliberately one
# long-lived observer: it never polls and it never carries typed text.
set -u

command -v udevadm >/dev/null 2>&1 || exit 127
command -v jq >/dev/null 2>&1 || exit 127

udevadm monitor --udev --property | while IFS= read -r line; do
  if [[ -z "$line" ]]; then
    if [[ -n "${action:-}" && ( "${subsystem:-}" == "input" || "${subsystem:-}" == "drm" ) ]]; then
      jq -cn \
        --arg type "device.event" \
        --arg action "$action" \
        --arg subsystem "$subsystem" \
        --arg devpath "${devpath:-}" \
        --arg name "${id_model:-${name:-}}" \
        --arg vendorId "${id_vendor_id:-}" \
        --arg productId "${id_model_id:-}" \
        --arg serial "${id_serial_short:-}" \
        --arg path "${id_path:-${devpath:-}}" \
        --arg transport "${id_bus:-}" \
        --arg seat "${id_seat:-seat0}" \
        --argjson keyboard "$( [[ "${id_input_keyboard:-}" == 1 ]] && printf true || printf false )" \
        --argjson touchscreen "$( [[ "${id_input_touchscreen:-}" == 1 ]] && printf true || printf false )" \
        --argjson tablet "$( [[ "${id_input_tablet:-}" == 1 ]] && printf true || printf false )" \
        '{schemaVersion:1,type:$type,action:$action,subsystem:$subsystem,device:{devpath:$devpath,name:$name,vendorId:$vendorId,productId:$productId,serial:$serial,path:$path,transport:$transport,seat:$seat,capabilities:{keyboard:$keyboard,touchscreen:$touchscreen,tablet:$tablet}}}'
    fi
    action=""
    subsystem=""
    devpath=""
    id_model=""
    name=""
    id_vendor_id=""
    id_model_id=""
    id_serial_short=""
    id_path=""
    id_bus=""
    id_seat=""
    id_input_keyboard=""
    id_input_touchscreen=""
    id_input_tablet=""
    continue
  fi
  case "$line" in
    ACTION=*) action="${line#ACTION=}" ;;
    SUBSYSTEM=*) subsystem="${line#SUBSYSTEM=}" ;;
    DEVPATH=*) devpath="${line#DEVPATH=}" ;;
    ID_MODEL=*) id_model="${line#ID_MODEL=}" ;;
    NAME=*) name="${line#NAME=}" ;;
    ID_VENDOR_ID=*) id_vendor_id="${line#ID_VENDOR_ID=}" ;;
    ID_MODEL_ID=*) id_model_id="${line#ID_MODEL_ID=}" ;;
    ID_SERIAL_SHORT=*) id_serial_short="${line#ID_SERIAL_SHORT=}" ;;
    ID_PATH=*) id_path="${line#ID_PATH=}" ;;
    ID_BUS=*) id_bus="${line#ID_BUS=}" ;;
    ID_SEAT=*) id_seat="${line#ID_SEAT=}" ;;
    ID_INPUT_KEYBOARD=*) id_input_keyboard="${line#ID_INPUT_KEYBOARD=}" ;;
    ID_INPUT_TOUCHSCREEN=*) id_input_touchscreen="${line#ID_INPUT_TOUCHSCREEN=}" ;;
    ID_INPUT_TABLET=*) id_input_tablet="${line#ID_INPUT_TABLET=}" ;;
  esac
done
