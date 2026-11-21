/*
 * mtkchain-begonia: minimal chain loader for the Xiaomi Redmi Note 8 Pro
 * (begonia, MT6785).  Placed by tools/chainboot.py in front of the Linux
 * arm64 Image in an Android boot image (header v2).  LK decompresses the
 * boot image kernel to 0x40080000 and enters it with x0 = LK's device tree;
 * this code reads a request from the reserved ramoops pmsg zone, writes its
 * log to the ramoops console zone, then copies the Linux Image down to
 * 0x40080000 and starts it as LK would.
 *
 * Derived from oosexgang/hakios-mt6768 (MIT): the arm64 Image header and
 * chain_stub are the same mechanism used by its mtkloader.
 */
	.section .text.boot
	.global _start
	.global chain_stub
	.global chain_stub_end

_start:
	/* Linux arm64 Image header (64 bytes).  chainboot.py fills res2
	 * (offset 0x28, Linux Image length) and res3 (0x30, XNU payload
	 * offset, 0 when absent).  res4 (0x38) is unused. */
	b	primary_entry
	.word	0
	.quad	0x80000			/* text_offset */
	.quad	0x02000000		/* image_size (chainboot adjusts) */
	.quad	0x0a			/* flags: LE, 4K pages, anywhere */
	.quad	0			/* res2: Linux Image length */
	.quad	0			/* res3: XNU payload offset */
	.quad	0			/* res4 */
	.ascii	"ARM\x64"
	.word	0

primary_entry:
	msr	daifset, #0xf
	mov	x19, x0			/* LK's device tree */

	/* stack just below the load address; clear BSS */
	adr	x0, _start
	sub	x0, x0, #0x8000
	mov	sp, x0
	ldr	x0, =__bss_start
	ldr	x1, =__bss_end
1:	cmp	x0, x1
	b.ge	2f
	str	xzr, [x0], #8
	b	1b
2:	mov	x0, x19
	bl	chain_main
3:	wfe
	b	3b

/*
 * chain_stub(dtb, dst, src, len, entry): copy len bytes src -> dst, then
 * enter entry with x0 = dtb.  Position independent: chain_main copies it
 * above the Linux Image before the Image overwrites this program.
 */
chain_stub:
1:	ldr	x6, [x2], #8
	str	x6, [x1], #8
	subs	x3, x3, #8
	b.hi	1b
	dsb	sy
	ic	iallu
	dsb	sy
	isb
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	br	x4
chain_stub_end:
