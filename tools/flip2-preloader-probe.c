/*
 * Watch USB port 1-2 for MediaTek preloader 0e8d:2000.
 * Send the 8-byte sequence FASTBOOT once.
 * Confirm is READYTOO. A READYTOOB prefix is the same confirm.
 * Any other non-empty reply exits 99 and must not be retried.
 * Never resets the bus and never sends unlock or flash commands.
 */
#define _GNU_SOURCE
#include <sys/ioctl.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/usbdevice_fs.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static const char kPort[] = "1-2";
static const unsigned char kBootseq[] = {
	'F', 'A', 'S', 'T', 'B', 'O', 'O', 'T'
};
static const unsigned char kReadyToo[] = {
	'R', 'E', 'A', 'D', 'Y', 'T', 'O', 'O'
};
static const unsigned char kReadyToob[] = {
	'R', 'E', 'A', 'D', 'Y', 'T', 'O', 'O', 'B'
};
_Static_assert(sizeof kBootseq == 8, "FASTBOOT is 8 bytes");
_Static_assert(sizeof kReadyToo == 8, "confirm is 8 bytes");
_Static_assert(sizeof kReadyToob == 9, "READYTOOB is 9 bytes");

static int g_opens;
static int g_attempted;
static int g_denied;

static void die_usage(void)
{
	fprintf(stderr,
		"usage: flip2-preloader-probe [--check] [--wait-ms N]\n"
		"  --check    print ioctl numbers and exit; opens nothing\n"
		"  --wait-ms  poll port 1-2 for up to N ms (max 180000)\n"
		"exit 0 confirm, 2 miss, 3 empty reply, 97 refused, 98 permission, 99 hard-stop\n");
	exit(1);
}

static long long now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void note_once(const char *key, const char *msg)
{
	enum { N = 4, KEY = 32, MSG = 160 };
	static char keys[N][KEY];
	static char msgs[N][MSG];
	static int used;
	int i;

	for (i = 0; i < used; i++) {
		if (strcmp(keys[i], key) != 0)
			continue;
		if (strcmp(msgs[i], msg) == 0)
			return;
		snprintf(msgs[i], MSG, "%s", msg);
		puts(msg);
		fflush(stdout);
		return;
	}
	if (used < N) {
		snprintf(keys[used], KEY, "%s", key);
		snprintf(msgs[used], MSG, "%s", msg);
		used++;
	}
	puts(msg);
	fflush(stdout);
}

static int read_sysfs_hex(const char *path, unsigned int *out)
{
	FILE *f = fopen(path, "r");
	char buf[64];
	char *end = NULL;
	unsigned long v;

	if (!f)
		return -1;
	if (!fgets(buf, sizeof buf, f)) {
		fclose(f);
		return -1;
	}
	fclose(f);
	v = strtoul(buf, &end, 16);
	if (end == buf)
		return -1;
	*out = (unsigned int)v;
	return 0;
}

static int read_sysfs_dec(const char *path, unsigned int *out)
{
	FILE *f = fopen(path, "r");
	unsigned int v = 0;
	int n;

	if (!f)
		return -1;
	n = fscanf(f, "%u", &v);
	fclose(f);
	if (n != 1)
		return -1;
	*out = v;
	return 0;
}

static void hexdump(const char *tag, const unsigned char *b, int n)
{
	int i;

	printf("%s (%d):", tag, n);
	for (i = 0; i < n; i++)
		printf(" %02x", b[i]);
	printf(" \"");
	for (i = 0; i < n; i++) {
		unsigned char c = b[i];

		putchar((c >= 32 && c < 127) ? c : '.');
	}
	printf("\"\n");
	fflush(stdout);
}

static void note_port(void)
{
	char vpath[512], ppath[512], msg[128];
	unsigned int vid = 0, pid = 0;
	int n;

	n = snprintf(vpath, sizeof vpath,
		     "/sys/bus/usb/devices/%s/idVendor", kPort);
	if (n < 0 || (size_t)n >= sizeof vpath)
		return;
	n = snprintf(ppath, sizeof ppath,
		     "/sys/bus/usb/devices/%s/idProduct", kPort);
	if (n < 0 || (size_t)n >= sizeof ppath)
		return;
	if (read_sysfs_hex(vpath, &vid) != 0 || read_sysfs_hex(ppath, &pid) != 0) {
		snprintf(msg, sizeof msg, "port %s is empty", kPort);
		note_once("port", msg);
		return;
	}
	snprintf(msg, sizeof msg, "port %s is %04x:%04x", kPort, vid, pid);
	note_once("port", msg);
}

static int find_preloader(char *sysfs, size_t sysfs_len, char *node, size_t node_len)
{
	DIR *d;
	struct dirent *de;
	int count = 0;
	char found_name[64];
	unsigned int bus = 0, devn = 0;

	found_name[0] = 0;
	d = opendir("/sys/bus/usb/devices");
	if (!d) {
		fprintf(stderr, "opendir sysfs: %s\n", strerror(errno));
		return -1;
	}
	while ((de = readdir(d)) != NULL) {
		char vpath[512], ppath[512], msg[128];
		unsigned int vid = 0, pid = 0;
		int n;

		if (de->d_name[0] == '.' || strchr(de->d_name, ':'))
			continue;
		if (strlen(de->d_name) >= sizeof found_name)
			continue;
		n = snprintf(vpath, sizeof vpath,
			     "/sys/bus/usb/devices/%s/idVendor", de->d_name);
		if (n < 0 || (size_t)n >= sizeof vpath)
			continue;
		n = snprintf(ppath, sizeof ppath,
			     "/sys/bus/usb/devices/%s/idProduct", de->d_name);
		if (n < 0 || (size_t)n >= sizeof ppath)
			continue;
		if (read_sysfs_hex(vpath, &vid) != 0 || read_sysfs_hex(ppath, &pid) != 0)
			continue;
		if (vid == 0x0e8d && pid == 0x0003) {
			snprintf(msg, sizeof msg,
				 "saw %s 0e8d:0003 bootrom; not opening", de->d_name);
			note_once("bootrom", msg);
			continue;
		}
		if (vid != 0x0e8d || pid != 0x2000)
			continue;
		snprintf(msg, sizeof msg, "saw %s 0e8d:2000", de->d_name);
		note_once("pre", msg);
		count++;
		snprintf(found_name, sizeof found_name, "%s", de->d_name);
	}
	closedir(d);
	if (count > 1) {
		fprintf(stderr, "more than one 0e8d:2000; not opening\n");
		return -2;
	}
	if (count == 0)
		return 1;
	if (strcmp(found_name, kPort) != 0) {
		char msg[128];

		snprintf(msg, sizeof msg,
			 "0e8d:2000 at %s is not port %s; not opening",
			 found_name, kPort);
		note_once("other", msg);
		return 1;
	}
	{
		char bpath[512], dpath[512];
		int n;

		n = snprintf(bpath, sizeof bpath,
			     "/sys/bus/usb/devices/%s/busnum", kPort);
		if (n < 0 || (size_t)n >= sizeof bpath || read_sysfs_dec(bpath, &bus) != 0)
			return -1;
		n = snprintf(dpath, sizeof dpath,
			     "/sys/bus/usb/devices/%s/devnum", kPort);
		if (n < 0 || (size_t)n >= sizeof dpath || read_sysfs_dec(dpath, &devn) != 0)
			return -1;
	}
	if (snprintf(sysfs, sysfs_len, "/sys/bus/usb/devices/%s", kPort) >= (int)sysfs_len)
		return -1;
	if (snprintf(node, node_len, "/dev/bus/usb/%03u/%03u", bus, devn) >= (int)node_len)
		return -1;
	return 0;
}

static int ctrl(int fd, uint8_t rt, uint8_t req, uint16_t value, uint16_t index,
		unsigned char *data, uint16_t len, unsigned int timeout)
{
	struct usbdevfs_ctrltransfer xfer;
	int rc;

	memset(&xfer, 0, sizeof xfer);
	xfer.bRequestType = rt;
	xfer.bRequest = req;
	xfer.wValue = value;
	xfer.wIndex = index;
	xfer.wLength = len;
	xfer.timeout = timeout;
	xfer.data = data;
	rc = ioctl(fd, USBDEVFS_CONTROL, &xfer);
	if (rc < 0)
		return -1;
	return rc;
}

static int verify_desc(int fd)
{
	unsigned char desc[18];
	int n;
	unsigned int vid, pid;

	memset(desc, 0, sizeof desc);
	n = ctrl(fd, 0x80, 0x06, 0x0100, 0, desc, sizeof desc, 1000);
	if (n < 18) {
		fprintf(stderr, "GET_DESCRIPTOR rc %d: %s\n", n,
			n < 0 ? strerror(errno) : "short");
		return -1;
	}
	hexdump("device-descriptor", desc, 18);
	if (desc[0] < 18 || desc[1] != 0x01) {
		fprintf(stderr, "not a device descriptor; not sending\n");
		return -1;
	}
	vid = desc[8] | ((unsigned int)desc[9] << 8);
	pid = desc[10] | ((unsigned int)desc[11] << 8);
	printf("descriptor id %04x:%04x\n", vid, pid);
	if (vid != 0x0e8d || pid != 0x2000) {
		fprintf(stderr, "descriptor is not 0e8d:2000; not sending\n");
		return -2;
	}
	return 0;
}

static int claim_iface(int fd, unsigned int iface)
{
	struct usbdevfs_disconnect_claim dc;
	unsigned int n = iface;
	int err;

	memset(&dc, 0, sizeof dc);
	dc.interface = iface;
	dc.flags = 0;
	if (ioctl(fd, USBDEVFS_DISCONNECT_CLAIM, &dc) == 0) {
		printf("disconnect-claim interface %u\n", iface);
		return 0;
	}
	err = errno;
	fprintf(stderr, "DISCONNECT_CLAIM iface %u: %s\n", iface, strerror(err));
	if (ioctl(fd, USBDEVFS_CLAIMINTERFACE, &n) == 0) {
		printf("claim interface %u\n", iface);
		return 0;
	}
	err = errno;
	fprintf(stderr, "CLAIMINTERFACE iface %u: %s\n", iface, strerror(err));
	if (err == EACCES || err == EPERM)
		return -EACCES;
	return -1;
}

static void release_iface(int fd, int *claimed, unsigned int iface)
{
	unsigned int n;

	if (!*claimed || fd < 0)
		return;
	n = iface;
	if (ioctl(fd, USBDEVFS_RELEASEINTERFACE, &n) < 0)
		fprintf(stderr, "RELEASEINTERFACE %u: %s\n", iface, strerror(errno));
	*claimed = 0;
}

struct choice {
	int iface;
	unsigned int alt;
	unsigned int ep_in;
	unsigned int ep_out;
	int score;
};

static void consider(const char *devdir, const char *ifname, struct choice *best,
		     unsigned int *comm, int *have_comm)
{
	char base[512];
	unsigned int cls = 0, num = 0, alt = 0;
	unsigned int ep_in = 0, ep_out = 0;
	int n_in = 0, n_out = 0;
	int n, score;
	DIR *d;
	struct dirent *de;

	n = snprintf(base, sizeof base, "%s/%s", devdir, ifname);
	if (n < 0 || (size_t)n >= sizeof base)
		return;
	{
		char p[576];

		n = snprintf(p, sizeof p, "%s/bInterfaceClass", base);
		if (n < 0 || (size_t)n >= sizeof p || read_sysfs_hex(p, &cls) != 0)
			return;
		n = snprintf(p, sizeof p, "%s/bInterfaceNumber", base);
		if (n < 0 || (size_t)n >= sizeof p || read_sysfs_hex(p, &num) != 0)
			return;
		n = snprintf(p, sizeof p, "%s/bAlternateSetting", base);
		if (n < 0 || (size_t)n >= sizeof p || read_sysfs_dec(p, &alt) != 0)
			alt = 0;
	}
	if (cls == 0x02) {
		*have_comm = 1;
		*comm = num;
	}
	d = opendir(base);
	if (!d)
		return;
	while ((de = readdir(d)) != NULL) {
		char ep[700], a[760], m[760];
		unsigned int addr = 0, attr = 0;

		if (strncmp(de->d_name, "ep_", 3) != 0)
			continue;
		n = snprintf(ep, sizeof ep, "%s/%s", base, de->d_name);
		if (n < 0 || (size_t)n >= sizeof ep)
			continue;
		n = snprintf(a, sizeof a, "%s/bEndpointAddress", ep);
		if (n < 0 || (size_t)n >= sizeof a || read_sysfs_hex(a, &addr) != 0)
			continue;
		n = snprintf(m, sizeof m, "%s/bmAttributes", ep);
		if (n < 0 || (size_t)n >= sizeof m || read_sysfs_hex(m, &attr) != 0)
			continue;
		if ((attr & 3) != 2)
			continue;
		if (addr & 0x80) {
			ep_in = addr;
			n_in++;
		} else {
			ep_out = addr;
			n_out++;
		}
	}
	closedir(d);
	if (n_in != 1 || n_out != 1)
		return;
	score = 10;
	if (cls == 0x0a)
		score += 5;
	if (num == 1)
		score += 1;
	{
		char drv[576], link[256];
		ssize_t ln;

		n = snprintf(drv, sizeof drv, "%s/driver", base);
		if (n >= 0 && (size_t)n < sizeof drv) {
			ln = readlink(drv, link, sizeof link - 1);
			if (ln > 0) {
				link[ln] = 0;
				if (strstr(link, "cdc_acm"))
					score += 3;
			}
		}
	}
	printf("candidate iface %u alt %u class %02x ep_in %02x ep_out %02x score %d\n",
	       num, alt, cls, ep_in, ep_out, score);
	if (score > best->score) {
		best->score = score;
		best->iface = (int)num;
		best->alt = alt;
		best->ep_in = ep_in;
		best->ep_out = ep_out;
	}
}

static int usb_node_ok(const char *node)
{
	unsigned int bus = 0, dev = 0;
	char extra = 0;

	if (sscanf(node, "/dev/bus/usb/%03u/%03u%c", &bus, &dev, &extra) != 2)
		return 0;
	if (bus == 0 || dev == 0)
		return 0;
	return 1;
}

static int talk(const char *sysfs, const char *node)
{
	struct choice best;
	char expect[64];
	DIR *d;
	const char *base;
	size_t blen;
	struct dirent *de;
	int fd = -1;
	int claimed_data = 0;
	int claimed_comm = 0;
	int result = 1;
	unsigned int comm = 0;
	int have_comm = 0;
	unsigned int line_idx;
	unsigned char line_coding[7];
	unsigned char dummy = 0;
	unsigned char outbuf[sizeof kBootseq];
	unsigned char in[32];
	struct usbdevfs_bulktransfer bulk;
	int got = 0;
	long long deadline;
	int n;

	memset(&best, 0, sizeof best);
	best.iface = -1;
	best.score = -1;
	n = snprintf(expect, sizeof expect, "/sys/bus/usb/devices/%s", kPort);
	if (n < 0 || (size_t)n >= sizeof expect || strcmp(sysfs, expect) != 0) {
		fprintf(stderr, "refusing sysfs %s\n", sysfs);
		return 97;
	}
	if (!usb_node_ok(node)) {
		fprintf(stderr, "refusing node %s\n", node);
		return 97;
	}

	d = opendir(sysfs);
	if (!d) {
		fprintf(stderr, "opendir %s: %s\n", sysfs, strerror(errno));
		return 1;
	}
	base = strrchr(sysfs, '/');
	base = base ? base + 1 : sysfs;
	blen = strlen(base);
	while ((de = readdir(d)) != NULL) {
		if (strncmp(de->d_name, base, blen) != 0)
			continue;
		if (de->d_name[blen] != ':')
			continue;
		consider(sysfs, de->d_name, &best, &comm, &have_comm);
	}
	closedir(d);
	if (best.iface < 0) {
		fprintf(stderr, "no bulk in/out interface; not sending\n");
		return 1;
	}
	printf("using iface %d alt %u ep_out %02x ep_in %02x\n",
	       best.iface, best.alt, best.ep_out, best.ep_in);
	if (have_comm)
		printf("cdc comm iface %u\n", comm);

	fd = open(node, O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		fprintf(stderr, "open %s: %s\n", node, strerror(errno));
		if (errno == EACCES || errno == EPERM)
			g_denied++;
		result = 1;
		goto out;
	}
	g_opens++;
	printf("open %s fd %d opens=%d\n", node, fd, g_opens);
	{
		int vr = verify_desc(fd);

		if (vr == -2) {
			result = 97;
			goto out;
		}
		if (vr != 0) {
			fprintf(stderr, "descriptor not ready; will retry\n");
			result = 1;
			goto out;
		}
	}
	{
		int cr = claim_iface(fd, (unsigned int)best.iface);

		if (cr != 0) {
			if (cr == -EACCES)
				g_denied++;
			result = 1;
			goto out;
		}
	}
	claimed_data = 1;
	if (have_comm && comm != (unsigned int)best.iface) {
		if (claim_iface(fd, comm) == 0)
			claimed_comm = 1;
		else
			fprintf(stderr, "comm interface not claimed; continuing\n");
	}
	{
		struct usbdevfs_setinterface si;

		memset(&si, 0, sizeof si);
		si.interface = (unsigned int)best.iface;
		si.altsetting = best.alt;
		if (ioctl(fd, USBDEVFS_SETINTERFACE, &si) < 0)
			fprintf(stderr, "SETINTERFACE alt %u: %s\n",
				best.alt, strerror(errno));
		else
			printf("SETINTERFACE iface %d alt %u\n", best.iface, best.alt);
	}

	line_idx = claimed_comm ? comm : (unsigned int)best.iface;
	/* CDC ACM SET_LINE_CODING is 7 bytes; FASTBOOT stays 8 bytes. */
	line_coding[0] = (unsigned char)(115200 & 0xff);
	line_coding[1] = (unsigned char)((115200 >> 8) & 0xff);
	line_coding[2] = (unsigned char)((115200 >> 16) & 0xff);
	line_coding[3] = (unsigned char)((115200 >> 24) & 0xff);
	line_coding[4] = 0;
	line_coding[5] = 0;
	line_coding[6] = 8;
	if (ctrl(fd, 0x21, 0x20, 0, (uint16_t)line_idx, line_coding, 7, 1000) < 0)
		fprintf(stderr, "SET_LINE_CODING iface %u: %s\n",
			line_idx, strerror(errno));
	else
		printf("SET_LINE_CODING 115200 8N1 iface %u\n", line_idx);
	if (ctrl(fd, 0x21, 0x22, 0x0003, (uint16_t)line_idx, &dummy, 0, 1000) < 0)
		fprintf(stderr, "SET_CONTROL_LINE_STATE: %s\n", strerror(errno));
	else
		printf("SET_CONTROL_LINE_STATE DTR|RTS\n");

	memcpy(outbuf, kBootseq, sizeof outbuf);
	{
		unsigned int requested = (unsigned int)sizeof outbuf;
		unsigned int actual;
		int rc;

		memset(&bulk, 0, sizeof bulk);
		bulk.ep = best.ep_out;
		bulk.len = requested;
		bulk.timeout = 500;
		bulk.data = outbuf;
		g_attempted = 1;
		printf("sending FASTBOOT once\n");
		hexdump("tx", outbuf, (int)sizeof outbuf);
		rc = ioctl(fd, USBDEVFS_BULK, &bulk);
		if (rc < 0) {
			fprintf(stderr, "BULK OUT: %s\n", strerror(errno));
			result = 1;
			goto out;
		}
		/* do_proc_bulk returns the transferred count. len stays the request size. */
		printf("bulk out rc %d len %u\n", rc, bulk.len);
		if ((unsigned int)rc > requested) {
			fprintf(stderr, "bulk out length rc %d request %u\n",
				rc, requested);
			result = 1;
			goto out;
		}
		actual = (unsigned int)rc;
		printf("bulk out actual %u\n", actual);
		if (actual != requested) {
			fprintf(stderr, "short bulk out; not reading a reply\n");
			result = 1;
			goto out;
		}
	}

	memset(in, 0, sizeof in);
	deadline = now_ms() + 500;
	while (got < 16 && now_ms() < deadline) {
		struct usbdevfs_bulktransfer rin;
		unsigned int cap = (unsigned int)(sizeof in - got);
		unsigned int remain = (unsigned int)(deadline - now_ms());
		unsigned int nread;
		int rc;

		if (got >= 8 && remain > 40)
			remain = 40;
		if (remain == 0)
			remain = 1;
		memset(&rin, 0, sizeof rin);
		rin.ep = best.ep_in;
		rin.len = cap;
		rin.timeout = remain;
		rin.data = in + got;
		rc = ioctl(fd, USBDEVFS_BULK, &rin);
		if (rc < 0) {
			if (errno != ETIMEDOUT && errno != EAGAIN &&
			    errno != ENODEV && errno != EPIPE)
				fprintf(stderr, "BULK IN: %s\n", strerror(errno));
			break;
		}
		printf("bulk in rc %d len %u cap %u\n", rc, rin.len, cap);
		if ((unsigned int)rc > cap) {
			fprintf(stderr, "bulk in length rc %d cap %u\n",
				rc, cap);
			result = 1;
			goto out;
		}
		/* do_proc_bulk returns the transferred count, including 0. len stays the request size. */
		nread = (unsigned int)rc;
		if (nread == 0)
			break;
		got += (int)nread;
	}
	hexdump("rx", in, got);
	if (got <= 0) {
		printf("empty reply\n");
		result = 3;
		goto out;
	}
	if (got >= 8 && memcmp(in, kReadyToo, 8) == 0) {
		if (got >= 9 && memcmp(in, kReadyToob, 9) == 0)
			printf("confirm READYTOOB\n");
		else
			printf("confirm READYTOO\n");
		result = 0;
		goto out;
	}
	printf("hard-stop: non-empty reply is not READYTOO\n");
	result = 99;
out:
	release_iface(fd, &claimed_comm, comm);
	release_iface(fd, &claimed_data, (unsigned int)best.iface);
	if (fd >= 0)
		close(fd);
	return result;
}

static void print_check(void)
{
	printf("USBDEVFS_CONTROL %lu\n", (unsigned long)USBDEVFS_CONTROL);
	printf("USBDEVFS_BULK %lu\n", (unsigned long)USBDEVFS_BULK);
	printf("USBDEVFS_SETINTERFACE %lu\n", (unsigned long)USBDEVFS_SETINTERFACE);
	printf("USBDEVFS_CLAIMINTERFACE %lu\n", (unsigned long)USBDEVFS_CLAIMINTERFACE);
	printf("USBDEVFS_RELEASEINTERFACE %lu\n", (unsigned long)USBDEVFS_RELEASEINTERFACE);
	printf("USBDEVFS_DISCONNECT_CLAIM %lu\n", (unsigned long)USBDEVFS_DISCONNECT_CLAIM);
	printf("sizeof ctrl %zu bulk %zu disconnect_claim %zu\n",
	       sizeof(struct usbdevfs_ctrltransfer),
	       sizeof(struct usbdevfs_bulktransfer),
	       sizeof(struct usbdevfs_disconnect_claim));
	hexdump("bootseq", kBootseq, (int)sizeof kBootseq);
	printf("port %s\n", kPort);
	printf("check ok; no device opened\n");
}

int main(int argc, char **argv)
{
	int wait_ms = 0;
	int check = 0;
	int i;
	long long deadline;

	setvbuf(stdout, NULL, _IOLBF, 0);
	setvbuf(stderr, NULL, _IOLBF, 0);
	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--check") == 0) {
			check = 1;
		} else if (strcmp(argv[i], "--wait-ms") == 0) {
			if (i + 1 >= argc)
				die_usage();
			wait_ms = atoi(argv[++i]);
			if (wait_ms < 0)
				die_usage();
		} else {
			die_usage();
		}
	}
	if (wait_ms > 180000)
		wait_ms = 180000;
	if (sizeof kBootseq != 8 || memcmp(kBootseq, "FASTBOOT", 8) != 0) {
		fprintf(stderr, "refusing internal bootseq\n");
		return 97;
	}
	if (check) {
		print_check();
		return 0;
	}

	printf("watching usb port %s for 0e8d:2000\n", kPort);
	fflush(stdout);
	deadline = now_ms() + wait_ms;
	for (;;) {
		char sysfs[512], node[64];
		int rc;

		note_port();
		rc = find_preloader(sysfs, sizeof sysfs, node, sizeof node);
		if (rc == -2)
			return 97;
		if (rc < 0)
			return 1;
		if (rc == 0) {
			printf("preloader %s node %s\n", sysfs, node);
			rc = talk(sysfs, node);
			printf("result %d opens=%d attempted=%d denied=%d\n",
			       rc, g_opens, g_attempted, g_denied);
			if (rc == 0 || rc == 3 || rc == 97 || rc == 98 ||
			    rc == 99 || g_attempted)
				return rc;
		}
		if (now_ms() >= deadline) {
			printf("no confirm (opens=%d attempted=%d denied=%d)\n",
			       g_opens, g_attempted, g_denied);
			return (!g_attempted && g_denied > 0) ? 98 : 2;
		}
		{
			struct timespec ts;

			ts.tv_sec = 0;
			ts.tv_nsec = 20 * 1000 * 1000;
			nanosleep(&ts, NULL);
		}
	}
}
