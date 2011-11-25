package TestDB::TestTable1;

use Moose;
with qw/ Redis::Object::Table /;

has attr_str => ( isa => 'Str', is => 'rw', required => 1 );
has attr_int => ( isa => 'Int', is => 'rw', required => 1 );
has attr_hash => ( isa => 'HashRef', is => 'rw', required => 1 );

__PACKAGE__->meta->make_immutable;

1;