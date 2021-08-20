# Univation

## Fido News

       Volume 2, Number 46                         30 December 1985
       +----------------------------------------------------------+
       |                                             _            |
       |                                            /  \          |
       |    - Fidonews -                           /|oo \         |
       |                                          (_|  /_)        |
       |  Fido and Fidonet                         _`@/_ \    _   |
       |    Users  Group                          |     | \   \\  |
       |     Newsletter                           | (*) |  \   )) |
       |                             ______       |__U__| /  \//  |
       |                            / FIDO \       _//|| _\   /   |
       |                           (________)     (_/(_|(____/    |
       |                                                (jm)      |
       +----------------------------------------------------------+

       Publisher:                                          Fido 1/1
       Editor in Chief:                              Thom Henderson
       Review Editor:                                  Allen Miller
       Chief Procrastinator Emeritus:                  Tom Jennings


       Fidonews                   Page 13               30 Dec 1985
                               Rainbow Corner
                           by Theodore Needleman

    Univation, Inc.  (1037 N.  Fair Oaks Avenue, Sunnyvale, CA 94089, phone
    408-745-0180) offers a variety of products for the Rainbow including RAM
    memory, fixed and removable hard disks, and an Ethernet LAN controller.  Not
    only are their prices very reasonable, but their Ethernet board can be
    piggybacked over the hard disk controller.

    Their hard disk controllers, whether for the fixed or the removable hard
    drives, all contain at least 64K of additional RAM, and can be obtained with
    up to 448K of RAM.  While this doesn't solve the problem of the HD
    controller/Comm Board slot contention that Phil asked about, it does show
    that Univation is concerned about providing the most expansion capability
    for a machine with a limited amount of expansion slots, and I commend them
    for their efforts.

       (c)opyright 1985 by Ted Needleman-all rights reserved

## mopd

I think a remnant of this controller is in mopd because Univation registered
with DEC so it could have images that were loaded via MOP.
```
./common/nma.c:	{ NMA_C_SOFD_UEC, "UEC", "Univation/RAINBOW-100" },
./common/nmadef.h:#define   NMA_C_SOFD_UEC   31	/* Univation/RAINBOW-100 */
```
So that you could net-boot your Rainbow... Not sure where these came from,
but the nmadef.h name suggests they were lifed from a VMS header file...

## Computerworld, December 10, 1984, page 124

NETS
(cont from page 123)
UNIVATION, INC.
Rainbow LAN Controller

Univation, Inc. has released a controller board that links Digital Equipment
Corp. Rainbow microcomputers into a local-area network.

Users connect the Local-Area Network Controller (LAN Controller) to the
Rainbow's transceiver device, then hook into Ethernet with a standard Ethernet
cable, according to Univation.

Network Research Corp. in Santa Monica, Calif., provides Fusion, the Xerox
Corp. Memory Systems (XMS) protocol software needed to impplement the network, a
spokesman said.

LAN Controller features reportedly include buffer management with three receive
packets and one transmit packet, four 8-bit data channels and loop-back for test
diagnostics.

The cost of the Rainbow LAN Controller is $750. Fusion software carries an
additional $750 price tag.

Univation, 1037 N. Fairoaks Ave., Sunnyvale, Calif. 94089.

## Computerworld, December 17, 1984, page 9

Communications tools in spotlight at Dexpo West '85
...

* A Univation, Inc. controller board that is said to permit DEC Rainbow personal
  computers to be tied together to form full-fledged local networks.

## Speculation

From: http://www.os2museum.com/wp/emulating-etherlink/

    When I started writing the 3C501 emulation, I assumed the card was a design
    from 1986 or 1987. That turned out to be both right and wrong. The 3C501,
    also known as IE-4, was indeed introduced approximately in 1986. However,
    several mentions of “3C500/3C501” piqued my curiosity. What’s a 3C500?

    The 3C500 was 3Com’s original IBM Ethernet (IE) adapter, introduced in
    October 1982, certainly one of the first PC Ethernet adapters, if not the
    very first one.

    The 3C500 (IE) was also nearly identical to the newer 3C501 (IE-4), and
    software written for the 3C500 should work on a 3C501. How do I know the IE
    and IE-4 are almost the same? Because their technical references are nearly
    identical, word for word.

    The 3C500 is so old that finding any information about it (besides that
    technical reference) is nearly impossible. My current assumption is that the
    biggest difference between IE and IE-4 is that the latter replaced a large
    number of discrete chips with a custom ASIC.

    In 1983, a group at MIT (led by Prof. Saltzer of Multics fame) developed one
    of the first TCP/IP based networking packages for the IBM PC. It supported
    one Ethernet card, the 3Com EtherLink. The package was called PC/IP and
    later turned into FTP Software’s PC/TCP. Surviving source archives of PC/IP
    from 1985 and 1986 are available.

    And a few months before PC/IP was started, the EtherLink was the hardware
    component of 3Com’s EtherSeries (1982), an Ethernet-based hardware and
    software package providing electronic mail, disk sharing, and more.

    In other words, the 3C501/3C500 is very, very old.

So the 3C501 design dates early enough. Let's read on:

    The EtherLink is built around the SEEQ 8001 EDLC (Ethernet Data Link
    Controller) which handles all Ethernet specifics. 3Com added a 2KB packet
    buffer and circuitry required for interfacing the EDLC with an IBM PC. The
    SEEQ 8001 appears to have been developed by SEEQ for and with 3Com; both
    companies were linked through Silicon Valley venture capital firms.

    The EtherLink is an 8-bit card (of course) which requires a 16-byte I/O port
    range, one interrupt, and optionally a DMA channel.

    The packet buffer is not mapped in the PC’s memory. It can be accessed
    through a one-byte window mapped in the I/O port range, or via DMA. Old
    drivers and drivers designed to run on a PC or PC/XT tend to use DMA,
    because it is faster than reading or writing the I/O port in a loop by a
    rather slow CPU. Drivers designed to run on a PC/AT tend to use string I/O
    instructions (insb and outsb) available on a 286 because those are faster
    than DMA and much easier to use.

So the 3C501 was aweful, and the 3C500 was worse. Let's look at the PC/TCP
archives referenced. They have code to support this card (and only this
card). And the code looks a bit like later drivers, and doesn't mention the name
of this card. At January 1985 to the PC/TCP snapshot, date is good. The 3C500
evidentally had a crapton of TTL logic and was hard to fit in a 16-bit fill
length slot which is why there's an ASIC in the 3C501 (according to comments).

So the SEEQ DQ8001 may have been the only game in town end of '84, start of
'85. I've not checked the PDP-11 ethernet cards that date from the time,
though. 2.9BSD has no networking support (Nov 83) and 2.10BSD has networking
(for the vax) and dates from 87. 4.2BSD from 83 has if_ec (3com which seems to
loosely match the 8001 datasheet), if_il (Interlan) that's something I don't
recognize. Ultrix (and later 4.3BSD) had if_qe, derived from the IL driver
in 84, so that's early enough. Surviving pictures suggest that this is based
around custom DEC gear.

https://www.3comstory.com/gallery?pgid=jpa4g60u-e6c4595a-882b-4365-a2ac-3a93e1c42eac

is a photo of the card, and it looks a lot like the DEC hard disk controller,
which puts it into the running for 'possible to do'. It's only a bit larger than
the Univation Disk controller drive. The jumpers for the different addresses
wouldn't be needed and with external drivers (or maybe only thin-net support),
it's within the realm of the possible.

Sadly, so far I've found no articles similar to the ones I found for the
Univation disk controller with extensive details on how to install / setup the
card. Based on the description this may be another card taht uses the memory
card interface with the 'chip select' jumpers so that it can do direct DMA. The
mismatch between the press release (4 packets) and the descriptions of the 3C501
having only room for one packet may be due to it using 4k or 8k RAM to buffer
the recieve. Univation favored simpler designs, so who knows, but it does have
DMA channels which only went to the hard disk / advanced communications
board. Maybe it piggy backed off *THAT*? Unknown based on the vague
descriptions...

So I might be able to create a speculative ethernet interface for the Rainbow in
emulation, but without an extant Univation Ethernet driver, it's going to be a
bit hard to test and/or prove short of porting a Unix that supports TCP/IP to
the Rainbow.

# DEC

Washington Area Rainbow Users Group Newsletter
November/December, 1986
Volume 3 No 11-12

Pages 6-7:
30. Rainbow LAN without the need for a VAX.

Answer: RB PCSA will provide the capability; you can use a VAXmate as the
server.

31. Direct Ethernet Access for the Rainbow; i.e., a board that plugs directly
into the Rainbow that doesn't preclude the use of a hard disk.

Answer: PCSA integreation kits will provide this.

32. VT220 and VT240 emulation software.

Answer: Will be provided with in the PCSA emulation kit.

Pages 8-9:

From WARUG's reporting of a DECUS Q&A session

Q: Is the "Mouse" on the Rainbow going to go into the Serial Port or a special
"Mouse" port?`

A: The "Mouse" will be built into the Ethernet Card

Q: Will the Ethernet card be available unbundled?

A: No, currently the plan is to offer a bundled package, although if customer
demand is strong enough for unbundling, we will look at that.

Q: Where is theEthernet Card going to fit?

A: First, the Ethernet Card will work only in a B, not an A, because the power
supply and memory space are too small. First, you take out your winchester board
and memory board , then take the Ethenret Card and plug into both ports and
replace both winchester and memory cards, back on top.

Q: If you have an 8087 does this preclude the use of this card?

A: No, it doesn't preclude that. What you do, if you bought that neat little
board there [presumably the 8081 adapter card], there are two ways that we are
looking at it right now, one is that the board will plug back on top, then the
other board will plug on top of that, and I'm not sure if that is gonna work,
because there's not much room in there. The other one is that they are gonna put
the 8087 space on the network board and you'll unplug the 8081 from the cute
board that you spent a lot of money on and plug the 8087 into the new board with
the other one.

