package TestDB;

use Moose;
extends qw/ Redis::Object /;

has tables => ( is => 'rw', isa => 'ArrayRef[Str]', default => sub { [ qw/
    TestTable1
    TestTable2
    TestTable3
/ ] } );

__PACKAGE__->meta->make_immutable;

1;