/*
 * Flip 2 landscape virtual gamepad — remaps matrix keypad to uinput gamepad
 * when gamepad mode is active (config or landscape auto).
 */

#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/input-event-codes.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <time.h>

#include <libevdev/libevdev.h>
#include <libevdev/libevdev-uinput.h>

#define CONFIG_FILE "/data/local/flip2/gamepad.conf"
#define POLL_LANDSCAPE_MS 1500
#define BACK_REAL_HOLD_MS 2000

#define STAR_CODE 522
#define POUND_CODE 523
#define MESSENGER_CODE 30
#define SOFT_LEFT 139
#define SOFT_RIGHT 48

#define AXIS_MAX 32767
#define AXIS_MIN -32767
#define STICK_EDGE AXIS_MAX

typedef struct dev_st {
  int fd;
  const char *name;
  struct libevdev *evdev;
  struct libevdev_uinput *uidev;
  struct dev_st *next;
} device_t;

typedef struct {
  device_t *devices;
  struct libevdev *gp_dev;
  struct libevdev_uinput *gp_uidev;
  int active;
  int manual_on;
  int landscape_auto;
  int stick_lx, stick_ly;
  int stick_rx, stick_ry;
  long long back_hold_since;
  volatile sig_atomic_t running;
} app_t;

static app_t app = {0};

static long long now_ms(void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
}

static void pass_through_matrix(struct input_event *ev)
{
  for (device_t *d = app.devices; d; d = d->next) {
    if (!d->uidev || strcmp(d->name, "matrix-keypad") != 0)
      continue;
    libevdev_uinput_write_event(d->uidev, ev->type, ev->code, ev->value);
    libevdev_uinput_write_event(d->uidev, EV_SYN, SYN_REPORT, 0);
    break;
  }
}

static const char *supported_devices[] = {"mtk-kpd", "matrix-keypad", NULL};

static void cfg_load(void)
{
  FILE *f = fopen(CONFIG_FILE, "r");
  app.manual_on = 0;
  app.landscape_auto = 1;
  if (!f)
    return;
  char line[256];
  while (fgets(line, sizeof line, f)) {
    if (strncmp(line, "enabled=", 8) == 0)
      app.manual_on = (line[8] == '1');
    if (strncmp(line, "landscape_auto=", 15) == 0)
      app.landscape_auto = (line[15] == '1');
  }
  fclose(f);
}

static int landscape_now(void)
{
  FILE *p = popen("dumpsys window displays 2>/dev/null", "r");
  if (!p)
    return 0;
  char buf[512];
  int land = 0;
  while (fgets(buf, sizeof buf, p)) {
    if (strstr(buf, "rotation=1") || strstr(buf, "rotation=3"))
      land = 1;
  }
  pclose(p);
  return land;
}

static int should_be_active(void)
{
  cfg_load();
  if (app.manual_on)
    return 1;
  if (app.landscape_auto && landscape_now())
    return 1;
  return 0;
}

static void stick_apply(void)
{
  if (!app.gp_uidev)
    return;
  libevdev_uinput_write_event(app.gp_uidev, EV_ABS, ABS_X, app.stick_lx);
  libevdev_uinput_write_event(app.gp_uidev, EV_ABS, ABS_Y, app.stick_ly);
  libevdev_uinput_write_event(app.gp_uidev, EV_ABS, ABS_RX, app.stick_rx);
  libevdev_uinput_write_event(app.gp_uidev, EV_ABS, ABS_RY, app.stick_ry);
  libevdev_uinput_write_event(app.gp_uidev, EV_SYN, SYN_REPORT, 0);
}

static void set_active(int on)
{
  device_t *d;
  if (on == app.active)
    return;
  app.active = on;
  if (on) {
    app.stick_lx = app.stick_ly = app.stick_rx = app.stick_ry = 0;
    for (d = app.devices; d; d = d->next)
      ioctl(d->fd, EVIOCGRAB, 1);
  } else {
    for (d = app.devices; d; d = d->next)
      ioctl(d->fd, EVIOCGRAB, 0);
    stick_apply();
  }
}

static int gamepad_init(void)
{
  struct input_absinfo absinfo = {.minimum = AXIS_MIN, .maximum = AXIS_MAX, .fuzz = 0, .flat = 0};

  app.gp_dev = libevdev_new();
  if (!app.gp_dev)
    return -1;
  libevdev_set_name(app.gp_dev, "Flip2 Gamepad");
  libevdev_enable_event_type(app.gp_dev, EV_KEY);
  libevdev_enable_event_type(app.gp_dev, EV_ABS);
  libevdev_enable_event_code(app.gp_dev, EV_KEY, BTN_GAMEPAD, NULL);
  libevdev_enable_event_code(app.gp_dev, EV_KEY, BTN_SOUTH, NULL);
  libevdev_enable_event_code(app.gp_dev, EV_KEY, BTN_EAST, NULL);
  libevdev_enable_event_code(app.gp_dev, EV_KEY, BTN_NORTH, NULL);
  libevdev_enable_event_code(app.gp_dev, EV_KEY, BTN_WEST, NULL);
  libevdev_enable_event_code(app.gp_dev, EV_KEY, BTN_TL, NULL);
  libevdev_enable_event_code(app.gp_dev, EV_KEY, BTN_TR, NULL);
  libevdev_enable_event_code(app.gp_dev, EV_KEY, BTN_TL2, NULL);
  libevdev_enable_event_code(app.gp_dev, EV_KEY, BTN_TR2, NULL);
  libevdev_enable_event_code(app.gp_dev, EV_KEY, BTN_START, NULL);
  libevdev_enable_event_code(app.gp_dev, EV_KEY, BTN_THUMBL, NULL);
  libevdev_enable_event_code(app.gp_dev, EV_ABS, ABS_X, &absinfo);
  libevdev_enable_event_code(app.gp_dev, EV_ABS, ABS_Y, &absinfo);
  libevdev_enable_event_code(app.gp_dev, EV_ABS, ABS_RX, &absinfo);
  libevdev_enable_event_code(app.gp_dev, EV_ABS, ABS_RY, &absinfo);
  libevdev_enable_event_code(app.gp_dev, EV_ABS, ABS_HAT0X, &absinfo);
  libevdev_enable_event_code(app.gp_dev, EV_ABS, ABS_HAT0Y, &absinfo);

  if (libevdev_uinput_create_from_device(app.gp_dev, LIBEVDEV_UINPUT_OPEN_MANAGED,
                                         &app.gp_uidev) < 0) {
    libevdev_free(app.gp_dev);
    app.gp_dev = NULL;
    return -1;
  }
  return 0;
}

static void emit_key(int code, int value)
{
  libevdev_uinput_write_event(app.gp_uidev, EV_KEY, code, value);
  libevdev_uinput_write_event(app.gp_uidev, EV_SYN, SYN_REPORT, 0);
}

static void dpad_map(int k, int v)
{
  int hx = 0, hy = 0;

  if (v == 0) {
    app.stick_lx = app.stick_ly = 0;
    stick_apply();
    libevdev_uinput_write_event(app.gp_uidev, EV_ABS, ABS_HAT0X, 0);
    libevdev_uinput_write_event(app.gp_uidev, EV_ABS, ABS_HAT0Y, 0);
    libevdev_uinput_write_event(app.gp_uidev, EV_SYN, SYN_REPORT, 0);
    return;
  }
  switch (k) {
  case KEY_UP:
    app.stick_lx = -STICK_EDGE;
    hx = -1;
    break;
  case KEY_DOWN:
    app.stick_lx = STICK_EDGE;
    hx = 1;
    break;
  case KEY_LEFT:
    app.stick_ly = -STICK_EDGE;
    hy = -1;
    break;
  case KEY_RIGHT:
    app.stick_ly = STICK_EDGE;
    hy = 1;
    break;
  default:
    return;
  }
  stick_apply();
  libevdev_uinput_write_event(app.gp_uidev, EV_ABS, ABS_HAT0X, hx);
  libevdev_uinput_write_event(app.gp_uidev, EV_ABS, ABS_HAT0Y, hy);
  libevdev_uinput_write_event(app.gp_uidev, EV_SYN, SYN_REPORT, 0);
}

static void numpad_stick(int k, int v)
{
  int rx = 0, ry = 0;

  if (v == 0) {
    app.stick_rx = app.stick_ry = 0;
    stick_apply();
    return;
  }
  switch (k) {
  case KEY_5:
    break;
  case KEY_8:
    rx = STICK_EDGE;
    break;
  case KEY_2:
    rx = -STICK_EDGE;
    break;
  case KEY_4:
    ry = STICK_EDGE;
    break;
  case KEY_1:
    rx = -STICK_EDGE;
    ry = -STICK_EDGE;
    break;
  case KEY_9:
    rx = STICK_EDGE;
    ry = -STICK_EDGE;
    break;
  case KEY_7:
    rx = -STICK_EDGE;
    ry = STICK_EDGE;
    break;
  case KEY_3:
    rx = STICK_EDGE;
    ry = STICK_EDGE;
    break;
  default:
    return;
  }
  app.stick_rx = rx;
  app.stick_ry = ry;
  stick_apply();
}

static int handle_key(int code, int value)
{
  if (!app.active)
    return 0;

  switch (code) {
  case KEY_UP:
  case KEY_DOWN:
  case KEY_LEFT:
  case KEY_RIGHT:
    dpad_map(code, value);
    return 1;
  case KEY_1:
  case KEY_2:
  case KEY_3:
  case KEY_4:
  case KEY_5:
  case KEY_7:
  case KEY_8:
  case KEY_9:
    numpad_stick(code, value);
    return 1;
  case KEY_ENTER:
    emit_key(BTN_THUMBL, value);
    return 1;
  case POUND_CODE:
    emit_key(BTN_SOUTH, value);
    return 1;
  case KEY_0:
    emit_key(BTN_EAST, value);
    return 1;
  case STAR_CODE:
    emit_key(BTN_NORTH, value);
    return 1;
  case SOFT_LEFT:
    emit_key(BTN_TL, value);
    return 1;
  case SOFT_RIGHT:
    emit_key(BTN_TR, value);
    return 1;
  case MESSENGER_CODE:
    emit_key(BTN_TR2, value);
    return 1;
  case KEY_BACK:
    if (value == 1) {
      app.back_hold_since = now_ms();
      emit_key(BTN_START, 1);
      return 1;
    }
    {
      long long held = app.back_hold_since ? now_ms() - app.back_hold_since : 0;
      app.back_hold_since = 0;
      if (held >= BACK_REAL_HOLD_MS) {
        emit_key(BTN_START, 0);
        struct input_event be = {.type = EV_KEY, .code = KEY_BACK, .value = 1};
        pass_through_matrix(&be);
        be.value = 0;
        pass_through_matrix(&be);
      } else {
        emit_key(BTN_START, 0);
      }
      return 1;
    }
  case KEY_VOLUMEUP:
    emit_key(BTN_TL2, value);
    return 1;
  case KEY_VOLUMEDOWN:
    emit_key(BTN_TR2, value);
    return 1;
  default:
    break;
  }
  return 0;
}

static int devices_init(void)
{
  DIR *dir = opendir("/dev/input");
  if (!dir)
    return -1;
  struct dirent *ent;
  while ((ent = readdir(dir)) != NULL) {
    if (ent->d_type != DT_CHR)
      continue;
    char path[256];
    snprintf(path, sizeof path, "/dev/input/%s", ent->d_name);
    int fd = open(path, O_RDONLY | O_NONBLOCK);
    if (fd < 0)
      continue;
    struct libevdev *ev = NULL;
    if (libevdev_new_from_fd(fd, &ev) < 0) {
      close(fd);
      continue;
    }
    int ok = 0;
    for (int i = 0; supported_devices[i]; i++) {
      if (strcmp(libevdev_get_name(ev), supported_devices[i]) == 0) {
        ok = 1;
        break;
      }
    }
    if (!ok) {
      libevdev_free(ev);
      close(fd);
      continue;
    }
    device_t *d = calloc(1, sizeof *d);
    d->fd = fd;
    d->name = libevdev_get_name(ev);
    d->evdev = ev;
    d->uidev = NULL;
    if (libevdev_uinput_create_from_device(
            ev, LIBEVDEV_UINPUT_OPEN_MANAGED, &d->uidev) < 0)
      d->uidev = NULL;
    d->next = app.devices;
    app.devices = d;
  }
  closedir(dir);
  return app.devices ? 0 : -1;
}

static void devices_free(void)
{
  while (app.devices) {
    device_t *n = app.devices->next;
    ioctl(app.devices->fd, EVIOCGRAB, 0);
    if (app.devices->uidev)
      libevdev_uinput_destroy(app.devices->uidev);
    libevdev_free(app.devices->evdev);
    close(app.devices->fd);
    free(app.devices);
    app.devices = n;
  }
}

static void on_sig(int sig)
{
  (void)sig;
  app.running = 0;
}

int main(int argc, char **argv)
{
  (void)argc;
  (void)argv;
  signal(SIGINT, on_sig);
  signal(SIGTERM, on_sig);
  app.running = 1;

  if (devices_init() != 0 || gamepad_init() != 0)
    return 1;

  set_active(should_be_active());

  long long last_cfg = 0;
  struct timespec ts;

  while (app.running) {
    clock_gettime(CLOCK_MONOTONIC, &ts);
    long long now = ts.tv_sec * 1000LL + ts.tv_nsec / 1000000;
    if (now - last_cfg >= POLL_LANDSCAPE_MS) {
      set_active(should_be_active());
      last_cfg = now;
    }

    struct pollfd fds[16];
    int nf = 0;
    for (device_t *d = app.devices; d && nf < 16; d = d->next) {
      fds[nf].fd = d->fd;
      fds[nf].events = POLLIN;
      nf++;
    }
    if (poll(fds, nf, 200) <= 0)
      continue;

    for (device_t *d = app.devices; d; d = d->next) {
      struct input_event ev;
      while (libevdev_next_event(d->evdev, LIBEVDEV_READ_FLAG_NORMAL, &ev) ==
             LIBEVDEV_READ_STATUS_SUCCESS) {
        if (ev.type == EV_MSC)
          continue;
        if (ev.type == EV_KEY)
          (void)handle_key(ev.code, ev.value);
      }
    }
  }

  set_active(0);
  if (app.gp_uidev)
    libevdev_uinput_destroy(app.gp_uidev);
  if (app.gp_dev)
    libevdev_free(app.gp_dev);
  devices_free();
  return 0;
}
