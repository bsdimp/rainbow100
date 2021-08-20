# Recovered Univation driver

I recovered this off the image I was able to take of the badly broken (but not
completely broken) hard disk that was attached to the univation controller I got
off ebay.

univ211.bin contains the driver. It's patched into the io.sys file on the
Rainbow version of MS-DOS 2.11. It is patched using the patch.211 script
that's also included.

To date, this is the only driver I've been able to find for the Univation
controller. This controller seems tobe a Xebec design that was warmed over for
the Rainbow's data bus. It's a SASI design, and the hard drive I got came with
the Adaptec ACB-4000A adapter card, with what appeared to be stock firmware.
Page 68 of http://bitsavers.org/pdf/xebec/104524C_S1410Man_Aug83.pdf has the
basics of the design. Appendix B has the basic routines to access it, and
there's some evidence of transliteration into 8088 assembler from this
code/pseudo-code. I'm working on a KiCad schematic as well, but it needs a bit
more work than I've completed.

A disassembled driver that I think is mostly working can be found in
univdisk.asm, but it uses AT&T syntax, not Intel/MASM. It's been mostly
reconstructed, but isn't 100% identical yet. There was a newer version,
as evidenced from .o files, but I can't find it now.
