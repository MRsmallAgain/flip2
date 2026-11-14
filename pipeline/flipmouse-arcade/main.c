/*
 * Virtual mouse for keypad phones — vendored from https://github.com/TylerBoni/FlipMouse
 * Original by tyler boni <tyler.boni@gmail.com> (MIT per upstream README).
 *
 * flip2-repo local patch (see VENDORED.md): passive until activated.
 * Upstream grabbed the keypads at startup and toggled on a Star tap — that
 * steals the * key from the null-keyboard IME (T9 candidate cycling +
 * hold-* dictation). Patched behavior:
 *   - passive observer until activated (no grab; the system sees every key)
 *   - toggle: hold the upper-left soft key (139) for HOLD_TOGGLE_MS and
 *     release — enables mouse mode when passive, releases the cursor when
 *     active. Toggling on release means we never grab while a key is
 *     physically down (that would strand Android's synthetic-repeat timer);
 *     in mouse mode a short soft-key tap still scrolls up one step.
 *   - while active: keypads grabbed; D-pad moves, OK clicks, pound scrolls
 *     down, soft-left scrolls up, del toggles drag, volume = speed. In mouse
 *     mode the right soft key passes through so the Shortcuts bar still fires.
 *   - a Star tap exits back to passive (grabs released, IME unaffected)
 *
 * flip2 landscape gamepad (same daemon — pipeline/landscape-gamepad):
 *   - when landscape (dumpsys) and gamepad.conf landscape_auto=1: auto gamepad
 *     remap (virtual uinput gamepad); no separate Flip2Gamepad process.
 *   - hold right soft key (48) HOLD_TOGGLE_MS in landscape gamepad mode: drop
 *     remap and use virtual mouse with D-pad rotated for landscape (cursor only).
 *   - tap right soft key (48) in gamepad mode: R1 (BTN_TR), press + release.
 *   - soft-left hold still toggles full passive ↔ mouse (portrait-oriented mouse).
 */

// #define DEBUG 1

#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/input-event-codes.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libevdev/libevdev-uinput.h>
#include <dirent.h>
#include <limits.h>
#include <stdarg.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/signalfd.h>
#include <sys/time.h>
#include <time.h>

/* Configuration */
#define DEV_INPUT "/dev/input"
#define LOG_FILE "/cache/FlipMouse.log"
#define SPEED_FILE "/data/local/flip2/flipmouse-speed"
#define GAMEPAD_CONFIG "/data/local/flip2/gamepad.conf"
#define POLL_LANDSCAPE_MS 1500
#define BACK_REAL_HOLD_MS 2000
#define SOFT_RIGHT_CODE 48
#define MESSENGER_CODE 30
#define AXIS_GP_MAX 32767
#define AXIS_GP_MIN -32767
#define STICK_EDGE AXIS_GP_MAX

/* The keypad can report more than one direction at a time, so the D-pad and the
 * numpad stick are tracked as sets of held keys. Treating them as a single
 * value meant any release zeroed both axes: lifting one finger dropped the
 * other direction too, and the key still held never re-fired. */
#define DPAD_BIT_UP 0x01
#define DPAD_BIT_DOWN 0x02
#define DPAD_BIT_LEFT 0x04
#define DPAD_BIT_RIGHT 0x08

/* The numpad cross is a second D-pad, so it feeds the same left stick + hat as
 * DPAD_BIT_*. It keeps its own per-key bits because 1/3/7/9 are diagonals: one
 * key sets two directions, and a direction must only clear when no other held
 * key still wants it. It used to have its own set that wrote only
 * ABS_RX/ABS_RY (the right stick); Astro Loop's InputRouter.onMotion reads
 * AXIS_X/AXIS_Y and AXIS_HAT_X/AXIS_HAT_Y and never the right stick, so every
 * numpad direction was invisible in-game. Key 6 was also missing entirely. */
#define NPAD_BIT_1 0x001
#define NPAD_BIT_2 0x002
#define NPAD_BIT_3 0x004
#define NPAD_BIT_4 0x008
#define NPAD_BIT_5 0x010
#define NPAD_BIT_6 0x020
#define NPAD_BIT_7 0x040
#define NPAD_BIT_8 0x080
#define NPAD_BIT_9 0x100
#ifndef FLIPMOUSE_DEFAULT_SPEED
#define FLIPMOUSE_DEFAULT_SPEED 39
#endif
#ifdef DEBUG
#define ENABLE_LOG 1
#else
#define ENABLE_LOG 0
#endif

/* Constants */
#define MIN_MOUSE_SPEED 1
#define WHEEL_SLOWDOWN_FACTOR 5

/* Held-key auto-repeat (local patch): the keypads have no kernel autorepeat
 * (no EV_REP in their capabilities) and Android's framework repeater never
 * sees the keys while the keypads are grabbed, so holding a direction key
 * would otherwise move exactly one step. Synthesize Android-like repeat:
 * one step on press, then repeats after REPEAT_DELAY_MS and every
 * REPEAT_INTERVAL_MS until release. */
#define REPEAT_DELAY_MS 400
#define REPEAT_INTERVAL_MS 100
#define WHEEL_REPEAT_INTERVAL_MS (WHEEL_SLOWDOWN_FACTOR * REPEAT_INTERVAL_MS)
/* Upper-left soft key (139/KEY_MENU): hold this long, then release, to toggle
 * mouse mode (enable when passive, release the cursor when active). */
#define SOFTKEY_CODE 139
#define HOLD_TOGGLE_MS 1000

/* Non-standard kernel codes on this unit's matrix-keypad (matrix-keypad.kl):
 * star = 522, pound = 523. Everything else the keypad emits is already the
 * standard Linux keycode (103/108/105/106 = arrows, 28 = ENTER, 139 = MENU,
 * 231 = SEND, 158 = BACK). 48 is the right soft key — matrix-keypad.kl maps
 * it to SOFT_RIGHT, the Shortcuts-bar trigger — so it must pass through
 * untouched in mouse mode; drag toggles on DEL (138) instead. */
#define STAR_CODE 522
#define POUND_CODE 523
#define DEL_CODE 138

/* Event action return codes */
typedef enum
{
  CHANGED_TO_MOUSE = -2,
  MUTE_EVENT = 0,
  PASS_THRU_EVENT = 1,
  CHANGED_EVENT = 2
} event_action_t;

typedef enum
{
  MODE_PASSIVE = 0,
  MODE_GAMEPAD = 1,
  MODE_LANDSCAPE_CURSOR = 2,
  MODE_MOUSE = 3
} input_mode_t;

typedef struct
{
  struct libevdev *dev;
  struct libevdev_uinput *uidev;
  int stick_lx, stick_ly, stick_rx, stick_ry;
  int dpad_held;   /* bitmask of D-pad keys down (DPAD_*_BIT) */
  int numpad_held; /* bitmask of numpad stick keys down */
  long long back_hold_since;
  long long right_hold_since;
  int landscape_cursor;
} gamepad_t;

/* Device structure */
typedef struct dev_st
{
  int fd;
  const char *name;
  struct libevdev *evdev;
  struct libevdev_uinput *uidev;
  int dead; /* read() failed with ENODEV/EIO: unlink from the list */
  struct dev_st *next;
} device_t;

/* Mouse configuration structure */
typedef struct
{
  int enabled;
  long long softhold_since;  /* soft key pressed at ms (0 = not held) */
  int held_code;             /* active: keycode held for auto-repeat (0 = none) */
  long long next_repeat_ms;  /* active: when the next repeat step is due */
  int speed;
  int drag_mode;
  struct libevdev *dev;
  struct libevdev_uinput *uidev;
} mouse_t;

/* Global state */
typedef struct
{
  device_t *devices;
  mouse_t mouse;
  gamepad_t gamepad;
  input_mode_t mode;
  int cfg_manual_gp;
  int cfg_landscape_auto;
  char cfg_block_cursor_pkgs[512];
  int landscape_cursor_override;
  long long last_landscape_poll;
  FILE *log_fp;
  volatile sig_atomic_t running;
} app_state_t;

#define CHANGED_TO_GAMEPAD -3

/* Device list */
static const char *supported_devices[] = {
    "mtk-kpd",        /* volume keys (114/115) — activation gesture lives here */
    "matrix-keypad",  /* the Flip2 keypad */
    NULL};

/* Global application state */
static app_state_t app_state = {0};

/* Function prototypes */
/* Mouse handling */
static int mouse_init(void);
static void mouse_cleanup(void);
static void mouse_activate(void);
static void mouse_deactivate(void);
static void repeat_stop(void);
static void fire_repeat(void);
static int mouse_handle_event(device_t *dev, struct input_event *ev);

/* Device handling */
static int devices_find_and_init(void);
static void devices_cleanup(void);
static int devices_reap(void);

/* Event handling */
static long long now_ms(void);
static int handle_input_event(device_t *dev, struct input_event *ev);

/* Logging */
static void log_init(void);
static void log_close(void);
static void log_message(const char *format, ...);
static void log_perror(const char *prefix);
static void log_event(const char *prefix, struct input_event *ev);

/* Signal handling */
static void signal_handler(int sig);
static void setup_signal_handlers(void);

/* Main loop */
static int run_event_loop(void);

/* --- Logging Functions --- */

static void log_init(void)
{
  if (!ENABLE_LOG)
    return; /* Logging disabled */

  app_state.log_fp = fopen(LOG_FILE, "a");
  if (!app_state.log_fp)
  {
    perror("Failed to open log file");
    return; /* Continue without logging */
  }
  fprintf(app_state.log_fp, "\n----- FlipMouse Log initialized -----");
  fflush(app_state.log_fp);
}

static void log_close(void)
{
  if (app_state.log_fp)
  {
    fclose(app_state.log_fp);
    app_state.log_fp = NULL;
  }
}

static void log_perror(const char *prefix)
{
  if (!ENABLE_LOG)
    return;
  int err = errno; /* Save errno because log_message might change it */
  log_message("%s: %s (errno=%d)", prefix, strerror(err), err);
}

static void log_message(const char *format, ...)
{
  if (!ENABLE_LOG)
    return;

  va_list args;
  char log_buffer[256];

  va_start(args, format);
  vsnprintf(log_buffer, sizeof(log_buffer), format, args);
  va_end(args);

  if (app_state.log_fp)
  {
    fprintf(app_state.log_fp, "%s\n", log_buffer);
    fflush(app_state.log_fp); /* Ensure the log is written immediately */
  }

#ifdef DEBUG
  printf("%s\n", log_buffer);
#endif
}

static void log_event(const char *prefix, struct input_event *ev)
{
  if (!ENABLE_LOG || ev->type == EV_SYN)
    return;

  char event_info[256];
  snprintf(event_info, sizeof(event_info),
           "%s [%s] Event: time %ld.%06ld, type %d (%s), code %d (%s), value %d",
           prefix,
           app_state.mouse.enabled ? "GRAB" : "PASS",
           ev->input_event_sec,
           ev->input_event_usec,
           ev->type,
           libevdev_event_type_get_name(ev->type),
           ev->code,
           libevdev_event_code_get_name(ev->type, ev->code),
           ev->value);

  log_message("%s", event_info);
}

/* --- Mouse Functions --- */

static void mouse_save_speed(int speed)
{
  FILE *f = fopen(SPEED_FILE, "w");
  if (!f)
    return;
  fprintf(f, "%d\n", speed);
  fclose(f);
}

static int mouse_load_speed(void)
{
  FILE *f = fopen(SPEED_FILE, "r");
  int v = FLIPMOUSE_DEFAULT_SPEED;
  if (!f)
    return v;
  if (fscanf(f, "%d", &v) != 1)
    v = FLIPMOUSE_DEFAULT_SPEED;
  fclose(f);
  if (v < MIN_MOUSE_SPEED)
    v = MIN_MOUSE_SPEED;
  return v;
}

static int mouse_init(void)
{
  app_state.mouse.dev = libevdev_new();
  log_message("Creating virtual mouse device");

  if (!app_state.mouse.dev)
  {
    log_message("ERROR: Failed to create virtual mouse device");
    return -1;
  }

  libevdev_set_name(app_state.mouse.dev, "FlipMouse Virtual Mouse");

  /* Configure mouse capabilities */
  libevdev_enable_event_code(app_state.mouse.dev, EV_REL, REL_X, NULL);
  libevdev_enable_event_code(app_state.mouse.dev, EV_REL, REL_Y, NULL);
  libevdev_enable_event_code(app_state.mouse.dev, EV_REL, REL_WHEEL, NULL);
  libevdev_enable_event_code(app_state.mouse.dev, EV_REL, REL_HWHEEL, NULL);
  libevdev_enable_event_code(app_state.mouse.dev, EV_KEY, BTN_LEFT, NULL);
  libevdev_enable_event_code(app_state.mouse.dev, EV_KEY, BTN_RIGHT, NULL);

  if (libevdev_uinput_create_from_device(app_state.mouse.dev,
                                         LIBEVDEV_UINPUT_OPEN_MANAGED,
                                         &app_state.mouse.uidev) < 0)
  {
    log_message("ERROR: Failed to create virtual mouse uinput device");
    libevdev_free(app_state.mouse.dev);
    app_state.mouse.dev = NULL;
    return -1;
  }
  /* Initialize mouse parameters */
  app_state.mouse.enabled = 0;
  app_state.mouse.softhold_since = 0;
  app_state.mouse.speed = mouse_load_speed();
  app_state.mouse.drag_mode = 0;
  app_state.mouse.held_code = 0;
  app_state.mouse.next_repeat_ms = 0;

  log_message("Virtual mouse initialized (speed=%d; passive — hold upper-left soft key 1s and release to activate)",
              app_state.mouse.speed);
  return 0;
}

static void mouse_cleanup(void)
{
  if (app_state.mouse.uidev)
  {
    libevdev_uinput_destroy(app_state.mouse.uidev);
    app_state.mouse.uidev = NULL;
  }

  if (app_state.mouse.dev)
  {
    libevdev_free(app_state.mouse.dev);
    app_state.mouse.dev = NULL;
  }

  log_message("Virtual mouse resources released");
}

/* --- Activation (local patch, replaces upstream's star-tap toggle) --- */
static long long now_ms(void);
static void sync_apply_mode(void);

static long long now_ms(void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
}

static int is_grabbed_mode(input_mode_t m)
{
  return m == MODE_GAMEPAD || m == MODE_LANDSCAPE_CURSOR || m == MODE_MOUSE;
}

static void devices_set_grab(int on)
{
  for (device_t *d = app_state.devices; d; d = d->next)
  {
    if (ioctl(d->fd, EVIOCGRAB, on ? 1 : 0) < 0)
      log_message("WARNING: grab(%d) failed for %s", on, d->name);
  }
}

static void cfg_load_gamepad(void)
{
  FILE *f = fopen(GAMEPAD_CONFIG, "r");
  app_state.cfg_manual_gp = 0;
  app_state.cfg_landscape_auto = 1;
  app_state.cfg_block_cursor_pkgs[0] = '\0';
  if (!f)
    return;
  char line[256];
  while (fgets(line, sizeof line, f))
  {
    if (strncmp(line, "enabled=", 8) == 0)
      app_state.cfg_manual_gp = (line[8] == '1');
    else if (strncmp(line, "landscape_auto=", 15) == 0)
      app_state.cfg_landscape_auto = (line[15] == '1');
    else if (strncmp(line, "block_cursor_toggle_packages=", 29) == 0)
    {
      char *val = line + 29;
      size_t n = strcspn(val, "\r\n");
      if (n >= sizeof app_state.cfg_block_cursor_pkgs)
        n = sizeof app_state.cfg_block_cursor_pkgs - 1;
      memcpy(app_state.cfg_block_cursor_pkgs, val, n);
      app_state.cfg_block_cursor_pkgs[n] = '\0';
    }
  }
  fclose(f);
}

/* `dumpsys window displays` costs 100-160 ms on this phone and used to run
 * twice per poll (mode_wanted + sync_apply_mode), stalling the whole event loop
 * for up to 300 ms every POLL_LANDSCAPE_MS and delaying key delivery with it.
 * Probe once per cycle; everything else reads the cache. A rotation change is
 * still picked up within one poll interval. */
static int landscape_cached;

static int landscape_probe(void)
{
  FILE *p = popen("dumpsys window displays 2>/dev/null", "r");
  if (!p)
    return 0;
  char buf[1024];
  /* This TCL build never prints AOSP's "rotation=1"/"rotation=3" -- it prints
   * "mCurrentRotation=ROTATION_90" plus a "cur=WxH" size. Match both forms and
   * fall back to width>height. (mLandscapeRotation is a constant on this build,
   * so it must never be matched.) */
  int rot_land = 0;
  int size_land = -1;
  while (fgets(buf, sizeof buf, p))
  {
    if (strstr(buf, "mCurrentRotation=ROTATION_90") ||
        strstr(buf, "mCurrentRotation=ROTATION_270") ||
        strstr(buf, "rotation=1") || strstr(buf, "rotation=3"))
      rot_land = 1;
    const char *cur = strstr(buf, "cur=");
    if (cur)
    {
      int w = 0, h = 0;
      if (sscanf(cur + 4, "%dx%d", &w, &h) == 2 && w > 0 && h > 0 && w != h)
        size_land = (w > h);
    }
  }
  pclose(p);
  return rot_land || size_land == 1;
}

/* Everything else reads the cache, which the poll block refreshes once per
 * cycle. Calling the popen() probe from mode_wanted() *and* sync_apply_mode()
 * meant two 100-160 ms stalls per poll, right in the key path. */
static int landscape_now(void)
{
  return landscape_cached;
}

static int focus_line_has_blocklisted_pkg(const char *buf)
{
  const char *pkg = app_state.cfg_block_cursor_pkgs;
  for (;;)
  {
    const char *comma = strchr(pkg, ',');
    size_t len = comma ? (size_t)(comma - pkg) : strlen(pkg);
    if (len > 0 && len < 200)
    {
      char name[200];
      memcpy(name, pkg, len);
      name[len] = '\0';
      if (strstr(buf, name))
        return 1;
    }
    if (!comma)
      break;
    pkg = comma + 1;
  }
  return 0;
}

static int foreground_in_blocklist(void)
{
  if (!app_state.cfg_block_cursor_pkgs[0])
    return 0;
  const char *cmds[] = {
      "dumpsys activity activities 2>/dev/null | grep ResumedActivity | head -1",
      "dumpsys window 2>/dev/null | grep mCurrentFocus | grep -v 'mCurrentFocus=null' | head -1",
      NULL};
  for (int i = 0; cmds[i]; i++)
  {
    FILE *p = popen(cmds[i], "r");
    if (!p)
      continue;
    char buf[512];
    int hit = 0;
    if (fgets(buf, sizeof buf, p) && focus_line_has_blocklisted_pkg(buf))
      hit = 1;
    pclose(p);
    if (hit)
      return 1;
  }
  return 0;
}

static int cursor_hold_blocked(void)
{
  cfg_load_gamepad();
  return foreground_in_blocklist();
}

static input_mode_t mode_wanted(void)
{
  cfg_load_gamepad();
  if (app_state.mouse.enabled)
    return MODE_MOUSE;
  if (app_state.landscape_cursor_override)
    return MODE_LANDSCAPE_CURSOR;
  if (app_state.cfg_manual_gp || (app_state.cfg_landscape_auto && landscape_now()))
    return MODE_GAMEPAD;
  return MODE_PASSIVE;
}

static void pass_through_matrix(int code, int value)
{
  for (device_t *d = app_state.devices; d; d = d->next)
  {
    if (!d->uidev || strcmp(d->name, "matrix-keypad") != 0)
      continue;
    libevdev_uinput_write_event(d->uidev, EV_KEY, code, value);
    libevdev_uinput_write_event(d->uidev, EV_SYN, SYN_REPORT, 0);
    break;
  }
}

static void gp_stick_apply(void)
{
  if (!app_state.gamepad.uidev)
    return;
  libevdev_uinput_write_event(app_state.gamepad.uidev, EV_ABS, ABS_X, app_state.gamepad.stick_lx);
  libevdev_uinput_write_event(app_state.gamepad.uidev, EV_ABS, ABS_Y, app_state.gamepad.stick_ly);
  libevdev_uinput_write_event(app_state.gamepad.uidev, EV_ABS, ABS_RX, app_state.gamepad.stick_rx);
  libevdev_uinput_write_event(app_state.gamepad.uidev, EV_ABS, ABS_RY, app_state.gamepad.stick_ry);
  libevdev_uinput_write_event(app_state.gamepad.uidev, EV_SYN, SYN_REPORT, 0);
}

static void gp_emit_key(int code, int value)
{
  if (!app_state.gamepad.uidev)
    return;
  libevdev_uinput_write_event(app_state.gamepad.uidev, EV_KEY, code, value);
  libevdev_uinput_write_event(app_state.gamepad.uidev, EV_SYN, SYN_REPORT, 0);
}

static int gamepad_init(void)
{
  struct input_absinfo absinfo = {.minimum = AXIS_GP_MIN, .maximum = AXIS_GP_MAX, .fuzz = 0, .flat = 0};
  app_state.gamepad.dev = libevdev_new();
  if (!app_state.gamepad.dev)
    return -1;
  libevdev_set_name(app_state.gamepad.dev, "Flip2 Gamepad");
  libevdev_enable_event_type(app_state.gamepad.dev, EV_KEY);
  libevdev_enable_event_type(app_state.gamepad.dev, EV_ABS);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_KEY, BTN_GAMEPAD, NULL);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_KEY, BTN_SOUTH, NULL);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_KEY, BTN_EAST, NULL);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_KEY, BTN_NORTH, NULL);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_KEY, BTN_TL, NULL);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_KEY, BTN_TR, NULL);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_KEY, BTN_TL2, NULL);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_KEY, BTN_TR2, NULL);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_KEY, BTN_START, NULL);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_KEY, BTN_THUMBL, NULL);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_ABS, ABS_X, &absinfo);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_ABS, ABS_Y, &absinfo);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_ABS, ABS_RX, &absinfo);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_ABS, ABS_RY, &absinfo);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_ABS, ABS_HAT0X, &absinfo);
  libevdev_enable_event_code(app_state.gamepad.dev, EV_ABS, ABS_HAT0Y, &absinfo);
  if (libevdev_uinput_create_from_device(app_state.gamepad.dev, LIBEVDEV_UINPUT_OPEN_MANAGED,
                                         &app_state.gamepad.uidev) < 0) {
    libevdev_free(app_state.gamepad.dev);
    app_state.gamepad.dev = NULL;
    return -1;
  }
  return 0;
}

static void gamepad_cleanup(void)
{
  if (app_state.gamepad.uidev)
    libevdev_uinput_destroy(app_state.gamepad.uidev);
  if (app_state.gamepad.dev)
    libevdev_free(app_state.gamepad.dev);
  app_state.gamepad.uidev = NULL;
  app_state.gamepad.dev = NULL;
}

/* Push the currently-held direction set out to the virtual gamepad.
 *
 * Both crosses feed the SAME axes. Astro Loop's InputRouter.onMotion reads
 * AXIS_X/AXIS_Y (left stick) and AXIS_HAT_X/AXIS_HAT_Y; it never reads
 * AXIS_RX/AXIS_RY, so the numpad's private right-stick output was invisible
 * in-game and every numpad direction did nothing. The two clusters are both a
 * cross in the same physical orientation, so they share one direction set --
 * the numpad simply adds diagonals, which the D-pad cannot report.
 *
 * HAT axes share the stick's -32767..32767 range, so they must be written at
 * full scale, not +-1. Android normalises the raw value, and a raw 1 becomes
 * ~0.00003: far under the game's 0.5 hat threshold and under the deadzone
 * Android needs to synthesise DPAD key events, i.e. the D-pad did nothing.
 *
 * The landscape cross is a true 90-degree rotation: Up->left, left->down,
 * down->right, right->up. */
static void gp_dirs_apply(void)
{
  int d = app_state.gamepad.dpad_held;
  int n = app_state.gamepad.numpad_held;
  int up = !!(d & DPAD_BIT_UP), down = !!(d & DPAD_BIT_DOWN);
  int left = !!(d & DPAD_BIT_LEFT), right = !!(d & DPAD_BIT_RIGHT);
  int hx = 0, hy = 0;

  /* Phone keypad layout, not a PC numpad: 1-2-3 is the TOP row and 7-8-9 the
   * bottom, so 2 points up and 8 points down. 1/3/7/9 are diagonals, so each
   * sets two directions: a direction stays on until no held numpad key still
   * wants it. */
  if (n & (NPAD_BIT_2 | NPAD_BIT_1 | NPAD_BIT_3))
    up = 1;
  if (n & (NPAD_BIT_8 | NPAD_BIT_7 | NPAD_BIT_9))
    down = 1;
  if (n & (NPAD_BIT_4 | NPAD_BIT_1 | NPAD_BIT_7))
    left = 1;
  if (n & (NPAD_BIT_6 | NPAD_BIT_3 | NPAD_BIT_9))
    right = 1;

  if (up)
    hx -= STICK_EDGE;
  if (down)
    hx += STICK_EDGE;
  if (left)
    hy += STICK_EDGE;
  if (right)
    hy -= STICK_EDGE;

  app_state.gamepad.stick_lx = hx;
  app_state.gamepad.stick_ly = hy;
  gp_stick_apply();
  libevdev_uinput_write_event(app_state.gamepad.uidev, EV_ABS, ABS_HAT0X, hx);
  libevdev_uinput_write_event(app_state.gamepad.uidev, EV_ABS, ABS_HAT0Y, hy);
  libevdev_uinput_write_event(app_state.gamepad.uidev, EV_SYN, SYN_REPORT, 0);
}

/* Track each direction as its own key. Modelling the cross as a single value
 * (the old behaviour) meant the newest key overwrote the whole axis pair, so
 * pressing a second direction cancelled the first and releasing either one
 * cleared both. */
static void gp_dpad(int k, int v)
{
  int bit = 0;
  switch (k) {
  case KEY_UP: bit = DPAD_BIT_UP; break;
  case KEY_DOWN: bit = DPAD_BIT_DOWN; break;
  case KEY_LEFT: bit = DPAD_BIT_LEFT; break;
  case KEY_RIGHT: bit = DPAD_BIT_RIGHT; break;
  default: return;
  }
  if (v)
    app_state.gamepad.dpad_held |= bit;
  else
    app_state.gamepad.dpad_held &= ~bit;
  gp_dirs_apply();
}

static void gp_numpad(int k, int v)
{
  int bit = 0;
  switch (k) {
  case KEY_1: bit = NPAD_BIT_1; break;
  case KEY_2: bit = NPAD_BIT_2; break;
  case KEY_3: bit = NPAD_BIT_3; break;
  case KEY_4: bit = NPAD_BIT_4; break;
  case KEY_5: bit = NPAD_BIT_5; break;
  case KEY_6: bit = NPAD_BIT_6; break;
  case KEY_7: bit = NPAD_BIT_7; break;
  case KEY_8: bit = NPAD_BIT_8; break;
  case KEY_9: bit = NPAD_BIT_9; break;
  default: return;
  }
  if (v)
    app_state.gamepad.numpad_held |= bit;
  else
    app_state.gamepad.numpad_held &= ~bit;
  gp_dirs_apply();
}

static int gamepad_handle_key(int code, int value)
{
  switch (code) {
  case KEY_UP: case KEY_DOWN: case KEY_LEFT: case KEY_RIGHT:
    gp_dpad(code, value);
    return MUTE_EVENT;
  case KEY_1: case KEY_2: case KEY_3: case KEY_4: case KEY_5:
  case KEY_6: case KEY_7: case KEY_8: case KEY_9:
    gp_numpad(code, value);
    return MUTE_EVENT;
  case KEY_ENTER: gp_emit_key(BTN_THUMBL, value); return MUTE_EVENT;
  case POUND_CODE: gp_emit_key(BTN_SOUTH, value); return MUTE_EVENT;
  case KEY_0: gp_emit_key(BTN_EAST, value); return MUTE_EVENT;
  case STAR_CODE: gp_emit_key(BTN_NORTH, value); return MUTE_EVENT;
  case SOFTKEY_CODE: gp_emit_key(BTN_TL, value); return MUTE_EVENT;
  case MESSENGER_CODE: gp_emit_key(BTN_TR2, value); return MUTE_EVENT;
  case KEY_VOLUMEUP: gp_emit_key(BTN_TL2, value); return MUTE_EVENT;
  case KEY_VOLUMEDOWN: gp_emit_key(BTN_TR2, value); return MUTE_EVENT;
  case KEY_BACK:
    if (value == 1) {
      app_state.gamepad.back_hold_since = now_ms();
      gp_emit_key(BTN_START, 1);
      return MUTE_EVENT;
    }
    {
      long long held = app_state.gamepad.back_hold_since ? now_ms() - app_state.gamepad.back_hold_since : 0;
      app_state.gamepad.back_hold_since = 0;
      gp_emit_key(BTN_START, 0);
      if (held >= BACK_REAL_HOLD_MS) {
        pass_through_matrix(KEY_BACK, 1);
        pass_through_matrix(KEY_BACK, 0);
      }
      return MUTE_EVENT;
    }
  default:
    return MUTE_EVENT;
  }
}

static void sync_apply_mode(void)
{
  if (!landscape_now())
    app_state.landscape_cursor_override = 0;
  input_mode_t want = mode_wanted();
  if (want != app_state.mode) {
    app_state.mode = want;
    app_state.gamepad.landscape_cursor = (want == MODE_LANDSCAPE_CURSOR);
    app_state.mouse.enabled = (want == MODE_MOUSE || want == MODE_LANDSCAPE_CURSOR);
    /* Keys held across a mode change never get a release we see, so drop the
     * tracked set here or the new mode starts with directions stuck down. */
    app_state.gamepad.dpad_held = 0;
    app_state.gamepad.numpad_held = 0;
    app_state.gamepad.stick_lx = app_state.gamepad.stick_ly = 0;
    app_state.gamepad.stick_rx = app_state.gamepad.stick_ry = 0;
    devices_set_grab(is_grabbed_mode(want) ? 1 : 0);
    gp_stick_apply();
    log_message("mode -> %d", (int)want);
  }
}

/* Take over: grab every monitored keypad so native delivery stops and we
 * decide where each event goes. */
static void mouse_activate(void)
{
  app_state.mouse.enabled = 1;
  app_state.mouse.softhold_since = 0;
  app_state.mode = MODE_MOUSE;
  app_state.landscape_cursor_override = 0;
  repeat_stop();
  devices_set_grab(1);
  log_message("Mouse mode enabled (keypads grabbed)");
}

/* Back to passive: release the keypads so every key reaches the system
 * natively again (the IME keeps its star key). */
static void mouse_deactivate(void)
{
  repeat_stop();
  app_state.mouse.enabled = 0;
  app_state.landscape_cursor_override = 0;
  sync_apply_mode();
  log_message("Mouse mode disabled");
}

/* --- Held-key auto-repeat (local patch) --- */
static void repeat_stop(void)
{
  app_state.mouse.held_code = 0;
  app_state.mouse.next_repeat_ms = 0;
}

/* Emit one movement/wheel step for the held key and reschedule. */
static void fire_repeat(void)
{
  int code = app_state.mouse.held_code;
  int rel_code = 0, rel_value = 0;
  long long interval = REPEAT_INTERVAL_MS;

  if (!app_state.mouse.enabled || !code)
    return;
  if (app_state.gamepad.landscape_cursor)
  {
    switch (code)
    {
    case KEY_UP: rel_code = REL_X; rel_value = -app_state.mouse.speed; break;
    case KEY_DOWN: rel_code = REL_X; rel_value = app_state.mouse.speed; break;
    case KEY_LEFT: rel_code = REL_Y; rel_value = -app_state.mouse.speed; break;
    case KEY_RIGHT: rel_code = REL_Y; rel_value = app_state.mouse.speed; break;
    default: break;
    }
    if (rel_code)
    {
      libevdev_uinput_write_event(app_state.mouse.uidev, EV_REL, rel_code, rel_value);
      libevdev_uinput_write_event(app_state.mouse.uidev, EV_SYN, SYN_REPORT, 0);
      app_state.mouse.next_repeat_ms = now_ms() + interval;
      return;
    }
  }
  switch (code)
  {
  case KEY_UP: rel_code = REL_Y; rel_value = -app_state.mouse.speed; break;
  case KEY_DOWN: rel_code = REL_Y; rel_value = app_state.mouse.speed; break;
  case KEY_LEFT: rel_code = REL_X; rel_value = -app_state.mouse.speed; break;
  case KEY_RIGHT: rel_code = REL_X; rel_value = app_state.mouse.speed; break;
  case KEY_MENU: rel_code = REL_WHEEL; rel_value = 1; interval = WHEEL_REPEAT_INTERVAL_MS; break;
  case KEY_SEND: rel_code = REL_WHEEL; rel_value = -1; interval = WHEEL_REPEAT_INTERVAL_MS; break;
  default: repeat_stop(); return;
  }
  libevdev_uinput_write_event(app_state.mouse.uidev, EV_REL, rel_code, rel_value);
  libevdev_uinput_write_event(app_state.mouse.uidev, EV_SYN, SYN_REPORT, 0);
  app_state.mouse.next_repeat_ms = now_ms() + interval;
  log_message("repeat step code=%d", code);
}

static int mouse_handle_event(device_t *dev, struct input_event *ev)
{
  int keycode = ev->code;

  /* Process according to keycode */
  switch (keycode)
  {
  case KEY_VOLUMEUP:
    if (ev->value == 1)
    { /* Key press */
      app_state.mouse.speed++;
      mouse_save_speed(app_state.mouse.speed);
      log_message("Mouse speed increased to %d", app_state.mouse.speed);
    }
    return MUTE_EVENT;

  case KEY_VOLUMEDOWN:
    if (ev->value == 1)
    { /* Key press */
      app_state.mouse.speed--;
      if (app_state.mouse.speed < MIN_MOUSE_SPEED)
        app_state.mouse.speed = MIN_MOUSE_SPEED;
      mouse_save_speed(app_state.mouse.speed);
      log_message("Mouse speed decreased to %d", app_state.mouse.speed);
    }
    return MUTE_EVENT;

  case KEY_ENTER:
    log_message("Mouse left click");
    ev->type = EV_KEY;
    ev->code = BTN_LEFT;
    return CHANGED_TO_MOUSE;

  case DEL_CODE: /* keypad DEL (138) toggles drag — formerly raw 48, which is
                  * the right soft key (Shortcuts trigger) and must pass
                  * through so launcher shortcuts work in mouse mode */
    if (ev->value == 1)
    { /* Key press */
      app_state.mouse.drag_mode = !app_state.mouse.drag_mode;

      log_message("Drag mode %s", app_state.mouse.drag_mode ? "enabled" : "disabled");
      ev->type = EV_KEY;
      ev->code = BTN_LEFT;
      ev->value = app_state.mouse.drag_mode ? 1 : 0; /* 1=press, 0=release */

      return CHANGED_TO_MOUSE;
    }
    return MUTE_EVENT; /* drag toggles on press; swallow the release */

  case KEY_UP:
  case KEY_DOWN:
  case KEY_LEFT:
  case KEY_RIGHT:
  case KEY_MENU: /* scroll up */
  case KEY_SEND: /* scroll down */
    /* Local patch: press = one step now + synthesized auto-repeat until
     * release; release is swallowed (the press already emitted the step).
     * Wheel keys repeat on the slowed wheel cadence. */
    if (ev->value == 1)
    {
      app_state.mouse.held_code = keycode;
      app_state.mouse.next_repeat_ms =
          now_ms() + ((keycode == KEY_MENU || keycode == KEY_SEND)
                          ? WHEEL_REPEAT_INTERVAL_MS
                          : REPEAT_DELAY_MS);
    }
    else
    {
      if (app_state.mouse.held_code == keycode)
        repeat_stop();
      return MUTE_EVENT;
    }
    ev->type = EV_REL;
    if (app_state.gamepad.landscape_cursor &&
        (keycode == KEY_UP || keycode == KEY_DOWN || keycode == KEY_LEFT ||
         keycode == KEY_RIGHT))
    {
      if (keycode == KEY_UP || keycode == KEY_DOWN)
      {
        ev->code = REL_X;
        ev->value = (keycode == KEY_UP) ? -app_state.mouse.speed
                                        : app_state.mouse.speed;
      }
      else
      {
        ev->code = REL_Y;
        ev->value = (keycode == KEY_LEFT) ? -app_state.mouse.speed
                                          : app_state.mouse.speed;
      }
    }
    else if (keycode == KEY_UP || keycode == KEY_DOWN)
    {
      ev->code = REL_Y;
      ev->value = (keycode == KEY_UP) ? -app_state.mouse.speed
                                      : app_state.mouse.speed;
    }
    else if (keycode == KEY_LEFT || keycode == KEY_RIGHT)
    {
      ev->code = REL_X;
      ev->value = (keycode == KEY_LEFT) ? -app_state.mouse.speed
                                        : app_state.mouse.speed;
    }
    else /* wheel */
    {
      ev->code = REL_WHEEL;
      ev->value = (keycode == KEY_MENU) ? 1 : -1;
    }
    return CHANGED_TO_MOUSE;

  default:
    return PASS_THRU_EVENT;
  }

  return PASS_THRU_EVENT;
}

/* --- Device Management Functions --- */

/* uinput nodes (including the pass-through clones this daemon creates for each
 * real keypad) live under /sys/devices/virtual/input and inherit the *real*
 * device's name, so matching on name alone re-adopts our own clones on every
 * restart. A clone whose creating process died stays select()-readable forever
 * without ever producing an event, which pins the loop in a read-error spin and
 * starves the real keypads — the "buttons sometimes don't fire" bug. Resolve the
 * node's sysfs backing and skip anything virtual. */
/* The fake keypad used for on-device testing is itself a uinput device, so the
 * virtual guard would hide it and the documented rig would silently stop
 * working. FLIP2_ARCADE_TEST_INPUT names *that one node* (e.g.
 * /dev/input/event5) and is honoured only for that exact path — a blanket
 * "let virtual through" switch made the daemon adopt its own pass-through
 * clones and grab itself. Only a hand-started test daemon sets it;
 * service.sh does not. */
static int test_input_allowed(const char *dev_path)
{
  const char *allow = getenv("FLIP2_ARCADE_TEST_INPUT");
  return allow && allow[0] && strcmp(allow, dev_path) == 0;
}

static int node_is_virtual(const char *dev_path)
{
  const char *base = strrchr(dev_path, '/');
  base = base ? base + 1 : dev_path;

  if (test_input_allowed(dev_path))
    return 0;

  char link[PATH_MAX];
  char target[PATH_MAX];
  snprintf(link, sizeof(link), "/sys/class/input/%s/device", base);
  if (!realpath(link, target))
    return 0; /* cannot resolve -> treat as real rather than lose the keypad */
  return strstr(target, "/devices/virtual/") != NULL;
}

static int device_name_present(const char *name)
{
  for (device_t *d = app_state.devices; d; d = d->next)
  {
    if (strcmp(d->name, name) == 0)
      return 1;
  }
  return 0;
}

static int devices_find_and_init(void)
{
  DIR *dir;
  struct dirent *file;
  int result = -1;

  dir = opendir(DEV_INPUT);
  if (!dir)
  {
    log_message("ERROR: Failed to open directory %s", DEV_INPUT);
    log_perror("opendir");
    return -1;
  }

  while ((file = readdir(dir)) != NULL)
  {
    char file_path[256];
    int found = 0;

    /* Skip non-character devices */
    if (file->d_type != DT_CHR)
      continue;

    snprintf(file_path, sizeof(file_path), "%s/%s", DEV_INPUT, file->d_name);
    log_message("Checking device %s", file_path);

    /* Never adopt a uinput clone (ours or anyone else's). */
    if (node_is_virtual(file_path))
    {
      log_message("Skipping virtual input node %s", file_path);
      continue;
    }

    /* O_NONBLOCK so a device that stops producing events can never wedge the
     * loop in a blocking read. */
    int fd = open(file_path, O_RDONLY | O_NONBLOCK);
    if (fd < 0)
    {
      log_message("ERROR: Failed to open device file %s", file_path);
      log_perror("open");
      continue;
    }

    struct libevdev *evdev = NULL;
    if (libevdev_new_from_fd(fd, &evdev) < 0)
    {
      log_message("ERROR: Failed to create libevdev from fd %d", fd);
      close(fd);
      continue;
    }

    /* Check if this is a device we're interested in */
    for (int i = 0; supported_devices[i]; i++)
    {
      if (strcmp(libevdev_get_name(evdev), supported_devices[i]) == 0)
      {
        /* One node per name: a second same-named node would double-deliver
         * every key and re-grab itself. The listed test node is exempt, because
         * the fake keypad deliberately impersonates matrix-keypad. */
        if (!test_input_allowed(file_path) && device_name_present(libevdev_get_name(evdev)))
        {
          log_message("Skipping duplicate %s", libevdev_get_name(evdev));
          break;
        }

        log_message("Found supported device: %s", libevdev_get_name(evdev));

        /* Create device structure */
        device_t *dev = malloc(sizeof(device_t));
        if (!dev)
        {
          log_message("ERROR: Failed to allocate memory for device");
          libevdev_free(evdev);
          close(fd);
          continue;
        }

        /* Initialize device — NO grab (local patch): we stay a passive
         * observer until mouse mode is activated. */
        dev->fd = fd;
        dev->name = libevdev_get_name(evdev);
        dev->evdev = evdev;
        dev->next = NULL;

        /* Create uinput device (clone used to re-inject pass-through keys
         * while the real device is grabbed in mouse mode) */
        if (libevdev_uinput_create_from_device(dev->evdev,
                                               LIBEVDEV_UINPUT_OPEN_MANAGED,
                                               &(dev->uidev)) < 0)
        {
          log_message("ERROR: Failed to create uinput device");
          libevdev_free(evdev);
          close(fd);
          free(dev);
          continue;
        }

        log_message("Successfully attached device: %s", dev->name);

        /* Add to device list */
        if (!app_state.devices)
        {
          app_state.devices = dev;
        }
        else
        {
          device_t *d = app_state.devices;
          while (d->next)
            d = d->next;
          d->next = dev;
        }

        found = 1;
        result = 0; /* Success */
        break;
      }
    }

    /* If not a supported device, cleanup resources */
    if (!found)
    {
      log_message("Device %s not in supported list", file_path);
      libevdev_free(evdev);
      close(fd);
    }
  }

  closedir(dir);
  return result;
}

static void devices_cleanup(void)
{
  device_t *curr = app_state.devices;

  while (curr)
  {
    device_t *next = curr->next;

    if (curr->uidev)
      libevdev_uinput_destroy(curr->uidev);

    if (curr->evdev)
      libevdev_free(curr->evdev);

    if (curr->fd >= 0)
      close(curr->fd);

    free(curr);
    curr = next;
  }

  app_state.devices = NULL;
  log_message("All input devices released");
}

/* Unlink devices whose read() failed (node removed / hot-unplugged). Returns
 * the number dropped so the caller knows to rebuild its fd_set. */
static int devices_reap(void)
{
  device_t **link = &app_state.devices;
  int dropped = 0;

  while (*link)
  {
    device_t *d = *link;
    if (!d->dead)
    {
      link = &d->next;
      continue;
    }

    *link = d->next;
    log_message("Reaping dead device %s (fd %d)", d->name, d->fd);

    /* Release any grab before tearing down, so the system sees the keypad
     * again if this was a real node. */
    ioctl(d->fd, EVIOCGRAB, 0);
    if (d->uidev)
      libevdev_uinput_destroy(d->uidev);
    if (d->evdev)
      libevdev_free(d->evdev);
    if (d->fd >= 0)
      close(d->fd);
    free(d);
    dropped++;
  }

  return dropped;
}

/* --- Event Handling Functions --- */
static int handle_input_event(device_t *dev, struct input_event *ev)
{
  if (app_state.mode == MODE_PASSIVE)
  {
    if (ev->type == EV_KEY && ev->code == SOFTKEY_CODE)
    {
      if (ev->value == 1)
        app_state.mouse.softhold_since = now_ms();
      else if (app_state.mouse.softhold_since)
      {
        long long held = now_ms() - app_state.mouse.softhold_since;
        app_state.mouse.softhold_since = 0;
        if (held >= HOLD_TOGGLE_MS && !cursor_hold_blocked())
          mouse_activate();
      }
    }
    return MUTE_EVENT;
  }

  if (ev->type == EV_MSC)
    return MUTE_EVENT;

  if (ev->type != EV_KEY)
    return PASS_THRU_EVENT;

  if (app_state.mode == MODE_GAMEPAD)
  {
    if (ev->code == SOFT_RIGHT_CODE)
    {
      /* Right soft key: a tap is R1, a hold still switches to the landscape
       * cursor. It used to be swallowed here, and gamepad_handle_key had no
       * mapping for it either, so BTN_TR was enabled on the virtual pad but
       * physically unreachable -- the "right key does nothing" report.
       * Nothing is emitted on press: we cannot know yet whether this is a tap
       * or the cursor gesture, and a speculative BTN_TR would fire an R1 hit
       * every time someone held the key to move the cursor. */
      if (ev->value == 1)
        app_state.gamepad.right_hold_since = now_ms();
      else if (app_state.gamepad.right_hold_since)
      {
        long long held = now_ms() - app_state.gamepad.right_hold_since;
        app_state.gamepad.right_hold_since = 0;
        if (held >= HOLD_TOGGLE_MS && !cursor_hold_blocked())
        {
          app_state.landscape_cursor_override = 1;
          sync_apply_mode();
          log_message("right soft hold: landscape cursor");
        }
        else
        {
          log_message("right soft tap: BTN_TR (R1)");
          gp_emit_key(BTN_TR, 1);
          gp_emit_key(BTN_TR, 0);
        }
      }
      return MUTE_EVENT;
    }
    return gamepad_handle_key(ev->code, ev->value);
  }

  if (app_state.mode == MODE_LANDSCAPE_CURSOR || app_state.mode == MODE_MOUSE)
  {
    if (ev->code == SOFTKEY_CODE)
    {
      if (ev->value == 1)
      {
        app_state.mouse.softhold_since = now_ms();
        return MUTE_EVENT;
      }
      if (app_state.mouse.softhold_since)
      {
        long long held = now_ms() - app_state.mouse.softhold_since;
        app_state.mouse.softhold_since = 0;
        if (held >= HOLD_TOGGLE_MS)
        {
          if (app_state.mode == MODE_LANDSCAPE_CURSOR)
          {
            app_state.landscape_cursor_override = 0;
            sync_apply_mode();
            return MUTE_EVENT;
          }
          mouse_deactivate();
          return MUTE_EVENT;
        }
      }
      if (app_state.mode == MODE_MOUSE)
      {
        libevdev_uinput_write_event(app_state.mouse.uidev, EV_REL, REL_WHEEL, 1);
        libevdev_uinput_write_event(app_state.mouse.uidev, EV_SYN, SYN_REPORT, 0);
      }
      return MUTE_EVENT;
    }

    if (ev->code == STAR_CODE && ev->value == 0)
    {
      if (app_state.mode == MODE_LANDSCAPE_CURSOR)
      {
        app_state.landscape_cursor_override = 0;
        sync_apply_mode();
      }
      else
        mouse_deactivate();
      return MUTE_EVENT;
    }

    if (ev->code == POUND_CODE)
      ev->code = KEY_SEND;

    return mouse_handle_event(dev, ev);
  }

  return MUTE_EVENT;
}

/* --- Signal Handling --- */

static void signal_handler(int sig)
{
  log_message("Received signal %d, shutting down", sig);
  app_state.running = 0;
}

static void setup_signal_handlers(void)
{
  /* Use simple signal() function to avoid struct sigaction issues */
  signal(SIGINT, signal_handler);
  signal(SIGTERM, signal_handler);
  signal(SIGHUP, signal_handler);
}

/* --- Main Event Loop --- */

static int run_event_loop(void)
{
  struct input_event event;
  int event_result;
  fd_set fds, rfds;
  int maxfd = 0;
  char prefix[8];

  /* Initialize file descriptor set */
  FD_ZERO(&fds);
  for (device_t *d = app_state.devices; d; d = d->next)
  {
    FD_SET(d->fd, &fds);
    if (d->fd >= maxfd)
      maxfd = d->fd + 1;
  }

  log_message("Entering main event loop");
  app_state.running = 1;

  while (app_state.running)
  {
    {
      long long now = now_ms();
      if (app_state.last_landscape_poll == 0 ||
          now - app_state.last_landscape_poll >= POLL_LANDSCAPE_MS)
      {
        /* Exactly one dumpsys per cycle: the probe fills the cache that
         * mode_wanted() and sync_apply_mode() both read. */
        landscape_cached = landscape_probe();
        sync_apply_mode();
        app_state.last_landscape_poll = now;
      }
    }

    rfds = fds;
    /* Bound select() so the loop always wakes for its own timers:
     *   - the next auto-repeat deadline, while a mouse key is held;
     *   - the next rotation poll, always.
     * Without the rotation bound, select() blocked until a key arrived, so the
     * poll only ran *after* the first event of a new orientation and that key
     * was handled under the old mode — the "first press after rotating is
     * swallowed" note. */
    {
      struct timeval tv;
      struct timeval *tvp = NULL;
      long long wait = -1;

      if (app_state.mouse.enabled && app_state.mouse.held_code)
        wait = app_state.mouse.next_repeat_ms - now_ms();

      long long poll_wait = app_state.last_landscape_poll
                                ? app_state.last_landscape_poll + POLL_LANDSCAPE_MS - now_ms()
                                : 0;
      if (poll_wait < 0)
        poll_wait = 0;
      if (wait < 0 || poll_wait < wait)
        wait = poll_wait;

      tv.tv_sec = (time_t)(wait / 1000);
      tv.tv_usec = (suseconds_t)((wait % 1000) * 1000);
      tvp = &tv;

      if (select(maxfd, &rfds, NULL, NULL, tvp) < 0)
      {
        if (errno == EINTR)
          continue; /* Interrupted by signal */

        log_message("ERROR: select() failed");
        log_perror("select");
        break;
      }
      if (tvp && app_state.mouse.held_code &&
          now_ms() >= app_state.mouse.next_repeat_ms)
      {
        /* select() hit the repeat deadline: emit one step and reschedule. */
        fire_repeat();
        continue;
      }
    }

    for (device_t *d = app_state.devices; d; d = d->next)
    {
      if (!FD_ISSET(d->fd, &rfds))
        continue;

      /* Drain the whole queue for this device. Reading a single event per
       * wakeup left the rest queued, so a burst (D-pad plus a button in quick
       * succession) was delivered a wakeup late — that was the "have to press
       * twice" feel. */
      for (;;)
      {
        ssize_t n = read(d->fd, &event, sizeof(event));
        if (n == (ssize_t)sizeof(event))
        {
          /* fall through to processing below */
        }
        else if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR))
        {
          break; /* queue drained (non-blocking fd) */
        }
        else
        {
          /* Real error (ENODEV/EIO) — the node is gone. Drop it instead of
           * re-reading it forever: a dead clone stays select()-readable, and
           * spinning on it starved the working keypads. */
          log_message("ERROR: read failed on %s (errno=%d) — dropping device",
                      d->name, errno);
          d->dead = 1;
          break;
        }

#ifdef DEBUG
        /* Only log events while active — passive mode would spam the log
         * with every normal keypress the system already received. Gamepad mode
         * grabs the keypad too, so its events exist nowhere else. */
        if (app_state.mouse.enabled || app_state.mode == MODE_GAMEPAD)
        {
          snprintf(prefix, sizeof(prefix), "<%d<", d->fd);
          log_event(prefix, &event);
        }
#endif

        /* Process event */
        event_result = handle_input_event(d, &event);

        /* Handle event based on result code */
        if (event_result > 0)
        {
          /* Forward to original device (clone) — valid while grabbed */
#ifdef DEBUG
          if (app_state.mouse.enabled || app_state.mode == MODE_GAMEPAD)
          {
            snprintf(prefix, sizeof(prefix), ">%d>", d->fd);
            log_event(prefix, &event);
          }
#endif
          libevdev_uinput_write_event(d->uidev, event.type, event.code, event.value);
          libevdev_uinput_write_event(d->uidev, EV_SYN, SYN_REPORT, 0);
        }
        else if (event_result < 0)
        {
          /* Forward to virtual mouse */
#ifdef DEBUG
          log_event(">M>", &event);
#endif
          libevdev_uinput_write_event(app_state.mouse.uidev, event.type, event.code, event.value);
          libevdev_uinput_write_event(app_state.mouse.uidev, EV_SYN, SYN_REPORT, 0);
        }
        /* event_result == 0 means mute the event */
      }
    }

    /* Unlink any device that died and rebuild the descriptor set. */
    if (devices_reap())
    {
      FD_ZERO(&fds);
      maxfd = 0;
      for (device_t *d = app_state.devices; d; d = d->next)
      {
        FD_SET(d->fd, &fds);
        if (d->fd >= maxfd)
          maxfd = d->fd + 1;
      }
    }
  }

  return 0;
}

/* --- Main Function --- */

int main(int argc, char **argv)
{
  /* Initialize logging */
  log_init();
  log_message("FlipMouse (flip2 patched build) starting up");

  /* Set up signal handlers for clean shutdown */
  setup_signal_handlers();

  /* Find and initialize input devices */
  if (devices_find_and_init() != 0)
  {
    log_message("ERROR: Failed to find any supported input devices");
    log_close();
    return 1;
  }

  if (mouse_init() != 0)
  {
    log_message("ERROR: Failed to initialize virtual mouse");
    devices_cleanup();
    log_close();
    return 1;
  }

  if (gamepad_init() != 0)
    log_message("WARNING: gamepad uinput init failed — landscape remap disabled");

  /* Prime the rotation cache before the first mode sync, or a launch into an
   * already-landscape app starts in passive until the first poll fires. */
  landscape_cached = landscape_probe();
  app_state.last_landscape_poll = now_ms();

  sync_apply_mode();

  int result = run_event_loop();

  gamepad_cleanup();
  mouse_cleanup();
  devices_cleanup();

  log_message("FlipMouse shutting down");
  log_close();

  return result;
}
