#   $Id: Makefile.PL 30 2007-12-19 10:25:30Z aff $

use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME          => 'Sol::Parser',
  VERSION       => 0.01,
  AUTHOR        => 'Andreas Faafeng <aff@cpan.org>',
  VERSION_FROM  => 'lib/Sol/Parser.pm',
  ABSTRACT_FROM => 'lib/Sol/Parser.pm',
  PL_FILES      => {},
  PREREQ_PM     => {
    'File::Find'        => 0,
    'Test::More'        => 0,
    'Test::Differences' => 0,
    'Log::Log4perl'     => 0,
  },
  dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
  clean => { FILES    => 'Sol-Parser-*' },
);
