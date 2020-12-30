# $FreeBSD$

PROG?=	pboot
STRIP=
MAN=
BINMODE=${NOBINMODE}
SRCS=	${PROG}.S
ORG=0x1000

CFLAGS=-m32 -ffreestanding -mno-mmx -mno-sse -msoft-float -march=i386
LDFLAGS+=${LDFLAGS_BIN}
# compact binary with no padding between text, data, bss
LDSCRIPT=	boot.ldscript
LDFLAGS_ORG=	-Wl,--defsym,ORG=${ORG},-T,${LDSCRIPT}
LDFLAGS_BIN=	-e start ${LDFLAGS_ORG} -Wl,-N,-S,--oformat,binary -nostdlib

CC=gcc

.include <bsd.prog.mk>
