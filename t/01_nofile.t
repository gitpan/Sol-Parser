#!perl -T

#   $Id: 01_nofile.t 32 2007-12-19 13:25:33Z aff $

use warnings;
use strict;

use Test::More tests => 3;
use lib qw( lib );

use Sol::Parser;
ok(1);

# test missing or undefined filename
eval { Sol::Parser::parse(); };
like($@, qr/missing argument file/i, q{parse should die when file is missing});

# test filename that does not exist
eval { Sol::Parser::parse(q{/hey_they_cannot_possibly_have_a_file_named_like_this}); };
like($@, qr/no such file/i, q{parse should die when file is missing});

__END__

