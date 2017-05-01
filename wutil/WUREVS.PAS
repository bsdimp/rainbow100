const HeaderString = 'RAINBOW 100 WINCHESTER DISK UTILITY Version 3.2';

{ REVISION HISTORY (NEWEST TO OLDEST)

  VERSION       DATE            DESCRIPTION

  3.2           08 Aug 1989     Added code to make WUTIL compatible with the
                                latest release B of MS-DOS version 3.10.  This
                                code adjusts for the different BIOS segment.
                                ---
                01 May 1989     Added VENIX/Rainbow to the list of operating
                                system.
                                ---                                      --VE--
  3.12          12 Apr 1989     Fixed a bug which caused WUTIL to not start
                                on the Rainbow A under certain circumstances.
                                ---
                05 Apr 1989     Added the RETURN key to the secondary boot
                                loader code as an equivalent to DO and
                                keypad ENTER.                            --VE--
                                ---
  3.11          31 Jan 1989     Fixed a bug which caused V3.1 to hang under
                                MSDOS V2.11.  I used an undocumented DOS
                                call in WUTIL V3.1 to find the list of 
                                installed device drivers.  But then I simply
                                forgot to check if this undocumented DOS
                                call worked the same under MS-DOS V3.10 and
                                V2.11, which it didn't.                  --VE--
                                ---
  3.1           16 Dec 1988     Added support for the CHS dual winchester
                                controller.  While in the main menu the
                                CTRL-SHIFT-SELECT key combination now toggles
                                between physical drive 1 and 2.  All options
                                selected from the main menu will then be
                                applied to the currently selected drive.
                                NOTE: The CHS driver for the second drive must
                                be loaded to enable WUTIL to access the 2nd
                                drive.                                   --VE--
                                ---
                05 Nov 1988     Added code to write the number of FAT sec-
                                tors of an MS-DOS partition into the appro-
                                priate location of the DPD block.        --VE--
                                ---
                01 Nov 1988     During repartitioning, if WUTIL was supposed 
                                to leave a partition unchanged and this par-
                                tition happened to be one of an operating sys-
                                tem unknown to WUTIL (VENIX in this case),
                                WUTIL replaced its name in the DPD block with
                                a null string.  Changed this so the old name
                                will be kept with the partition.         --VE--
                                ---
  3.0           26 Oct 1988     Finally received permission from the original
                                author of WUTIL, Tony Camas, to distribute
                                the new version.  Since there are so many
                                changes in this version vs. version 2.0
                                I figured it deserves the version number to
                                be bumped to 3.0 instead of 2.1.         --VE--
                                ---
  2.1.03        17 Oct 1988     by Vinzenz Esser:
  *************************     Fixed a bug in the Print Screen routine which
  *   DO NOT DISTRIBUTE   *     caused the last three screen lines not to be
  *************************     printed, if the Rainbow is running on 50Hz.
                                ---
                                Added 'Total Tracks' column to display of
                                current hard disk status.
                                ---
                                Added support of the CTRL key to the reparti-
                                tioning option.  CTRL LEFT/RIGHT ARROW now
                                decreases/increases the partition size in
                                100 track increments.
                                ---
                                When in the 'Dump Sector' option pressing the
                                LEFT/RIGHT ARROWs together with both the SHIFT
                                and CTRL keys at the same time will increment/
                                decrement the track number in 100 track incre-
                                ments.
                                ---
                                In the 'Dump Sector' option it is no longer
                                possible to increment the track number beyond
                                the last actual data track of your hard disk.
                                The last actual data track is considered to be
                                the last logical track before the manufacturing
                                cylinder, which usually is the last cylinder
                                on the disk.
                                ---
                                When entering information about an individual
                                disk drive it is no longer possible to enter
                                specifications, which are beyond the Rainbow's
                                capabilities:  number of cylinders can not
                                exceed 1024, number of heads can not exceed 8.
                                ---
  2.1.02        12 Oct 1988     by Vinzenz Esser:
  *************************     Added RD32/ST251 (40MB) support.
  *   DO NOT DISTRIBUTE   *     ---
  *************************     A very common reason for getting the error
                                message 'CAN'T FIND WINCHESTER INTERRUPT SERVICE
                                IN MS-DOS' when starting WUTIL is having a TSR
                                program installed which took over the winchester
                                interrupt vector.  To make the user aware of
                                that a message has been added to the error
                                display.
                                ---
                                Changed the sequence of operating systems the
                                SELECT key cycles through so that MS-DOS comes
                                before CP/M now.  I did this for two reasons:
                                If an MS-DOS partition is supposed to be added
                                from the unallocated tracks being >1024 tracks
                                the INSERT key first allocates all those tracks
                                to a GAP.  With CP/M being the next possible
                                choice the number of tracks would be shrinked
                                to 1024, since that's the maximum size for a
                                CP/M partition.  Pressing SELECT again to make
                                this partition an MS-DOS partition would leave
                                the size at 1024 and the user would have to
                                (SHIFT)LEFT-ARROW back to the desired size.
                                With MS-DOS being the first choice a lot of
                                keystrokes can be saved here.  And then mostly
                                MS-DOS partitions are created nowadays anyways.
                                ---
  2.1.01        10 Oct 1988     by Vinzenz Esser:
  *************************     A few changes to make WUTIL compatible with the
  *   DO NOT DISTRIBUTE   *     final release of MS-DOS V3.10:
  *************************     ---                                
                                Added check for 'COM1' and 'LPT1' in the chain
                                of installed device drivers.  The check is
                                implemented in such a way that we remain back-
                                wards compatible with older MS-DOS releases.
                                ---                                
                                Added check for the presence of code which has
                                been added to the hard disk driver.  This code,
                                which is supposed to prevent a program from
                                accessing a non-existent MS-DOS partition, pre-
                                vents WUTIL from reading the hard disks home
                                block.  If our check finds this code we patch
                                in a JMP instruction to skip over this piece of
                                code.  Actually we are using the result of the
                                check for the 'COM1' and 'LPT1' device driver
                                to determine if the patch is necessary, since
                                the additional device drivers and the additio-
                                nal code in the hard disk driver have been im-
                                plemented with the same version of MS-DOS (i.e
                                V3.10 including test versions 3.10.017 and up).
                                If we patch the driver, naturally we'll remove
                                the patch, when we exit from WUTIL.
                                ---
                                Since partition sizes of 1025, 1026, or 1027
                                tracks for an MS-DOS partition can cause a hell
                                of a problem we need to make sure that par-
                                titions with these sizes can not be created.
                                ===============================================
  2.0           13 August 1986  Many changes and new features, described below:
                                ---
                                In partitioning, logical units are now assigned
                                to CP/M and CCP/M as a unit (CP/M first, then
                                CCP/M) and the total number of partitions
                                allowed is four total for the two operating
                                systems.  This is because CCP/M evidentally
                                also accesses CP/M partitions, which we didn't
                                know.
                                ---
                28 July 1986    When we added code in version 1.1 to bypass
                                formatting of manufacturer tracks if they are
                                readable, we meant well...but it didn't work.
                                If there is manufacturer data in these tracks,
                                it is written using 256-byte sectors; therefore
                                reads would fail and the tracks would be
                                formatted anyway.  A future version will read
                                these correctly...in the mean time, we now
                                no longer format these tracks at all.
                                ---
                23 July 1986    The AutoBoot flag in the HOM block should be
                                set to $FF when there is no auto boot, not to
                                zero.  Fix the code to do it right.
                                ---
                                We are now providing our own PREBOOT and
                                SECBOOT loaders, so the patching code in
                                the format/initialize function has been
                                removed.
                                ---
                20 July 1986    Add main menu function to copy boot loaders
                                (PREBOOT and SECBOOT) to hard disk (only).
                                ---
                                Format/initialize function now attempts to
                                close all files before exiting with MAIN SCREEN
                                key (avoid running out of file handles on
                                future calls).
                                ---
                06 July 1986    It appears that MS-DOS does not like partitions
                                of exactly 32MB.  The maximum was decreased by
                                one track so there would be no problem.
                                ---
                                Add room for another digit in partition size
                                display (in display disk info code).  Also
                                removed "init" column from this display as all
                                partitions always show up as initialized.
                                ---
                                Another modification to allow WUTIL to work
                                under the "latest" version of 3.1. (.013)
                                ---
                30 June 1986    Revamped O/S checking in partitioning code
                                and improved minimum/maximum checks.  Then
                                implemented 16-bit FAT feature in MS-DOS
                                version 3.x by allowing MS-DOS partitions
                                to be up to 32MB in version 3.x.  Then
                                modified FormatMSDOSPartition to use 16-bit
                                FATs if the partition is bigger than 8MB.
                                ---
                29 June 1986    General disk info output now always prints
                                512 bytes/sector and 16 sectors/track, since
                                we refuse to handle anything else anyway.
                                Printing these always is faster than looking
                                up these numbers in the home block, of course.
                                ---
                                Conversion of tracks to megabytes performed
                                in various places was done without use of
                                floating values in the correct places; the
                                result was overflows for larger values which
                                displayed negative values.
                                ---
                26 June 1986    Minor change to FindHDRoutines so it will
                                not object when run under version 3.x of
                                MS-DOS.  Whether everything else works,
                                however, remains to be tested.
                                ---
                                Increased limit of tracks from 5000 to 15000,
                                making the capacity of WUTIL now something
                                like 117MB.  Also made this value a changeable
                                constant, so that next time it is changed, it
                                will be easy.  The new constant is called
                                "TrackLimit" and is distributed as 14999.  -AGC

  1.1           25 June 1986    Corrected an extremely nasty typo which could
                                be responsible for several "flaky" problems.
                                Somewhere during the development of the most
                                recent version (1.0), the calculation of
                                the number of AST blocks required on a disk was
                                moved into a subroutine used by several pieces
                                of code.  This procedure, unfortunately, had
                                the number 250 where the number 100 should have
                                been, and thus always vastly undercalculated
                                the size of the AST area.  Nasty, nasty.
                                ---
                                With much grumbling and under extreme protest,
                                the algorithm which decides where to place
                                the various control blocks in the formatting
                                code has been more or less completely
                                redesigned so that it always puts the DPD and
                                OSN blocks in track 0, sectors 3 and 4,
                                respectively.  Why?  Because, much to our
                                chagrin, we found out that much system software
                                produced for the rainbow pays no attention to
                                where the HOM block says these things are and
                                just looks for them in those specific places.
                                Thus, WUTIL was creating disks that confused
                                many system utilities like LDCOPY, et al.
                                Turns out that the resulting algorithm is
                                actually generally smarter, though, so maybe
                                it was a good idea after all.  The new
                                algorithm ought to be able to handle disks
                                bigger than 5000 tracks, too, though this is
                                yet to be tested (and certain global data
                                areas have to be made bigger to accomodate
                                that).
                                ---
                                When formatting a disk, if the track being
                                formatted is in the manufacturer's cylinder,
                                WUTIL now tries to read the first sector of
                                the track first and only formats it if this
                                read fails; i.e., we now try to avoid writing
                                over manufacturer data if it's there.  -AGC

  1.0           16 June 1986    FORMAL RELEASE!  -AGC

  BETA-0.9E     15 June 1986    Sort DPD entries by starting track number after
                                the DPD block is read in ReadMajorBlocks.
                                This solves yet another CHS compatibility
                                problem; CHS evidentally puts out these
                                entries in any old order, which fools the
                                partition editor into thinking there are
                                gaps all over the place that don't really exist.
                                ---
                                For disks with 8 surfaces, DEC's PREBOOT and
                                SECBOOT loaders do not work.  WUTIL will now
                                try to patch them when writing them onto the
                                disk so that they have the correct number of
                                surfaces value.                         -AGC

  BETA-0.9D     13 June 1986    Several changes to try and deal with disks
                                formatted by the popular CHS formatter, which
                                appears to not write valid BAT data and which
                                null-pads instead of space-pads operating
                                system names in the OSN block.  WUTIL will now
                                attempt to continue if there is something
                                wrong with the BAT or AST areas, either on read
                                or on write.  It also transforms null-padded
                                operating system names into space-padded ones.
                                                                        -AGC

  BETA-0.9C     09 June 1986    Added speed/reliability options to formatting
                                function.  Now there is a 4-item submenu to
                                select the extent to which formatting should
                                be done.
                                ---
                                The "all ones" bit pattern written during
                                double-verify formatting was silly because
                                that's the data that's left there by the
                                "format track" call.  Replaced this with
                                a pattern of (mostly) alternating ones and
                                zeroes.
                                ---
                                Modified menu handling procedure to display
                                message that MAIN SCREEN key is allowed if
                                it is.
                                ---
                                MAIN SCREEN key now available in the "enter
                                your own disk information" screen of the
                                formatting function.
                                ---
                                Sector dump function no longer calls
                                ReadMajorBlocks since only the data in the HOM
                                block is nominally required.  In fact, if the
                                HOM block read fails, it will still try to
                                work and assume that the disk has 4 heads. -AGC

  BETA-0.9B     06 June 1986    Modified logic in Initialize procedure so that
                                FindISRFlag is only called with the second
                                (newer) vector if the old one fails to pan out.
                                TURBO evidentally does not automatically do
                                this when an OR appears; result was that
                                ISRSeg was left with the wrong value on a
                                100A, and this caused FindHDData to fail.  -AGC

  BETA-0.9      23 May 1986     First complete release for beta test. -AGC
}
