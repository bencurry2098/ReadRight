#!/usr/bin/env bash
# Usage:
#   ./scripts/screenshot.sh                        # prompts for all credentials
#   ./scripts/screenshot.sh student                # screenshot student only
#   ./scripts/screenshot.sh teacher                # screenshot teacher only
#   ./scripts/screenshot.sh student teacher        # both (default)
#
# Credentials can be passed as env vars to skip prompts:
#   STUDENT_EMAIL=... STUDENT_PASS=... TEACHER_EMAIL=... TEACHER_PASS=... ./scripts/screenshot.sh

set -euo pipefail

DEVICE="emulator-5554"
OUTPUT_DIR="screenshots/$(date +%Y-%m-%d_%H-%M-%S)"
mkdir -p "$OUTPUT_DIR"

# ── helpers ──────────────────────────────────────────────────────────────────

adb_screenshot() {
  local name="$1"
  local path="$OUTPUT_DIR/${name}.png"
  adb -s "$DEVICE" shell screencap -p /sdcard/screen.png
  adb -s "$DEVICE" pull /sdcard/screen.png "$path" >/dev/null
  adb -s "$DEVICE" shell rm /sdcard/screen.png
  echo "  saved: $path"
}

wait_for_idle() {
  # Wait for the UI thread to be idle (no pending frames)
  sleep "${1:-2}"
}

tap() {
  adb -s "$DEVICE" shell input tap "$1" "$2"
  wait_for_idle 1.5
}

tap_text() {
  # Tap a UI element by visible text using uiautomator
  local text="$1"
  local coords
  coords=$(adb -s "$DEVICE" shell uiautomator dump /sdcard/ui.xml >/dev/null && \
    adb -s "$DEVICE" shell cat /sdcard/ui.xml | \
    grep -o "text=\"${text}\"[^/]*/>" | head -1 | \
    grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | \
    grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]' || true)

  if [[ -z "$coords" ]]; then
    echo "  [warn] could not find element with text: $text"
    return 1
  fi

  # Parse "[x1,y1][x2,y2]" -> midpoint
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
  adb -s "$DEVICE" shell input text "$1"
  wait_for_idle 0.5
}

clear_field() {
  # Select all + delete
  adb -s "$DEVICE" shell input keyevent KEYCODE_CTRL_A
  adb -s "$DEVICE" shell input keyevent KEYCODE_DEL
  wait_for_idle 0.3
}

navigate_to_login() {
  # Force-stop then relaunch to always land on login
  adb -s "$DEVICE" shell am force-stop com.example.readright 2>/dev/null || true
  sleep 1
  adb -s "$DEVICE" shell monkey -p com.example.readright -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  wait_for_idle 3
}

login_as() {
  local email="$1"
  local pass="$2"

  # Tap Email field (labelText: 'Email') and type
  tap_text "Email" || {
    echo "  [warn] falling back to coordinate tap for Email field"
    # Fallback: tap approximate center of email field - adjust if layout changes
    tap 540 650
  }
  clear_field
  type_text "$email"

  # Tap Password field
  tap_text "Password" || tap 540 780
  clear_field
  type_text "$pass"

  # Tap login button
  tap_text "Log In" || tap_text "Login" || tap_text "Sign In" || tap 540 920
  wait_for_idle 4
}

logout() {
  # Tap the logout icon in the AppBar (top-right)
  # The icon is Icons.logout — find it via content-desc or coordinate
  tap_text "logout" 2>/dev/null || {
    # AppBar logout button is typically top-right corner
    local screen_width=1080
    tap $(( screen_width - 80 )) 90
  }
  wait_for_idle 3
}

# ── credential prompts ────────────────────────────────────────────────────────

prompt_creds() {
  local role="$1"
  local email_var="${role^^}_EMAIL"
  local pass_var="${role^^}_PASS"

  if [[ -z "${!email_var:-}" ]]; then
    read -rp "  ${role} email: " val
    export "$email_var"="$val"
  fi
  if [[ -z "${!pass_var:-}" ]]; then
    read -rsp "  ${role} password: " val
    echo
    export "$pass_var"="$val"
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

  # Practice tab (index 1)
  tap_text "Practice"
  adb_screenshot "student_02_practice"

  # Words tab (index 2)
  tap_text "Words"
  adb_screenshot "student_03_word_list"

  # Tap first word list item if present
  adb -s "$DEVICE" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
  tap_text "Dolch Pre-Primer" 2>/dev/null && {
    wait_for_idle 2
    adb_screenshot "student_04_word_list_detail"
    adb -s "$DEVICE" shell input keyevent KEYCODE_BACK
    wait_for_idle 1.5
  }

  # Progress tab (index 3)
  tap_text "Progress"
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

  # Word Lists tab
  tap_text "Word Lists"
  adb_screenshot "teacher_02_word_lists"

  # Tap first word list
  tap_text "Dolch Pre-Primer" 2>/dev/null && {
    wait_for_idle 2
    adb_screenshot "teacher_03_word_list_detail"
    adb -s "$DEVICE" shell input keyevent KEYCODE_BACK
    wait_for_idle 1.5
  }

  # Students tab
  tap_text "Students"
  adb_screenshot "teacher_04_students"

  # Tap first student if any
  adb -s "$DEVICE" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
  # Try tapping the first list item below the Students heading
  # We do a coordinate-based swipe-and-tap on the first card
  sleep 0.5
  # Attempt to tap first student entry (row ~300px from top)
  adb -s "$DEVICE" shell input tap 540 400
  wait_for_idle 2
  # If we navigated somewhere, screenshot and go back
  adb_screenshot "teacher_05_student_view"
  adb -s "$DEVICE" shell input keyevent KEYCODE_BACK
  wait_for_idle 1.5

  # Settings tab
  tap_text "Settings"
  adb_screenshot "teacher_06_settings"

  logout
  echo "  Teacher screenshots done."
}

# ── main ─────────────────────────────────────────────────────────────────────

ROLES=("${@:-student teacher}")
if [[ $# -eq 0 ]]; then
  ROLES=("student" "teacher")
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
