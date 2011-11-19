package TestDB::TestTable1;

use Moose;
with qw/ Redis::Object::Table /;

use version 0.74; our $VERSION = qv( "v0.1.0" );

has attr_str => ( isa => 'Str', is => 'rw', required => 1 );
has attr_int => ( isa => 'Int', is => 'rw', required => 1 );
has attr_hash => ( isa => 'HashRef', is => 'rw', required => 1 );

1;