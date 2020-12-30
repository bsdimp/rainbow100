# $FreeBSD$

PROG?=	pboot
STRIP=
MAN=
BINMODE=${NOBINMODE}
SRCS=	${PROG}.S
ORG=0x1000
CLEANFILES+=pboot.out

# Note: much of this taken from FreeBSD's boot0
CFLAGS=-m32 -ffreestanding -mno-mmx -mno-sse -msoft-float -march=i386 -no-integrated-as
LDFLAGS+=${LDFLAGS_BIN}
# compact binary with no padding between text, data, bss
LDSCRIPT=	boot.ldscript
LDFLAGS_ORG=	-Wl,--defsym,ORG=${ORG},-T,${LDSCRIPT}
LDFLAGS_BIN=	-e start ${LDFLAGS_ORG} -Wl,-N,-S,--oformat,binary -nostdlib

all: ${PROG} ${PROG}.out
pboot.out:	${PROG}
	@ls -l pboot
	dd if=pboot of=pboot.out bs=512 conv=sync
	# make sure that we assemnble correctly: clang 8 integrated as doesn't
	-objdump -D -m i386 -M i8088,addr16,data16 -b binary pboot | grep code

.include <bsd.prog.mk>
