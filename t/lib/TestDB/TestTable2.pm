package TestDB::TestTable2;

use Moose;
with qw/ Redis::Object::Table /;

use version 0.74; our $VERSION = qv( "v0.1.0" );

sub INDEX_ATTRIBUTES { qw/ attr_str / }

has attr_str => ( isa => 'Str', is => 'rw', required => 1 );
has attr_int => ( isa => 'Int', is => 'rw', required => 1 );
has attr_hash => ( isa => 'HashRef', is => 'rw', required => 1 );


1;