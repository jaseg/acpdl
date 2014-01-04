#!/usr/bin/perl -w
# Copyright © 2007-2013 Jamie Zawinski <jwz@jwz.org>
#
# Permission to use, copy, modify, distribute, and sell this software and its
# documentation for any purpose is hereby granted without fee, provided that
# the above copyright notice appear in all copies and that both that
# copyright notice and this permission notice appear in supporting
# documentation.  No representations are made about the suitability of this
# software for any purpose.  It is provided "as is" without express or 
# implied warranty.
#
# Keep only those ID3v2 frames that are deemed useful.  Delete all others.
#
# find ~/mp3/ -name '*.mp3' -mtime -90 -print0 | xargs -0 ~/www/hacks/id3-clean.pl -v
#
# Created: 21-Dec-2007.

require 5;
use diagnostics;
use strict;

use MP3::Tag;

my $progname = $0; $progname =~ s@.*/@@g;
my $version = q{ $Revision: 1.19 $ }; $version =~ s/^[^0-9]+([0-9.]+).*$/$1/;

my $verbose = 1;
my $debug_p = 0;

# These are the ID3v2 frame-types that we keep.
#
my %allowed_frames = (
   'APIC' => 1, # Attached picture
#  'COMM' => 1, # Comments (any language)
   'COMM_eng' => 1, # Comments (English only)
   'PIC'  => 1, # Attached picture (obsolete)
   'RVAD' => 1, # Relative volume adjustment
   'TALB' => 1, # Album/Movie/Show title
   'TBPM' => 1, # Beats per minute
   'TCMP' => 1, # Part of a compilation (iTunes extension)
   'TCOM' => 1, # Composer
   'TCON' => 1, # Content type (Genre)
   'TCP'  => 1, # Part of a compilation (iTunes extension, obsolete)
   'TIT2' => 1, # Title/songname/content description ("Name" in iTunes)
   'TKEY' => 1, # Initial key
   'TLEN' => 1, # Length (milliseconds)
   'TPE1' => 1, # Lead performers/Soloists ("Artist" in iTunes)
   'TPE2' => 1, # Band/orchestra/accompaniment ("Album Artist" in iTunes)
#  'TPOS' => 1, # Part of a set (e.g. disc N of M)
   'TRCK' => 1, # Track number/Position in set
   'TSRC' => 1, # ISRC (international standard recording code)
   'TYER' => 1, # Year
#  'USLT' => 1, # Unsychronized lyric/text transcription (any language)
   'USLT_eng' => 1, # Unsychronized lyric/text transcription (English only)
   );

# Anything not in %allowed_frames is deleted, but this table lets us
# distinguish between "known" and "unknown" deleted tags, for diagnostic
# purposes.
#
my %disallowed_frames = (
   'COMM_ID3v1' => 1, # Converted ID3v1 comment: duplicated in the real COMM.
   'CM1'  => 1, # Another kind of comment?
   'GEOB' => 1, # General encapsulated object (e.g. "RealJukebox:Metadata")
   'MCD'  => 1, # Music CD identifier
   'MCDI' => 1, # Music CD identifier
   'NCO'  => 1, # Uknown binary data (MusicMatch?)
   'NCON' => 1, # Uknown binary data (MusicMatch?)
   'PCNT' => 1, # Play counter
   'POPM' => 1, # Popularimeter (rating, not used by iTunes)
   'PRI'  => 1, # Unknown - some other volume normalization scheme maybe?
   'PRIV' => 1, # Private frame (e.g. amazon.com tracking watermark)
   'TCOP' => 1, # Copyright message
   'TDAT' => 1, # Recording date (DDMM)
   'TDEN' => 1, # Encoding time
   'TENC' => 1, # Encoded by
   'TEXT' => 1, # Lyricist/Text writer
   'TFLT' => 1, # File type (e.g., "audio/mp3" - duh)
   'TIME' => 1, # Recording time (HHMM)
   'TIT1' => 1, # Content group description (only seen as duplicate of TIT2?)
   'TIT3' => 1, # Subtitle/Description refinement (but usually e.g. "04:16"!)
   'TLAN' => 1, # Language
   'TMED' => 1, # Media type (e.g., digital)
   'TOPE' => 1, # Original artists/performers (goes in "TCOM" in iTunes)
   'TORY' => 1, # Original release year (I put this in TYER)
   'TPE3' => 1, # Conductor/performer refinement (unused in iTunes?)
   'TPE4' => 1, # Interpreted, remixed, modified by (goes in "TCOM" in iTunes)
   'TPOS' => 1, # Part of a set (e.g. disc N of M)
   'TPUB' => 1, # Publisher
   'TDRC' => 1, # Release date, maybe?
   'TDOR' => 1, # Release date, maybe?
   'TOWN' => 1, # File owner/licensee
   'TSIZ' => 1, # Size of file in bytes, minus ID3v2 tag - duh.
   'TSOP' => 1, # Band name? Sorting maybe?
   'TSSE' => 1, # Software/Hardware and settings used for encoding
   'TXXX' => 1, # User defined text information ("Ripping tool", "Source=CD")
   'UFID' => 1, # Unique file identifier (usually a URL)
   'USER' => 1, # Terms of use
   'WPUB' => 1, # Publishers official webpage
   'WCOM' => 1, # Commercial information (another URL)
   'WOAF' => 1, # Official audio file webpage
   'WOAR' => 1, # Official artist/performer webpage
   'WOAS' => 1, # Official audio source webpage
   'WXXX' => 1, # User defined URL link frame
   'XDOR' => 1, # Release date
   'XSOP' => 1, # Musicbrainz Sortname
   );


# I do not like having a million micro-genres in my collection.
# This table lets you rewrite one genre to a different one,
# e.g., let's just call "Independent Rock" "Rock".
#
# If you don't want that, comment out everything between {} here.
#
my %rewrite_genres = (
  'Classic Rock' 	=> 'Rock',
  'Dance'	 	=> 'Techno',
  'Grunge'		 => 'Rock',
  'Other'	 	=> 'Rock',
  'Pop'		 	=> 'Rock',
  'Rap'		 	=> 'Hip Hop',
  'Industrial'	 	=> 'Rock',
  'Alternative'	 	=> 'Rock',
  'Death Metal'	 	=> 'Metal',
  'Soundtrack'	 	=> 'Rock',
  'Ambient'		=> 'Techno',
  'Instrumental' 	=> 'Techno',
  'Noise'	 	=> 'Industrial',
  'AlternRock'	 	=> 'Rock',
  'Darkwave'		=> 'Gothic',
  'Techno-Industrial '	=> 'Industrial',
  'Electronic'	 	=> 'Techno',
  'Pop-Folk'		=> 'Folk',
  'Eurodance'	 	=> 'Techno',
  'Pop/Funk'		=> 'Rock',
  'Rock & Roll'	 	=> 'Rock',
  'Hard Rock'	 	=> 'Rock',
  'Folk-Rock'	 	=> 'Folk',
  'Gothic Rock'	 	=> 'Gothic',
  'Punk Rock'	 	=> 'Punk',
);


sub print_frame($$) {
  my ($id3v2, $frame) = @_;

  my $frame2 = $frame;
  $frame2 =~ s/^(.+)\d\d$/$1/s;

  my ($info, $name, @rest) = $id3v2->get_frame($frame);
  $name = '???' unless $name;
  print STDERR "\t$frame2 ($name) - ";
  if (ref $info) {
    print STDERR "\n";
    foreach my $k (keys %$info) {
      my $v = $$info{$k};
      if ($k =~ m/^_/s
          && $frame2 ne 'UFID'
          #&& $frame2 ne 'PRIV'
          && $frame2 ne 'MCDI'
         ) {
        $v = "<data>";
      } elsif ($frame2 eq 'USLT' && $k eq 'Text') {
        my @lines = split (/\n/, $v);
        my $n = $#lines+1;
        $v = "<$n lines>" if ($n > 1);
      }
      print STDERR sprintf("\t     %-18s - %s\n", $k, $v);
    }
    print STDERR "\n";
  } else {
    print STDERR "$info\n";
  }
}


sub id3clean($$$) {
  my ($file, $set_comp_p, $force_p) = @_;

  MP3::Tag->config (id3v23_unsync => 0);   # iTunes needs this.

  my $mp3 = MP3::Tag->new($file);
  if (! $mp3) {
    error ("$file is a directory") if (-d $file);
    error ("$file does not exist") unless (-f $file);
    error ("$file: no tags?");
  }

  $mp3->get_tags();
  my $id3v1 = $mp3->{ID3v1} if exists $mp3->{ID3v1};
  my $id3v2 = $mp3->{ID3v2} if exists $mp3->{ID3v2};

  # Allow writing of id3v2.4.  This is supposedly "not fully supported", but
  # I have no idea what that means, or what can go wrong.  Let's find out...
  $mp3->config (write_v24 => 1);

  my $changed_p = $force_p;

  if ($id3v1) {
    print STDERR "$progname: $file: deleted ID3v1 tag\n" if ($verbose > 2);
    $id3v1->remove_tag() unless ($debug_p);
    $changed_p++;
  }

  if (!$id3v2) {
    print STDERR "$progname: $file: no ID3v2 tag\n" if ($verbose > 2);
  } else {

    foreach my $frame (keys %{$id3v2->get_frame_ids()}) {

      my $frame2 = $frame;
      $frame2 =~ s/^(.+)\d\d$/$1/s;

      my ($info, $name, @rest) = $id3v2->get_frame($frame);

      error ("$file: can't read frame $frame") unless defined($info);

      # Mark converted ID3v1 comments differently.
      #
      if ($frame2 eq 'COMM' &&
          ref $info &&
          defined($info->{Description}) &&
          ($info->{Description} eq 'ID3v1 Comment' ||
           $info->{Description} eq 'CDDB Disc ID')) {
        $frame2 .= "_ID3v1";

      # If e.g. "USLT" is in %allowed_frames, always allow it.  Otherwise,
      # instead check for frame names like "USLT_eng", "USLT_spa", etc.
      #
      } elsif (!$allowed_frames{$frame2} &&
               ref $info && 
               defined($info->{Language})) {
        $frame2 .= "_" . $info->{Language};
      }

      if ($allowed_frames{$frame2} && $info ne '') {
        print STDERR "$progname: $file: $frame2 allowed\n" if ($verbose > 4);
        print_frame ($id3v2, $frame) if ($verbose > 5);

        # If the comment is an amazon.com watermark, remove it.
        #
        if ($frame2 =~ m/^COMM/s &&
            $info &&
            ($info->{Text} =~ m/Song ID:/si ||
             # Also nuke "Mixed In Key" comments.
             $info->{Text} =~ m@^[0-9][AB](/[0-9][AB])?$@s)) {
          print STDERR "$progname: $file: $frame2 removed ($info->{Text})\n"
            if ($verbose > 2);
          $id3v2->remove_frame($frame) if (! $debug_p);
          $changed_p++;

        # If "Artist" and "Album Artist" are the same, delete "Album Artist".
        # It's completely redundant.
        #
        } elsif ($frame2 eq 'TPE2') {
          if ($info eq $id3v2->get_frame('TPE1')) {

            print STDERR "$progname: $file: TPE1 == TPE2;" .
                         " deleting TPE2 (\"$info\")\n"
              if ($verbose > 2);
            $id3v2->remove_frame($frame) if (! $debug_p);
            $changed_p++;
          }
        }

      } else {
        my $kind = ($disallowed_frames{$frame2}
                    ? 'disallowed'
                    : ($info eq ''
                       ? 'null'
                       : 'unknown'));

        print STDERR "$progname: $file: $frame2 removed ($kind)\n"
          if ($verbose > 2);
        print_frame ($id3v2, $frame) 
          if ($verbose > ($kind eq 'unknown' ? 1 : 3));

        $id3v2->remove_frame($frame) if (! $debug_p);
        $changed_p++;
      }
    }

    # If there's an old PICnn tag, convert it to APICnn (ID3v2.3).
    #
    for (my $i = 0; $i < 10; $i++) {
      my $ff  = "PIC" . ($i == 0 ? "" : sprintf("%02d", $i));
      my $ff2 = "APIC";
      my ($info, $name, @rest) = $id3v2->get_frame($ff);
      if (defined($info)) {
        my $type = $$info{'Image Format'} || error ("$file: $ff: no type");
        my $data = $$info{'_Data'}        || error ("$file: $ff: no data");
        print STDERR "$progname: $file: converting $ff to $ff2\n" 
          if ($verbose > 2);
        if (! $debug_p) {
          $id3v2->add_frame($ff2, 0, $type, "\000", "", $data) ||
            error ("$file: add frame $ff2 failed");
          $id3v2->remove_frame($ff) ||
            error ("$file: remove frame $ff failed");
          $changed_p++;
        }
      }
    }

    # If there's an old TCP tag, convert it to TCMP (ID3v2.3).
    #
    {
      my $ff  = "TCP";
      my $ff2 = "TCMP";
      my ($info, $name, @rest) = $id3v2->get_frame($ff);
      if (defined($info)) {
        print STDERR "$progname: $file: converting $ff to $ff2 ($info)\n" 
          if ($verbose > 2);
        if (! $debug_p) {
          $id3v2->add_frame($ff2, $info) ||
            error ("$file: add frame $ff2 failed");
          $id3v2->remove_frame($ff) ||
            error ("$file: remove frame $ff failed");
          $changed_p++;
        }
      }
    }

    # If there's no TCMP tag, maybe add one.
    #
    if ($set_comp_p) {
      my $ff = "TCMP";
      my ($info, $name, @rest) = $id3v2->get_frame($ff);
      if (defined($info)) {
        print STDERR "$progname: $file: TCMP=$info already present\n"
          if ($verbose > 2);
      } else {
        print STDERR "$progname: $file: adding $ff frame\n" 
          if ($verbose > 2);
        if (! $debug_p) {
          $id3v2->add_frame($ff, "1") ||
            error ("$file: add frame $ff failed");
          $changed_p++;
        }
      }
    }

    # In ID3v1, "TCON" was a numeric genre number.
    # In ID3v2, it is either a string, or the genre number in parens.
    # Sometimes we need to convert it.  I don't know why.  Without
    # this, we start seeing numbers in iTunes instead of genre names.
    # E.g., "\00017\000" needs to be "(17)".
    {
      my $ff = "TCON";
      my ($raw) = $id3v2->get_frame($ff, 'raw');
      if (defined($raw) && $raw =~ m/^\000*(\d+)\000*$/s) {
        $raw = "($1)";
        if (! $debug_p) {
          $id3v2->change_frame ($ff, $raw) ||
            error ("$file: change frame $ff failed");
          print STDERR "$progname: $file: $ff updated $raw\n"
            if ($verbose > 4);
          $changed_p++;
        }
      }

      # Rewrite stupid genres to less-stupid genres.
      #
      my ($g) = $id3v2->get_frame($ff);
      if ($g) {
        my $g2 = $rewrite_genres{$g};
        if ($g2) {
          $id3v2->change_frame ($ff, $g2) ||
            error ("$file: change frame $ff failed");
          print STDERR "$progname: $file: $ff updated $g -> $g2\n"
            if ($verbose > 2);
          $changed_p++;
        }
      }
    }
  }

  if ($changed_p) {
    if ($debug_p) {
      print STDERR "$progname: not writing $file\n" if ($verbose);
    } else {
      if ($id3v2->write_tag(1)) {
        print STDERR "$progname: wrote $file\n" if ($verbose);
      } else {
        print STDERR "$progname: FAILED writing $file\n" if ($verbose);
      }
    }
  } elsif ($verbose > 3) {
    print STDERR "$progname: $file unchanged\n";
  }

}


sub error($) {
  my ($err) = @_;
  print STDERR "$progname: $err\n";
  exit 1;
}

sub usage() {
  print STDERR "usage: $progname [--verbose] [--quiet] [--debug] [--force] [--set-compilation] mp3-files ...\n";
  exit 1;
}

sub main() {
  my @files = ();
  my $set_comp_p = 0;
  my $force_p = 0;
  while ($#ARGV >= 0) {
    $_ = shift @ARGV;
    if ($_ eq "--verbose")   { $verbose++; }
    elsif (m/^-v+$/)         { $verbose += length($_)-1; }
    elsif (m/^--?q(uiet)?$/) { $verbose = 0; }
    elsif (m/^--?debug$/)    { $debug_p++; }
    elsif (m/^--?force$/)    { $force_p++; }
    elsif (m/^--?set-comp(ilation)?$/) { $set_comp_p++; }
    elsif (m/^-./)           { usage; }
    else                     { push @files, $_; }
  }
  usage unless ($#files >= 0);
  foreach my $file (@files) { 
    @_ =
      eval {
        id3clean ($file, $set_comp_p, $force_p);
      };
    if ($@) {
      print STDERR "$progname: $file: ERROR: $@\n";
    }
  }
}

main();
exit 0;
