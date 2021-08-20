# $FreeBSD$

PROG?=	univdrv
STRIP=
MAN=
BINMODE=${NOBINMODE}
SRCS=	${PROG}.S
ORG=0x980
CLEANFILES+=${PROG}.out
MK_PIE:= no

# Note: much of this taken from FreeBSD's boot0
CFLAGS=-m32 -ffreestanding -mno-mmx -mno-sse -msoft-float -march=i386
LDFLAGS+=${LDFLAGS_BIN}
# compact binary with no padding between text, data, bss
LDSCRIPT=	boot.ldscript
LDFLAGS_ORG=	-Wl,--defsym,ORG=${ORG},-T,${LDSCRIPT}
LDFLAGS_BIN=	-e start ${LDFLAGS_ORG} -Wl,-N,-S,--oformat,binary -nostdlib
LDFLAGS.lld+=	-Wl,--no-rosegment

all: ${PROG} ${PROG}.out
${PROG}.out:	${PROG}
	@ls -l univdrv
	dd if=univdrv of=univdrv.out bs=512 conv=sync
	# make sure that we assemnble correctly: clang 8 integrated as doesn't
	-objdump -D -m i386 -M i8088,addr16,data16 -b binary univdrv | grep code
	-objdump -D -m i386 -M i8088,addr16,data16 -b binary ../univ211.bin > old
	-objdump -D -m i386 -M i8088,addr16,data16 -b binary univdrv > new
	-diff -u old new > fred

.include <bsd.prog.mk>
