package Sol::Parser;

#   $Id: Parser.pm 33 2007-12-19 13:28:28Z aff $

use strict;
use warnings;

our $VERSION = '0.01';

use Log::Log4perl;

use constant LENGTH_OF_FLOAT   => 8;
use constant LENGTH_OF_INTEGER => 2;
use constant LENGTH_OF_LONG    => 4;
use constant END_OF_OBJECT     => "\x00\x00\x09";

my $conf = q(
  log4perl.category.sol.parser             = WARN, ScreenAppender
  log4perl.appender.ScreenAppender         = Log::Log4perl::Appender::Screen
  log4perl.appender.ScreenAppender.stderr  = 0
  log4perl.appender.ScreenAppender.layout  = PatternLayout
  log4perl.appender.ScreenAppender.layout.ConversionPattern=[%p] %d %M:%L  %m%n
);
Log::Log4perl::init( \$conf );
my $log  = Log::Log4perl::->get_logger(q(sol.parser));

my $file = undef;
my $FH   = undef;

my %datatype = (
                0x0 => 'number',
                0x1 => 'boolean',
                0x2 => 'string',
                0x3 => 'object',
                0x5 => 'null',
                0x6 => 'undefined',
                0x8 => 'array',
                0xa => 'raw-array',
                0xb => 'object-date',
                0xd => 'object-string-number-boolean-textformat',
                0xf => 'object-xml',
                0x10 => 'object-customclass',
               );

#  Parse and return type and value as list.
#  Expects to be called in list context.
sub _getTypeAndValue {

  $log->logdie("expected to be called in LIST context") if !wantarray();

  # Read data type
  my $value = undef;
  my $type = _getBytes(1);
  my $type_as_txt = $datatype{$type};
  if (!exists($datatype{$type})) {
    $log->warn(qq{Missing datatype for '$type'!}) if $log->is_warn();
  }

  # Read element depending on type
  if($type == 0) {
    $value =  _getFloat();
  } elsif($type == 1){
    $value =  _getBytes(1);
  } elsif ($type == 2) {
    $value =  _getString();
  } elsif($type == 3){
    $value =  _getObject();
  } elsif($type == 5) {   # null
    $value = undef;
  } elsif($type == 6) {   # undef
    $value = undef;
  } elsif($type == 8){    # array
    $value = _getArray();
  } elsif($type == 0xb){  # date
    $log->logdie("Not implemented yet: date");
  } elsif($type == 0xf){  # doublestring
    $log->logdie("Not implemented yet: doublestring");
  } elsif($type == 0x10){ # customclass
    $value = _getObject(1);
  } else {
    $log->logdie("Unknown type:$type" );
  }

  return ($type_as_txt, $value);
}

# Parse object and return contents as comma separated string. If
# customClass argument is given then read two strings instead of one.
sub _getObject {
  my $customClass = shift;
  my @retvals = ();
  while (eof($FH) != 1) {
    # Read until end flag is detected : 00 00 09
    if (_getraw(3) eq END_OF_OBJECT) {
      return join(q{,}, @retvals);
    }

    # "un-read" the 3 bytes
    seek($FH, -3, 1) or $log->logdie("seek failed");

    # Read name
    my $name = _getString();
    $log->debug(qq{name:$name}) if $log->is_debug();

    # Read 2nd name if customClass is set
    if ($customClass) {
      push @retvals, q{class_name=} . $name . q{;};
      my $name = _getString();
      $log->debug(qq{name:$name (2nd name - customClass)}) if $log->is_debug();
      $customClass = 0;
    }

    # Get data type and value
    my ($type, $value) = _getTypeAndValue();
    $log->debug(qq{type:$type value:$value}) if $log->is_debug();

    push @retvals, $name . q{;} . $value;
  }
  $log->logdie("Syntax error: reached end-of-file before end-of-object");
}

# Parse array and return contents as comma separated string.
sub _getArray {
  my @retvals = ();
  my $count = _getlong();
  if($count == 0) {
    return _getObject();
  }

 ELEMENT:
  while ($count-- > 0) {
    my $name = _getString();

    if (!defined($name)) {
      last ELEMENT;
    }

    my $retval = undef;
    my ($type, $value) = _getTypeAndValue();
    {
      no warnings q{uninitialized}; # allow undef values
      $log->debug(qq{$name;$type;$value}) if $log->is_debug();
      $retval = qq{$name;$type;$value};
    }
    push @retvals, $retval;
  }

  # Now expect END_OF_OBJECT tag to be next
  if (_getraw(3) eq END_OF_OBJECT) {
    return join(q{,}, @retvals);
  }

  $log->error(q{Did not find expected END_OF_OBJECT! at end of array!}) if $log->is_error();
  return;
}

# Parse and return a given number of bytes (unformatted)
sub _getraw {
  my $len = shift;
  $log->logdie("missing length argument") unless $len;
  my $buffer = undef;
  my $num = read($FH, $buffer, $len);
  return $buffer;
}

# Parse and return a given number of bytes (as singed char)
sub _getBytes {
  my $len = shift || 1;
  my $buffer = undef;
  my $num = read($FH, $buffer, $len);
  return unpack("c*", $buffer);
}

# Parse and return a string: The first 2 bytes contains the string
# length, succeeded by the string itself. Read length first unless
# length is given, otherwise read the given number of bytes.
sub _getString {
  my $len = shift;
  my $buffer = undef;
  my $num = undef;

  # read length from filehandle unless set
  $len = join(q{}, _getBytes(2)) unless ($len);

  # return undef if length is zero
  return unless $len;

  $log->debug(qq{len:$len}) if $log->is_debug();
  $num = read($FH, $buffer, $len);
  $log->debug(qq{buffer:$buffer}) if $log->is_debug();
  return $buffer;
}

# Parse and return integer number, default 2 bytes
sub _getint {
  my $len = shift || LENGTH_OF_INTEGER;
  my $buffer = undef;
  my $num = read($FH, $buffer, $len);
  return unpack 'c*', reverse $buffer;
}

# Parse and return long integer number, default 4 bytes
sub _getlong {
  my $len = shift || LENGTH_OF_LONG;
  my $buffer = undef;
  my $num = read($FH, $buffer, $len);
  return unpack 'c*', reverse $buffer;
}

# Parse and return floating point number: default 8 bytes
sub _getFloat {
  my $len = shift || LENGTH_OF_FLOAT;
  my $buffer = undef;
  my $num = read($FH, $buffer, $len);
  return unpack 'd*', reverse $buffer;
}

# Parse and return file header - 16 bytes in total. Return name if
# file starts with sol header, otherwise undef.  Failure means the
# 'TCSO' tag is missing.
sub _readHeader {

  # skip first 6 bytes
  _getString(6);

  # next 4 bytes should contain 'TSCO' tag
  if (_getString(4) ne q{TCSO}) {
    $log->error("missing TCSO - not a sol file") if $log->is_error();
    return; # failure
  }

  # Skip next 7 bytes
  _getString(7);

  # Read next byte (length of name) + the name
  my $name = _getString(_getint(1));

  $log->debug("name:$name") if $log->is_debug();

  # Skip next 4 bytes
  _getString(4);

  return $name; # ok
}

# Parse and return an element, in the format "name;datatype;value"
sub _readElement {
  my $retval = undef;

  # Read element length and name
  my $name = _getString(_getint(2));

  # Read data type and value
  my ($type, $value) = _getTypeAndValue();
  {
    no warnings q{uninitialized}; # allow undef values
    $log->info(qq{$name;$type;$value}) if $log->is_info();
    $retval = qq{$name;$type;$value};
  }

  # Read trailer (single byte)
  my $trailer = _getBytes(1);
  if ($trailer != 0) {
    $log->warn(qq{Expected 00 trailer, got '$trailer'}) if $log->is_warn();
  }

  return $retval;
}

# parse file and return contents as a list
sub parse {
  my $file = shift;

  $log->logdie( q{Missing argument file.}) if (!$file);
  $log->logdie(qq{No such file '$file'})  if (! -f $file);

  $log->debug("start") if $log->is_debug();

  open($FH,"< $file") || $log->logdie("Error opening file $file");
  $log->debug(qq{file:$file}) if $log->is_debug();
  binmode($FH);

  my @retvals = ();

  # Read header
  my $name = _readHeader() or $log->logdie("Invalid sol header");
  push @retvals, $name;

  # Read data elements
  while (eof($FH) != 1) {
    push @retvals, _readElement();
  }

  close($FH) or $log->logdie(q{failed to close filehandle!});

  return @retvals;
}

1;

__END__

=pod

=head1 NAME

Sol::Parser - a .sol file reader

=head1 SYNOPSIS

  use Sol::Parser;
  my @content = Sol::Parser::parse("settings.sol");
  print join("\n", @content);

=head1 DESCRIPTION

Local Shared Object (LSO), sometimes known as flash cookies, is a
cookie-like data entity used by Adobe Flash Player.  LSOs are stored
as files on the local file system with the I<.sol> extension.  This
module reads a Local Shared Object file and return content as a list.

=head1 SOL DATA FORMAT

The SOL files use a binary encoding.  It consists of a header and any
number of elements.  Both header and the elements have variable lengths.

=head2 Header

The header has the following structure:

=over

=item * 6 bytes (discarded)

=item * 4 bytes that should contain the string 'TSCO'

=item * 7 bytes (discarded)

=item * 1 byte that signifies the length of name (X bytes)

=item * X bytes name

=item * 4 bytes (discarded)

=back

=head2 Element

Each element has the following structure:

=over

=item * 2 bytes length of element name (Y bytes)

=item * Y bytes element name

=item * 1 byte data type

=item * Z bytes data (depending on the data type)

=item * 1 byte trailer

=back

=head1 TODO

=head2 Support I<XML> output

=head2 Add support for datatypes I<date> and I<doublestring>.

=head1 BUGS

Please report any bugs or feature requests to C<bug-sol-parser at
rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Sol-Parser>.  I will
be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

  perldoc Sol::Parser

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Sol-Parser>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Sol-Parser>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Sol-Parser>

=item * Search CPAN

L<http://search.cpan.org/dist/Sol-Parser>

=back

=head1 SEE ALSO

=head2 Local Shared Object

http://en.wikipedia.org/wiki/Local_Shared_Object

=head2 Flash coders Wiki doc on .Sol File Format

http://sourceforge.net/docman/?group_id=131628

=head1 ALTERNATIVE IMPLEMENTATIONS

http://www.sephiroth.it/python/solreader.php (PHP, by Alessandro
Crugnola)

http://osflash.org/s2x (Python, by Aral Balkan)

=head1 COPYRIGHT & LICENSE

Copyright 2007 Andreas Faafeng, all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


