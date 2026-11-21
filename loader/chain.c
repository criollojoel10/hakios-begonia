/*
 * mtkchain-begonia M1: read the ramoops pmsg request, log to the ramoops
 * console, chain the Linux arm64 Image.
 *
 * ramoops layout on begonia (from the bootloader command line
 * ramoops.mem_address=0x4d010000 mem_size=0xe0000 console_size=0x40000
 * pmsg_size=0x10000, the same layout mtkloader uses on MT6768):
 *
 *   0x4d010000  base
 *   0x4d09f000  console zone (0x40000)
 *   0x4d0e0000  pmsg zone    (0x10000)
 *
 * Linux has CONFIG_PSTORE_CONSOLE/PMSG off, so linux/hakios_ramoops.c maps
 * this reserved region as /dev/hakios-ramoops: offset 0x8f000 is the
 * console, 0xd0000 the pmsg.  The loader writes its log to the console and
 * scans the pmsg for the request string.  The zone survives the warm reset
 * a reboot performs; a power cycle may lose it.  M2 writes the same log to
 * the microSD (hackios-log) for persistence.
 */
#include <stdint.h>

#define RAMOOPS_BASE        0x4d010000ULL
#define RAMOOPS_PMSG        (RAMOOPS_BASE + 0xd0000ULL)
#define RAMOOPS_PMSG_SIZE   0x10000u
/* The kernel's pstore console owns the console zone (0x8f000).  The pmsg
 * backend is off, so its 64 KiB are free: 60 KiB for the loader log and the
 * last 4 KiB for the one-shot request. */
#define RAMOOPS_LOG_BASE    RAMOOPS_PMSG
#define RAMOOPS_LOG_SIZE    0xf000u
#define RAMOOPS_REQ_BASE    (RAMOOPS_PMSG + 0xf000ULL)
#define RAMOOPS_REQ_SIZE    0x1000u
#define RAMOOPS_SIG         0x43474244u /* "DBGC" */

#define CHAIN_OFFSET        0x40000ULL
#define LINUX_ENTRY         0x40080000ULL
#define STUB_PA             0x4a000000ULL
#define DTB_COPY_PA         0x4b000000ULL
#define DTB_COPY_MAX        0x100000ULL

#define REQUEST_STRING      "DARWIN-BEGONIA:BOOT-XNU"

extern char _start[];
extern char chain_stub[];
extern char chain_stub_end[];
extern char __bss_start[];
extern char __bss_end[];

static uint64_t hdr64(unsigned int off)
{
	return *(volatile uint64_t *)((uint64_t)_start + off);
}

static void memcpy8(uint64_t dst, uint64_t src, uint64_t n)
{
	uint64_t i;

	for (i = 0; i < n; i += 8)
		*(volatile uint64_t *)(dst + i) = *(volatile uint64_t *)(src + i);
}

struct plog_hdr {
	uint32_t sig;
	uint32_t start;
	uint32_t size;
};

static void plog_reset(void)
{
	volatile struct plog_hdr *h = (volatile struct plog_hdr *)RAMOOPS_LOG_BASE;

	h->sig = RAMOOPS_SIG;
	h->start = 0;
	h->size = 0;
}

static void plog_putc(char c)
{
	volatile struct plog_hdr *h = (volatile struct plog_hdr *)RAMOOPS_LOG_BASE;
	volatile char *d = (volatile char *)(RAMOOPS_LOG_BASE + sizeof(*h));
	uint32_t at = h->start, size = h->size;

	if (h->sig != RAMOOPS_SIG || at >= RAMOOPS_LOG_SIZE - sizeof(*h) ||
	    size > RAMOOPS_LOG_SIZE - sizeof(*h)) {
		plog_reset();
		at = size = 0;
	}
	d[at] = c;
	if (++at == RAMOOPS_LOG_SIZE - sizeof(*h))
		at = 0;
	if (size < RAMOOPS_LOG_SIZE - sizeof(*h))
		size++;
	h->start = at;
	h->size = size;
}

static void plog_puts(const char *s)
{
	while (*s)
		plog_putc(*s++);
}

static void plog_hex(uint64_t v)
{
	static const char hex[] = "0123456789abcdef";
	char buf[19];
	int i;

	buf[0] = '0';
	buf[1] = 'x';
	for (i = 0; i < 16; i++)
		buf[2 + i] = hex[(v >> (60 - 4 * i)) & 0xf];
	buf[18] = 0;
	plog_puts(buf);
	plog_putc('\n');
}

static int has_request(void)
{
	volatile char *p = (volatile char *)RAMOOPS_REQ_BASE;
	const char *needle = REQUEST_STRING;
	uint32_t i;

	for (i = 0; i + 1 < RAMOOPS_REQ_SIZE; i++) {
		uint32_t j = 0;

		while (needle[j] && i + j < RAMOOPS_REQ_SIZE &&
		       p[i + j] == needle[j])
			j++;
		if (!needle[j])
			return 1;
	}
	return 0;
}

static void clear_request(void)
{
	volatile uint64_t *p = (volatile uint64_t *)RAMOOPS_REQ_BASE;
	uint32_t i;

	for (i = 0; i < RAMOOPS_REQ_SIZE; i += 8)
		p[i / 8] = 0;
}

static uint64_t copy_dtb(uint64_t dtb)
{
	volatile uint32_t *h = (volatile uint32_t *)dtb;
	uint32_t total = __builtin_bswap32(h[1]); /* FDT totalsize is big-endian */
	uint64_t n;

	if (total < 0x100 || total > DTB_COPY_MAX) {
		plog_puts("dtb: bad totalsize, passing LK's address\n");
		return dtb;
	}
	n = (total + 7) & ~7ULL;
	plog_puts("dtb: ");
	plog_hex(dtb);
	plog_puts(" -> ");
	plog_hex(DTB_COPY_PA);
	plog_puts(" size ");
	plog_hex(total);
	memcpy8(DTB_COPY_PA, dtb, n);
	return DTB_COPY_PA;
}

void chain_main(uint64_t dtb)
{
	uint64_t imglen, payload, stub_len;
	int req;

	plog_reset();
	plog_puts("mtkchain-begonia M1\n");
	plog_puts("log pmsg+0x0 request pmsg+0xf000\n");

	req = has_request();
	plog_puts(req ? "request: XNU\n" : "request: Linux\n");

	imglen = hdr64(0x28);
	payload = hdr64(0x30);
	plog_puts("linux image len: ");
	plog_hex(imglen);
	if (payload) {
		plog_puts("xnu payload at: ");
		plog_hex(payload);
	}

	if (req) {
		plog_puts("XNU requested; M1 dry-run, no XNU payload started\n");
		plog_puts("M2: mtkloader will load the XNU payload and the microSD xnusys image\n");
	}
	clear_request();

	if (!imglen) {
		plog_puts("no Linux Image in this boot image; halting\n");
		for (;;)
			__asm__ volatile("wfe");
	}

	dtb = copy_dtb(dtb);

	stub_len = (uint64_t)(chain_stub_end - chain_stub);
	plog_puts("stub: ");
	plog_hex(stub_len);
	memcpy8(STUB_PA, (uint64_t)chain_stub, (stub_len + 7) & ~7ULL);

	plog_puts("chaining Linux at 0x40080000\n");
	((void (*)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t))STUB_PA)
		(dtb, LINUX_ENTRY, (uint64_t)_start + CHAIN_OFFSET, imglen,
		 LINUX_ENTRY);

	for (;;)
		__asm__ volatile("wfe");
}
