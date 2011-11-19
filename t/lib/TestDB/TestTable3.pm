package TestDB::TestTable3;

use Moose;
with qw/ Redis::Object::Table /;

use version 0.74; our $VERSION = qv( "v0.1.0" );

has regular => ( isa => 'StrIndexed', is => 'rw', required => 1 );
has safe    => ( isa => 'StrIndexedSafe', is => 'rw', required => 1 );

__PACKAGE__->meta->make_immutable;

1;