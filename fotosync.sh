#!/usr/bin/env bash
set -euo pipefail

# fotosync.sh — ADB pull (Android) -> local staging -> rsync to specific USB stick
# Modes:
#   --init     create settings.conf (store PHONE_ID + USB_UUID), no sync
#   --save     run sync jobs from settings.conf
#   --dry-run  show what would happen (implies --save behavior but no writes)
#   --help

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="${PROJECT_DIR}/settings.conf"

log() { printf "[fotosync] %s\n" "$*"; }
die() { printf "[fotosync] ERROR: %s\n" "$*" >&2; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_pkg_mgr() {
  if have_cmd pacman; then echo "pacman"; return; fi
  if have_cmd apt-get; then echo "apt"; return; fi
  echo "unknown"
}

install_deps() {
  local mgr
  mgr="$(detect_pkg_mgr)"

  if have_cmd adb; then
    log "Dependency OK: adb"
    return 0
  fi

  log "adb not found. Trying to install android-tools/adb..."

  case "$mgr" in
    pacman)
      sudo pacman -Sy --noconfirm android-tools
      ;;
    apt)
      sudo apt-get update -y
      sudo apt-get install -y adb
      ;;
    *)
      die "No supported package manager found (pacman/apt). Install 'android-tools' (Arch) or 'adb' (Debian/Ubuntu) manually."
      ;;
  esac

  have_cmd adb || die "adb still missing after install attempt."
  log "Dependency installed: adb"
}

# Returns a single adb device id (authorized) or fails
pick_phone_id() {
  mapfile -t devs < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')
  if ((${#devs[@]}==0)); then
    die "No authorized adb device found. Unlock phone once + allow USB debugging (RSA prompt), then re-run."
  fi
  if ((${#devs[@]}==1)); then
    echo "${devs[0]}"
    return 0
  fi

  log "Multiple adb devices detected:"
  local i
  for i in "${!devs[@]}"; do
    printf "  [%d] %s\n" "$i" "${devs[$i]}"
  done
  die "More than one device connected. Disconnect the others and re-run."
}

# Returns UUID of a mounted removable partition (best-effort)
pick_usb_uuid() {
  mapfile -t candidates < <(
    lsblk -rpo NAME,UUID,MOUNTPOINT,RM,TYPE |
      awk '$5=="part" && $4==1 && $3!="" && $2!="" {print $2 "\t" $3 "\t" $1}'
  )

  if ((${#candidates[@]}==0)); then
    die "No mounted removable USB partition found. Mount your USB stick and re-run."
  fi
  if ((${#candidates[@]}==1)); then
    echo "${candidates[0]}" | awk '{print $1}'
    return 0
  fi

  log "Multiple removable mounted partitions found:"
  printf "  UUID\t\t\tMOUNTPOINT\tDEVICE\n"
  printf "  ----\t\t\t----------\t------\n"
  local line
  for line in "${candidates[@]}"; do
    printf "  %s\n" "$line"
  done
  die "More than one candidate USB partition mounted. Leave only the target USB stick mounted and re-run."
}

find_usb_mountpoint_by_uuid() {
  local mp
  mp="$(lsblk -rpo UUID,MOUNTPOINT | awk -v u="$USB_UUID" '$1==u {print $2; exit}')"
  [[ -n "$mp" ]] || die "USB stick with UUID=$USB_UUID is not mounted. Mount it and re-run."
  echo "$mp"
}

phone_path_exists() {
  local path="$1"
  adb -s "$PHONE_ID" shell "test -e '$path'" >/dev/null 2>&1
}

write_default_settings() {
  local phone_id usb_uuid
  phone_id="$(pick_phone_id)"
  usb_uuid="$(pick_usb_uuid)"

  cat > "$SETTINGS_FILE" <<EOF
# fotosync settings
# Generated on: $(date -Is)

# ADB device serial (from: adb devices)
PHONE_ID="$phone_id"

# Filesystem UUID of the USB stick partition (from: lsblk -f)
USB_UUID="$usb_uuid"

# Local staging base directory (phone pulls land here first)
IMPORT_DIR="\$HOME/photo-import/pixel"

# rsync flags (default: only add new files, never overwrite existing)
RSYNC_FLAGS="-av --ignore-existing"

# Sync jobs:
# Format: "NAME|PHONE_PATH|USB_SUBDIR"
# Example:
# SYNC_JOBS=(
#   "camera|/sdcard/DCIM/Camera|Backup/Pixel/DCIM/Camera"
#   "whatsapp|/sdcard/Android/media/com.whatsapp/WhatsApp/Media|Backup/Apps/WhatsApp/Media"
# )
SYNC_JOBS=(
)
EOF

  chmod 600 "$SETTINGS_FILE"
  log "Created $SETTINGS_FILE"
  log "PHONE_ID=$phone_id"
  log "USB_UUID=$usb_uuid"
}

load_settings() {
  [[ -f "$SETTINGS_FILE" ]] || die "settings.conf not found. Run: $0 --init"
  # shellcheck disable=SC1090
  source "$SETTINGS_FILE"

  [[ -n "${PHONE_ID:-}" ]] || die "PHONE_ID missing in settings.conf"
  [[ -n "${USB_UUID:-}" ]] || die "USB_UUID missing in settings.conf"
  [[ -n "${IMPORT_DIR:-}" ]] || die "IMPORT_DIR missing in settings.conf"
  [[ -n "${RSYNC_FLAGS:-}" ]] || die "RSYNC_FLAGS missing in settings.conf"
}

require_expected_phone() {
  local current
  current="$(pick_phone_id)"
  [[ "$current" == "$PHONE_ID" ]] || die "Connected phone ($current) does not match configured PHONE_ID ($PHONE_ID). Aborting."
}

usage() {
  cat <<EOF
Usage:
  $0 --init
  $0 --save [--dry-run]
  $0 --help

--init     Create settings.conf (stores PHONE_ID + USB_UUID). Does NOT copy anything.
--save     Run SYNC_JOBS: adb pull -> local staging -> rsync to USB.
--dry-run  Show what would be copied (no changes).
EOF
}

MODE=""
DRY_RUN="0"

parse_args() {
  if (($#==0)); then usage; exit 1; fi

  while (($#)); do
    case "$1" in
      --init) MODE="init" ;;
      --save) MODE="save" ;;
      --dry-run) DRY_RUN="1" ;;
      --help|-h) usage; exit 0 ;;
      *) die "Unknown arg: $1 (use --help)" ;;
    esac
    shift
  done

  [[ -n "$MODE" ]] || die "Choose --init or --save"
}

do_init() {
  install_deps
  if [[ -f "$SETTINGS_FILE" ]]; then
    log "settings.conf already exists: $SETTINGS_FILE"
    log "Nothing to do."
    return 0
  fi
  log "Initializing settings.conf (no copying will be done)..."
  write_default_settings
  log "Init done. Now edit settings.conf and add SYNC_JOBS, then run: $0 --save"
}

do_save() {
  install_deps
  load_settings
  require_expected_phone

  local usb_mp
  usb_mp="$(find_usb_mountpoint_by_uuid)"

  mkdir -p "$IMPORT_DIR"

  if [[ "${#SYNC_JOBS[@]}" -eq 0 ]]; then
    die "SYNC_JOBS is empty. Edit settings.conf and add jobs, then re-run --save."
  fi

  log "USB mountpoint: $usb_mp"
  log "Staging base dir: $IMPORT_DIR"
  [[ "$DRY_RUN" == "1" ]] && log "DRY RUN enabled: no data will be copied."

  local job name phone_src usb_subdir staging dest rsync_flags
  rsync_flags="$RSYNC_FLAGS"
  if [[ "$DRY_RUN" == "1" ]]; then
    rsync_flags="$rsync_flags -n"
  fi

  for job in "${SYNC_JOBS[@]}"; do
    # Correct delimiter handling: split by "|"
    IFS="|" read -r name phone_src usb_subdir <<< "$job"

    if [[ -z "${name:-}" || -z "${phone_src:-}" || -z "${usb_subdir:-}" ]]; then
      log "Skipping invalid SYNC_JOBS entry (needs: NAME|PHONE_PATH|USB_SUBDIR): $job"
      continue
    fi

    if ! phone_path_exists "$phone_src"; then
      log "JOB [$name] Skip: phone path not found: $phone_src"
      continue
    fi

    staging="${IMPORT_DIR%/}/${name}"
    dest="${usb_mp%/}/${usb_subdir}"

    mkdir -p "$staging"
    mkdir -p "$dest"

    log "JOB [$name] adb pull: $phone_src -> $staging"
    if [[ "$DRY_RUN" == "1" ]]; then
      log "JOB [$name] (dry-run) skipping adb pull"
    else
      # adb pull is incremental-ish: existing files are typically skipped unless changed
      if ! adb -s "$PHONE_ID" pull "$phone_src" "$staging" >/dev/null 2>&1; then
        log "JOB [$name] WARNING: adb pull failed for $phone_src (skipping)."
        continue
      fi
    fi

    log "JOB [$name] rsync: $staging/ -> $dest/"
    # shellcheck disable=SC2086
    rsync $rsync_flags "$staging/" "$dest/"
  done

  log "Save done."
}

main() {
  parse_args "$@"
  case "$MODE" in
    init) do_init ;;
    save) do_save ;;
    *) die "Internal: unknown MODE=$MODE" ;;
  esac
}

main "$@"
