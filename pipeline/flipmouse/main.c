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
 *     down, soft-left scrolls up, soft-right toggles drag, volume = speed
 *   - a Star tap exits back to passive (grabs released, IME unaffected)
 */

// #define DEBUG 1

#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libevdev/libevdev-uinput.h>
#include <dirent.h>
#include <stdarg.h>
#include <signal.h>
#include <sys/signalfd.h>
#include <sys/time.h>
#include <time.h>

/* Configuration */
#define DEV_INPUT "/dev/input"
#define LOG_FILE "/cache/FlipMouse.log"
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
#define HOLD_TOGGLE_MS 2000

/* Non-standard kernel codes on this unit's matrix-keypad (matrix-keypad.kl):
 * star = 522, pound = 523. Everything else the keypad emits is already the
 * standard Linux keycode (103/108/105/106 = arrows, 28 = ENTER, 139 = MENU,
 * 48 = B, 231 = SEND, 158 = BACK). */
#define STAR_CODE 522
#define POUND_CODE 523

/* Event action return codes */
typedef enum
{
  CHANGED_TO_MOUSE = -2,
  MUTE_EVENT = 0,
  PASS_THRU_EVENT = 1,
  CHANGED_EVENT = 2
} event_action_t;

/* Device structure */
typedef struct dev_st
{
  int fd;
  const char *name;
  struct libevdev *evdev;
  struct libevdev_uinput *uidev;
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
  FILE *log_fp;
  volatile sig_atomic_t running;
} app_state_t;

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
  app_state.mouse.speed = 4;
  app_state.mouse.drag_mode = 0;
  app_state.mouse.held_code = 0;
  app_state.mouse.next_repeat_ms = 0;

  log_message("Virtual mouse initialized (passive — hold upper-left soft key 2s and release to activate)");
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
static long long now_ms(void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
}

/* Take over: grab every monitored keypad so native delivery stops and we
 * decide where each event goes. */
static void mouse_activate(void)
{
  device_t *d;
  app_state.mouse.enabled = 1;
  app_state.mouse.softhold_since = 0;
  repeat_stop();
  for (d = app_state.devices; d; d = d->next)
  {
    if (ioctl(d->fd, EVIOCGRAB, 1) < 0)
      log_message("WARNING: grab failed for %s", d->name);
  }
  log_message("Mouse mode enabled (keypads grabbed)");
}

/* Back to passive: release the keypads so every key reaches the system
 * natively again (the IME keeps its star key). */
static void mouse_deactivate(void)
{
  device_t *d;
  repeat_stop();
  app_state.mouse.enabled = 0;
  for (d = app_state.devices; d; d = d->next)
    ioctl(d->fd, EVIOCGRAB, 0);
  log_message("Mouse mode disabled (passive observer)");
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
      log_message("Mouse speed increased to %d", app_state.mouse.speed);
    }
    return MUTE_EVENT;

  case KEY_VOLUMEDOWN:
    if (ev->value == 1)
    { /* Key press */
      app_state.mouse.speed--;
      if (app_state.mouse.speed < MIN_MOUSE_SPEED)
        app_state.mouse.speed = MIN_MOUSE_SPEED;
      log_message("Mouse speed decreased to %d", app_state.mouse.speed);
    }
    return MUTE_EVENT;

  case KEY_ENTER:
    log_message("Mouse left click");
    ev->type = EV_KEY;
    ev->code = BTN_LEFT;
    return CHANGED_TO_MOUSE;

  case KEY_B:
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
    if (keycode == KEY_UP || keycode == KEY_DOWN)
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

    int fd = open(file_path, O_RDONLY);
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

/* --- Event Handling Functions --- */
static int handle_input_event(device_t *dev, struct input_event *ev)
{
  /* Passive mode (local patch): the device is NOT grabbed, so the system
   * receives every event natively — we only observe. Return MUTE (not
   * PASS_THRU) so nothing is re-injected through the clone device. */
  if (!app_state.mouse.enabled)
  {
    if (ev->type == EV_KEY && ev->code == SOFTKEY_CODE)
    {
      if (ev->value == 1)
      {
        app_state.mouse.softhold_since = now_ms();
      }
      else if (app_state.mouse.softhold_since)
      {
        long long held = now_ms() - app_state.mouse.softhold_since;
        app_state.mouse.softhold_since = 0;
        log_message("softkey held %lldms (passive)", held);
        if (held >= HOLD_TOGGLE_MS)
          mouse_activate();
      }
    }
    return MUTE_EVENT;
  }

  /* Active mode (keypads grabbed): the EV_KEY event is authoritative —
   * the kernel may also emit an MSC_SCAN companion for the same press. */
  if (ev->type == EV_MSC)
    return MUTE_EVENT;

  if (ev->type != EV_KEY)
    return PASS_THRU_EVENT;

  /* Upper-left soft key: hold HOLD_TOGGLE_MS then release to exit mouse mode;
   * a short tap keeps its old job of scrolling up one step. */
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
      log_message("softkey held %lldms (active)", held);
      if (held >= HOLD_TOGGLE_MS)
      {
        mouse_deactivate();
        return MUTE_EVENT;
      }
    }
    libevdev_uinput_write_event(app_state.mouse.uidev, EV_REL, REL_WHEEL, 1);
    libevdev_uinput_write_event(app_state.mouse.uidev, EV_SYN, SYN_REPORT, 0);
    log_message("softkey tap: scroll up");
    return MUTE_EVENT;
  }

  /* Star tap also exits mouse mode (on release, so a stray press never sticks) */
  if (ev->code == STAR_CODE)
  {
    log_message("star key value=%d", ev->value);
    if (ev->value == 0)
      mouse_deactivate();
    return MUTE_EVENT;
  }

  /* Pound is not a standard keycode — map it onto scroll-down */
  if (ev->code == POUND_CODE)
    ev->code = KEY_SEND;

  return mouse_handle_event(dev, ev);
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
    rfds = fds;
    /* Local patch: while a key is held for auto-repeat, bound select() to the
     * next repeat deadline instead of blocking forever. */
    {
      struct timeval tv;
      struct timeval *tvp = NULL;
      if (app_state.mouse.enabled && app_state.mouse.held_code)
      {
        long long wait = app_state.mouse.next_repeat_ms - now_ms();
        if (wait < 0)
          wait = 0;
        tv.tv_sec = (time_t)(wait / 1000);
        tv.tv_usec = (suseconds_t)((wait % 1000) * 1000);
        tvp = &tv;
      }
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

      if (read(d->fd, &event, sizeof(event)) != sizeof(event))
      {
        log_message("ERROR: Failed to read event");
        continue;
      }

#ifdef DEBUG
      /* Only log events while active — passive mode would spam the log
       * with every normal keypress the system already received. */
      if (app_state.mouse.enabled)
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
        if (app_state.mouse.enabled)
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

  /* Initialize virtual mouse */
  if (mouse_init() != 0)
  {
    log_message("ERROR: Failed to initialize virtual mouse");
    devices_cleanup();
    log_close();
    return 1;
  }

  /* Run the main event loop */
  int result = run_event_loop();

  /* Clean up all resources */
  mouse_cleanup();
  devices_cleanup();

  log_message("FlipMouse shutting down");
  log_close();

  return result;
}
