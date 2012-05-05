/*
 *  linux/boot/head.S
 *
 *  Copyright (C) 1991, 1992, 1993  Linus Torvalds
 */

/*
 *  head.S contains the 32-bit startup code.
 *
 * NOTE!!! Startup happens at absolute address 0x00001000, which is also where
 * the page directory will exist. The startup code will be overwritten by
 * the page directory. [According to comments etc elsewhere on a compressed
 * kernel it will end up at 0x1000 + 1Mb I hope so as I assume this. - AC]
 *
 * Page 0 is deliberately kept safe, since System Management Mode code in
 * laptops may need to access the BIOS data stored there.  This is also
 * useful for future device drivers that either access the BIOS via VM86
 * mode.
 */

/*
 * High loaded stuff by Hans Lermen & Werner Almesberger, Feb. 1996
 */
	.text

#include <linux/init.h>
#include <linux/linkage.h>
#include <asm/segment.h>
#include <asm/page_types.h>
#include <asm/boot.h>
#include <asm/asm-offsets.h>

	__HEAD
//#define __HEAD		.section	".head.text","ax"
ENTRY(startup_32)
	cld
	/*
	 * Test KEEP_SEGMENTS flag to see if the bootloader is asking
	 * us to not reload segments
	 */
	testb	$(1<<6), BP_loadflags(%esi)
//#define BP_loadflags 529 /* offsetof(struct boot_params, hdr.loadflags)
	jnz	1f

	cli
	movl	$__BOOT_DS, %eax
	movl	%eax, %ds
	movl	%eax, %es
	movl	%eax, %fs
	movl	%eax, %gs
	movl	%eax, %ss
1:

/*
 * Calculate the delta between where we were compiled to run
 * at and where we were actually loaded at.  This can only be done
 * with a short local call on x86.  Nothing  else will tell us what
 * address we are running at.  The reserved chunk of the real-mode
 * data at 0x1e4 (defined as a scratch field) are used as the stack
 * for this calculation. Only 4 bytes are needed.
 */
	leal	(BP_scratch+4)(%esi), %esp  //nice. 用boot params结构中的4个字节当临时栈。
	call	1f
1:	popl	%ebp
	subl	$1b, %ebp

/*
 * %ebp contains the address we are loaded at by the boot loader and %ebx
 * contains the address where we should move the kernel image temporarily
 * for safe in-place decompression.
 */

#ifdef CONFIG_RELOCATABLE  //yes. we defined!
	movl	%ebp, %ebx  // %ebp=1M, 最好去bochs里验证下
	movl	BP_kernel_alignment(%esi), %eax  //BP_kernel_alignment(%esi) = 0x1000000 = 16M
//#define CONFIG_PHYSICAL_ALIGN 0x1000000
	decl	%eax
	addl    %eax, %ebx
	notl	%eax
	andl    %eax, %ebx  //对齐操作  a= (a+align-1) & ~(align-1)
//hacklu.这里想当然了，以为eax仅仅是个对齐。没想到偏移了这么多。。。。。。
//%ebx = 0x1000000 = 16m!!!!!
#else
	movl	$LOAD_PHYSICAL_ADDR, %ebx
// LOAD_PHYSICAL_ADDR=0x1000000=16M
#endif

	/* Target address to relocate to for decompression */
	addl	$z_extract_offset, %ebx //z_extract_offset 是后面mkpiggy计算出来的。ld的时候才能确定
//这次的 z_extract_offset 0x003fb000 = 4076k

	/* Set up the stack */
	leal	boot_stack_end(%ebx), %esp //我猜拼接的时候后面留了空隙当栈 ,这的栈放在bss段，bss链接的时候放在最后

	/* Zero EFLAGS */
	pushl	$0
	popfl

/*
 * Copy the compressed kernel to the end of our buffer
 * where decompression in place becomes safe.
 */
//%ebp boot 加载内核到这里  1m
//%ebx 压缩的内核要移动到这里 16m+z_extract_offset 
	pushl	%esi
	leal	(_bss-4)(%ebp), %esi
	leal	(_bss-4)(%ebx), %edi
	movl	$(_bss - startup_32), %ecx
	shrl	$2, %ecx
	std
	rep	movsl  //std DF=1. 字符串操作的index递减。即si di是递减的。
//hacklu? 不明白这里为什么从后面开始移动？？
	cld
	popl	%esi

/*
 * Jump to the relocated address.
 */
	leal	relocated(%ebx), %eax
	jmp	*%eax
ENDPROC(startup_32)

	.text
relocated:

/*
 * Clear BSS (stack is currently empty)
 */
	xorl	%eax, %eax
	leal	_bss(%ebx), %edi
	leal	_ebss(%ebx), %ecx
	subl	%edi, %ecx
	shrl	$2, %ecx
	rep	stosl

/*
 * Adjust our own GOT
 */
	leal	_got(%ebx), %edx
	leal	_egot(%ebx), %ecx
1:
	cmpl	%ecx, %edx
	jae	2f
	addl	%ebx, (%edx)  //.got 都是指针，相对偏移量，加上起始地址%ebx即可
	addl	$4, %edx
	jmp	1b
2:

/*
 * Do the decompression, and jump to the new kernel..
 */
	leal	z_extract_offset_negative(%ebx), %ebp
//hacklu, %ebp = 16m ;bochs 验证之
				/* push arguments for decompress_kernel: */
	pushl	%ebp		/* output address */
	pushl	$z_input_len	/* input_len */
//也是后面计算出来的 z_input_len 0x003dc6eb = 3953k
	leal	input_data(%ebx), %eax
//input_data=0x6c find in piggy.S,0x6c是从反汇编的结果中刚看出来。我猜是因为head_32.S的.head.text编译完刚好长0x6c ;是的，猜对了
	pushl	%eax		/* input_data */
	leal	boot_heap(%ebx), %eax
	pushl	%eax		/* heap area */
	pushl	%esi		/* real mode pointer */
	call	decompress_kernel
	addl	$20, %esp

#if CONFIG_RELOCATABLE
/*
 * Find the address of the relocations.
 */
	leal	z_output_len(%ebp), %edi

/*
 * Calculate the delta between where vmlinux was compiled to run
 * and where it was actually loaded.
 */
	movl	%ebp, %ebx
	subl	$LOAD_PHYSICAL_ADDR, %ebx //LOAD_PHYSICAL_ADDR=16m
	jz	2f	/* Nothing to be done if loaded at compiled addr. */
/*
 * Process relocations.
 */
//hacklu?  不懂
1:	subl	$4, %edi
	movl	(%edi), %ecx
	testl	%ecx, %ecx
	jz	2f
	addl	%ebx, -__PAGE_OFFSET(%ebx, %ecx) // addl %ebx, -0xc0000000(%ebx,%ecx)
	jmp	1b
2:
#endif

/*
 * Jump to the decompressed kernel.
 */
	xorl	%ebx, %ebx
	jmp	*%ebp

/*
 * Stack and heap for uncompression
 */
	.bss
	.balign 4
boot_heap:
	.fill BOOT_HEAP_SIZE, 1, 0
boot_stack:
	.fill BOOT_STACK_SIZE, 1, 0
boot_stack_end:
