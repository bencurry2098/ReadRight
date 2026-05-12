#!/usr/bin/env bash
# Usage:
#   ./scripts/screenshot.sh                        # prompts for all credentials
#   ./scripts/screenshot.sh student                # screenshot student only
#   ./scripts/screenshot.sh teacher                # screenshot teacher only
#   ./scripts/screenshot.sh student teacher        # both (default)
#
# Credentials can be passed as env vars to skip prompts:
#   STUDENT_EMAIL=... STUDENT_PASS=... TEACHER_EMAIL=... TEACHER_PASS=... ./scripts/screenshot.sh

set -uo pipefail  # -e removed: adb commands return non-zero for benign reasons

DEVICE="emulator-5554"
OUTPUT_DIR="screenshots/$(date +%Y-%m-%d_%H-%M-%S)"
mkdir -p "$OUTPUT_DIR"

# ── helpers ──────────────────────────────────────────────────────────────────

die() { echo "FATAL: $*" >&2; exit 1; }

adb_ok() {
  # Verify adb can see the device before we start
  adb -s "$DEVICE" get-state >/dev/null 2>&1 || die "Device $DEVICE not found. Is the emulator running and adb connected?"
}

adb_screenshot() {
  local name="$1"
  local path="$OUTPUT_DIR/${name}.png"
  adb -s "$DEVICE" shell screencap -p /sdcard/screen.png || { echo "  [warn] screencap failed for $name"; return; }
  adb -s "$DEVICE" pull /sdcard/screen.png "$path" >/dev/null 2>&1 || { echo "  [warn] pull failed for $name"; return; }
  adb -s "$DEVICE" shell rm /sdcard/screen.png 2>/dev/null || true
  echo "  saved: $path"
}

wait_for_idle() {
  sleep "${1:-2}"
}

tap() {
  adb -s "$DEVICE" shell input tap "$1" "$2" || true
  wait_for_idle 1.5
}

tap_text() {
  local text="$1"
  local coords

  adb -s "$DEVICE" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true

  coords=$(adb -s "$DEVICE" shell cat /sdcard/ui.xml 2>/dev/null | \
    grep -o "text=\"${text}\"[^/]*/>" | head -1 | \
    grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | \
    grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]' || true)

  if [[ -z "$coords" ]]; then
    echo "  [warn] could not find element with text: $text"
    return 1
  fi

  local x1 y1 x2 y2 mx my
  x1=$(echo "$coords" | grep -o '^\[[0-9]*' | tr -d '[')
  y1=$(echo "$coords" | grep -o ',[0-9]*\]' | head -1 | tr -d ',]')
  x2=$(echo "$coords" | grep -o '\[[0-9]*,' | tail -1 | tr -d '[,')
  y2=$(echo "$coords" | grep -o ',[0-9]*\]' | tail -1 | tr -d ',]')
  mx=$(( (x1 + x2) / 2 ))
  my=$(( (y1 + y2) / 2 ))
  tap "$mx" "$my"
}

type_text() {
  # URL-encode spaces as %s; adb input text doesn't handle raw spaces well
  local encoded
  encoded=$(printf '%s' "$1" | sed 's/ /%s/g')
  adb -s "$DEVICE" shell input text "$encoded" || true
  wait_for_idle 0.5
}

clear_field() {
  adb -s "$DEVICE" shell input keyevent KEYCODE_CTRL_A || true
  adb -s "$DEVICE" shell input keyevent KEYCODE_DEL || true
  wait_for_idle 0.3
}

navigate_to_login() {
  echo "  Launching app..."
  adb -s "$DEVICE" shell am force-stop com.example.readright 2>/dev/null || true
  sleep 1
  adb -s "$DEVICE" shell am start -n com.example.readright/.MainActivity 2>/dev/null || \
    adb -s "$DEVICE" shell monkey -p com.example.readright -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || \
    die "Could not launch com.example.readright — is the app installed on $DEVICE?"
  wait_for_idle 4
}

login_as() {
  local email="$1"
  local pass="$2"
  echo "  Logging in as $email..."

  tap_text "Email" || { echo "  [warn] Email field not found, using coordinates"; tap 540 650; }
  clear_field
  type_text "$email"

  tap_text "Password" || { echo "  [warn] Password field not found, using coordinates"; tap 540 780; }
  clear_field
  type_text "$pass"

  tap_text "Log In" || tap_text "Login" || tap_text "Sign In" || { echo "  [warn] Login button not found, using coordinates"; tap 540 920; }
  wait_for_idle 5
}

logout() {
  echo "  Logging out..."
  # Try text first, then top-right corner coordinate
  tap_text "logout" 2>/dev/null || tap 1000 90
  wait_for_idle 3
}

# ── credential prompts ────────────────────────────────────────────────────────

prompt_creds() {
  local role="$1"
  local role_upper
  role_upper=$(echo "$role" | tr '[:lower:]' '[:upper:]')
  local email_var="${role_upper}_EMAIL"
  local pass_var="${role_upper}_PASS"

  if [[ -z "${!email_var:-}" ]]; then
    read -rp "  ${role} email: " val
    export "${email_var}=${val}"
  fi
  if [[ -z "${!pass_var:-}" ]]; then
    read -rsp "  ${role} password: " val
    echo
    export "${pass_var}=${val}"
  fi
}

# ── student screenshots ───────────────────────────────────────────────────────

screenshot_student() {
  echo ""
  echo "=== STUDENT screenshots ==="
  prompt_creds "student"

  navigate_to_login
  adb_screenshot "00_login"

  login_as "$STUDENT_EMAIL" "$STUDENT_PASS"
  adb_screenshot "student_01_dashboard"

  tap_text "Practice" || true
  adb_screenshot "student_02_practice"

  tap_text "Words" || true
  adb_screenshot "student_03_word_list"

  tap_text "Dolch Pre-Primer" 2>/dev/null && {
    wait_for_idle 2
    adb_screenshot "student_04_word_list_detail"
    adb -s "$DEVICE" shell input keyevent KEYCODE_BACK || true
    wait_for_idle 1.5
  } || true

  tap_text "Progress" || true
  adb_screenshot "student_05_progress"

  logout
  echo "  Student screenshots done."
}

# ── teacher screenshots ───────────────────────────────────────────────────────

screenshot_teacher() {
  echo ""
  echo "=== TEACHER screenshots ==="
  prompt_creds "teacher"

  navigate_to_login
  login_as "$TEACHER_EMAIL" "$TEACHER_PASS"
  adb_screenshot "teacher_01_dashboard"

  tap_text "Word Lists" || true
  adb_screenshot "teacher_02_word_lists"

  tap_text "Dolch Pre-Primer" 2>/dev/null && {
    wait_for_idle 2
    adb_screenshot "teacher_03_word_list_detail"
    adb -s "$DEVICE" shell input keyevent KEYCODE_BACK || true
    wait_for_idle 1.5
  } || true

  tap_text "Students" || true
  adb_screenshot "teacher_04_students"

  # Tap the first student card (first item below the header)
  tap 540 400
  wait_for_idle 2
  adb_screenshot "teacher_05_student_view"
  adb -s "$DEVICE" shell input keyevent KEYCODE_BACK || true
  wait_for_idle 1.5

  tap_text "Settings" || true
  adb_screenshot "teacher_06_settings"

  logout
  echo "  Teacher screenshots done."
}

# ── main ─────────────────────────────────────────────────────────────────────

# Verify adb can see the device before doing anything
adb_ok

if [[ $# -eq 0 ]]; then
  ROLES=("student" "teacher")
else
  ROLES=("$@")
fi

echo "Screenshots will be saved to: $OUTPUT_DIR"
echo "Device: $DEVICE"

for role in "${ROLES[@]}"; do
  case "$role" in
    student) screenshot_student ;;
    teacher) screenshot_teacher ;;
    *) echo "Unknown role: $role (use 'student' or 'teacher')" ;;
  esac
done

echo ""
echo "Done. All screenshots in: $OUTPUT_DIR"
