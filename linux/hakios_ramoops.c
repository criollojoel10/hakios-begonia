// SPDX-License-Identifier: GPL-2.0
/*
 * hakios_ramoops: expose begonia's reserved ramoops region to Linux when
 * CONFIG_PSTORE_CONSOLE/PMSG are off.
 *
 * The bootloader command line reserves:
 *   ramoops.mem_address=0x4d010000 mem_size=0xe0000
 *   console_size=0x40000 pmsg_size=0x10000
 *
 * mtkchain-begonia writes its log at 0x4d09f000 (console) and reads the
 * request at 0x4d0e0000 (pmsg).  This misc device maps the whole 0xe0000
 * region; userspace reads the console at offset 0x8f000 and writes the
 * request at 0xd0000.  tools/capture-boot-log.sh and tools/request-xnu.sh
 * use it.  The region is reserved RAM, so the kernel allocator does not
 * touch it; a warm reset keeps it for the next loader session.
 */
#include <linux/fs.h>
#include <linux/io.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/uaccess.h>

#define HAKIOS_RAMOOPS_BASE 0x4d010000UL
#define HAKIOS_RAMOOPS_SIZE 0xe0000UL

static void *ramoops_mem;
static void __iomem *ramoops_io;

static ssize_t hakios_ramoops_read(struct file *file, char __user *buf,
				   size_t count, loff_t *ppos)
{
	size_t n;
	void *tmp;
	int ret;

	if (*ppos < 0 || *ppos >= HAKIOS_RAMOOPS_SIZE)
		return 0;
	n = min_t(size_t, count, HAKIOS_RAMOOPS_SIZE - *ppos);
	if (!n)
		return 0;

	if (ramoops_mem)
		return simple_read_from_buffer(buf, n, ppos, ramoops_mem,
					       HAKIOS_RAMOOPS_SIZE);

	tmp = kmalloc(n, GFP_KERNEL);
	if (!tmp)
		return -ENOMEM;
	memcpy_fromio(tmp, ramoops_io + *ppos, n);
	ret = copy_to_user(buf, tmp, n);
	kfree(tmp);
	if (ret)
		return -EFAULT;
	*ppos += n;
	return n;
}

static ssize_t hakios_ramoops_write(struct file *file, const char __user *buf,
				    size_t count, loff_t *ppos)
{
	size_t n;
	void *tmp;
	int ret;

	if (*ppos < 0 || *ppos >= HAKIOS_RAMOOPS_SIZE)
		return -ENOSPC;
	n = min_t(size_t, count, HAKIOS_RAMOOPS_SIZE - *ppos);
	if (!n)
		return 0;

	if (ramoops_mem)
		return simple_write_to_buffer(ramoops_mem, HAKIOS_RAMOOPS_SIZE,
					      ppos, buf, n);

	tmp = kmalloc(n, GFP_KERNEL);
	if (!tmp)
		return -ENOMEM;
	ret = copy_from_user(tmp, buf, n);
	if (ret) {
		kfree(tmp);
		return -EFAULT;
	}
	memcpy_toio(ramoops_io + *ppos, tmp, n);
	kfree(tmp);
	*ppos += n;
	return n;
}

static loff_t hakios_ramoops_llseek(struct file *file, loff_t off, int whence)
{
	return fixed_size_llseek(file, off, whence, HAKIOS_RAMOOPS_SIZE);
}

static const struct file_operations hakios_ramoops_fops = {
	.owner = THIS_MODULE,
	.read = hakios_ramoops_read,
	.write = hakios_ramoops_write,
	.llseek = hakios_ramoops_llseek,
};

static struct miscdevice hakios_ramoops_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "hakios-ramoops",
	.fops = &hakios_ramoops_fops,
	.mode = 0600,
};

static int __init hakios_ramoops_init(void)
{
	int ret;

	ramoops_mem = memremap(HAKIOS_RAMOOPS_BASE, HAKIOS_RAMOOPS_SIZE,
			       MEMREMAP_WB);
	if (!ramoops_mem)
		ramoops_io = ioremap(HAKIOS_RAMOOPS_BASE, HAKIOS_RAMOOPS_SIZE);
	if (!ramoops_mem && !ramoops_io)
		return -ENOMEM;

	ret = misc_register(&hakios_ramoops_dev);
	if (ret) {
		if (ramoops_mem)
			memunmap(ramoops_mem);
		else
			iounmap(ramoops_io);
		return ret;
	}
	pr_info("hakios-ramoops: %#lx..%#lx at /dev/%s\n",
		HAKIOS_RAMOOPS_BASE,
		HAKIOS_RAMOOPS_BASE + HAKIOS_RAMOOPS_SIZE - 1,
		hakios_ramoops_dev.name);
	return 0;
}

static void __exit hakios_ramoops_exit(void)
{
	misc_deregister(&hakios_ramoops_dev);
	if (ramoops_mem)
		memunmap(ramoops_mem);
	else
		iounmap(ramoops_io);
}

module_init(hakios_ramoops_init);
module_exit(hakios_ramoops_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("HakiOS begonia ramoops console/pmsg access");
MODULE_AUTHOR("HakiOS begonia contributors");
