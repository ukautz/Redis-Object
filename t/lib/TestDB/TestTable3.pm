package TestDB::TestTable3;

use Moose;
with qw/ Redis::Object::Table /;

has regular => ( isa => 'StrIndexed', is => 'rw', required => 1 );
has safe    => ( isa => 'StrIndexedSafe', is => 'rw', required => 1 );

__PACKAGE__->meta->make_immutable;

1;