#!/usr/bin/env bash
# Usage:
#   ./scripts/screenshot.sh                        # prompts for all credentials
#   ./scripts/screenshot.sh student                # screenshot student only
#   ./scripts/screenshot.sh teacher                # screenshot teacher only
#
# Credentials can be passed as env vars to skip prompts:
#   STUDENT_EMAIL=... STUDENT_PASS=... TEACHER_EMAIL=... TEACHER_PASS=... ./scripts/screenshot.sh

set -uo pipefail

DEVICE="emulator-5554"
OUTPUT_DIR="screenshots/$(date +%Y-%m-%d_%H-%M-%S)"
mkdir -p "$OUTPUT_DIR"

# ── find adb ─────────────────────────────────────────────────────────────────

_find_adb() {
  local sdk_adb="$HOME/Library/Android/sdk/platform-tools/adb"
  if [[ -x "$sdk_adb" ]]; then echo "$sdk_adb"; return; fi
  local found
  found=$(find "$HOME/Library/Android/sdk" -name adb -type f 2>/dev/null | head -1)
  if [[ -n "$found" ]]; then echo "$found"; return; fi
  if command -v adb >/dev/null 2>&1; then command -v adb; return; fi
  echo ""
}
ADB=$(_find_adb)
[[ -n "$ADB" ]] || { echo "FATAL: adb not found." >&2; exit 1; }

# ── screen geometry (resolved once at startup) ────────────────────────────────

SW=0; SH=0
_init_screen() {
  local size
  size=$("$ADB" -s "$DEVICE" shell wm size | grep -o '[0-9]*x[0-9]*' | tail -1)
  SW=$(echo "$size" | cut -dx -f1)
  SH=$(echo "$size" | cut -dx -f2)
  echo "  Screen: ${SW}x${SH}px"
}

# tap_pct <x_pct> <y_pct> — converts percentage to physical pixels and taps
tap_pct() {
  local x=$(( SW * $1 / 100 ))
  local y=$(( SH * $2 / 100 ))
  "$ADB" -s "$DEVICE" shell input tap "$x" "$y" || true
  sleep 1.5
}

# ── helpers ───────────────────────────────────────────────────────────────────

die() { echo "FATAL: $*" >&2; exit 1; }

adb_ok() {
  "$ADB" -s "$DEVICE" get-state >/dev/null 2>&1 || \
    die "Device $DEVICE not found. Is the emulator running?"
}

adb_screenshot() {
  local name="$1"
  local path="$OUTPUT_DIR/${name}.png"
  "$ADB" -s "$DEVICE" shell screencap -p /sdcard/screen.png || { echo "  [warn] screencap failed for $name"; return; }
  "$ADB" -s "$DEVICE" pull /sdcard/screen.png "$path" >/dev/null 2>&1 || { echo "  [warn] pull failed for $name"; return; }
  "$ADB" -s "$DEVICE" shell rm /sdcard/screen.png 2>/dev/null || true
  echo "  saved: $path"
}

clear_field() {
  "$ADB" -s "$DEVICE" shell input keyevent KEYCODE_CTRL_A || true
  sleep 0.2
  "$ADB" -s "$DEVICE" shell input keyevent KEYCODE_DEL || true
  sleep 0.3
}

type_text() {
  # adb input text chokes on @ and some special chars — percent-encode them
  local encoded
  encoded=$(printf '%s' "$1" | sed 's/@/%40/g; s/\./%2E/g')
  "$ADB" -s "$DEVICE" shell input text "$encoded" || true
  sleep 0.5
}

press_back() {
  "$ADB" -s "$DEVICE" shell input keyevent KEYCODE_BACK || true
  sleep 1.5
}

launch_app() {
  echo "  Launching app..."
  "$ADB" -s "$DEVICE" shell am force-stop com.example.readright 2>/dev/null || true
  sleep 1
  "$ADB" -s "$DEVICE" shell am start -n com.example.readright/.MainActivity >/dev/null 2>&1 || \
    "$ADB" -s "$DEVICE" shell monkey -p com.example.readright \
      -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || \
    die "Could not launch app. Is com.example.readright installed on $DEVICE?"
  sleep 4
}

# ── login ─────────────────────────────────────────────────────────────────────
# Layout is a vertically-centered Column. Percentages tuned for a ~1080x2400
# display; tweak LOGIN_EMAIL_Y / LOGIN_PASS_Y / LOGIN_BTN_Y if fields are missed.

LOGIN_EMAIL_Y=42
LOGIN_PASS_Y=53
LOGIN_BTN_Y=63

login_as() {
  local email="$1"
  local pass="$2"
  echo "  Logging in as $email..."

  tap_pct 50 $LOGIN_EMAIL_Y
  clear_field
  type_text "$email"

  tap_pct 50 $LOGIN_PASS_Y
  clear_field
  type_text "$pass"

  tap_pct 50 $LOGIN_BTN_Y
  sleep 6   # wait for auth round-trip + navigation
}

# ── bottom nav bar ────────────────────────────────────────────────────────────
# 4 evenly-spaced tabs; centers at 12.5%, 37.5%, 62.5%, 87.5% of width.
# Nav bar sits just above the system gesture bar (~95% down the screen).

NAV_Y=95

nav_tab() {
  case "$1" in
    0) tap_pct 13 $NAV_Y ;;
    1) tap_pct 38 $NAV_Y ;;
    2) tap_pct 63 $NAV_Y ;;
    3) tap_pct 88 $NAV_Y ;;
  esac
}

logout() {
  echo "  Logging out..."
  # AppBar logout icon is top-right corner (~93% x, ~5% y)
  tap_pct 93 5
  sleep 3
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

# ── student flow ──────────────────────────────────────────────────────────────
# Student nav: 0=Dashboard 1=Practice 2=Words 3=Progress

screenshot_student() {
  echo ""
  echo "=== STUDENT screenshots ==="
  prompt_creds "student"
  launch_app

  adb_screenshot "00_login"
  login_as "$STUDENT_EMAIL" "$STUDENT_PASS"

  nav_tab 0   # Dashboard
  sleep 1
  adb_screenshot "student_01_dashboard"

  nav_tab 1   # Practice
  adb_screenshot "student_02_practice"

  nav_tab 2   # Words
  adb_screenshot "student_03_word_list"

  # Tap first word list card (~30% from top)
  tap_pct 50 35
  sleep 2
  adb_screenshot "student_04_word_list_detail"
  press_back

  nav_tab 3   # Progress
  adb_screenshot "student_05_progress"

  logout
  echo "  Student screenshots done."
}

# ── teacher flow ──────────────────────────────────────────────────────────────
# Teacher nav: 0=Dashboard 1=Word Lists 2=Students 3=Settings

screenshot_teacher() {
  echo ""
  echo "=== TEACHER screenshots ==="
  prompt_creds "teacher"
  launch_app
  login_as "$TEACHER_EMAIL" "$TEACHER_PASS"

  adb_screenshot "teacher_01_dashboard"

  nav_tab 1   # Word Lists
  adb_screenshot "teacher_02_word_lists"

  tap_pct 50 30   # first word list card
  sleep 2
  adb_screenshot "teacher_03_word_list_detail"
  press_back

  nav_tab 2   # Students
  adb_screenshot "teacher_04_students"

  tap_pct 50 30   # first student card
  sleep 2
  adb_screenshot "teacher_05_student_view"
  press_back

  nav_tab 3   # Settings
  adb_screenshot "teacher_06_settings"

  logout
  echo "  Teacher screenshots done."
}

# ── main ─────────────────────────────────────────────────────────────────────

adb_ok
_init_screen

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
