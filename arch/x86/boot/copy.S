/* ----------------------------------------------------------------------- *
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *
 *   This file is part of the Linux kernel, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

#include <linux/linkage.h>

/*
 * Memory copy routines
 */

	.code16gcc
	.text

GLOBAL(memcpy)
	pushw	%si
	pushw	%di
	movw	%ax, %di
	movw	%dx, %si
	pushw	%cx
	shrw	$2, %cx
	rep; movsl //move 4 byte from [ds:si] to [es:di]
	popw	%cx
	andw	$3, %cx
	rep; movsb
	popw	%di
	popw	%si
	ret
ENDPROC(memcpy)

GLOBAL(memset)
	pushw	%di
	movw	%ax, %di
	movzbl	%dl, %eax
	imull	$0x01010101,%eax  //hacklu.   扩展字节用的。传进来的参数可能是1个字节的。比如0xff。这样可以使eax为0xfffffffffff。方便下面4字节传
	pushw	%cx
	shrw	$2, %cx
	rep; stosl //store 4 byte from EAX to [es:di]
	popw	%cx
	andw	$3, %cx
	rep; stosb
	popw	%di
	ret
ENDPROC(memset)

GLOBAL(copy_from_fs)
	pushw	%ds
	pushw	%fs
	popw	%ds
	call	memcpy
	popw	%ds
	ret
ENDPROC(copy_from_fs)

GLOBAL(copy_to_fs)
	pushw	%es
	pushw	%fs
	popw	%es
	call	memcpy
	popw	%es
	ret
ENDPROC(copy_to_fs)

#if 0 /* Not currently used, but can be enabled as needed */
GLOBAL(copy_from_gs)
	pushw	%ds
	pushw	%gs
	popw	%ds
	call	memcpy
	popw	%ds
	ret
ENDPROC(copy_from_gs)

GLOBAL(copy_to_gs)
	pushw	%es
	pushw	%gs
	popw	%es
	call	memcpy
	popw	%es
	ret
ENDPROC(copy_to_gs)
#endif
