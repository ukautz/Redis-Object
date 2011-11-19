package TestDB;

use Moose;
extends qw/ Redis::Object /;

use version 0.74; our $VERSION = qv( "v0.1.0" );

has tables => ( is => 'rw', isa => 'ArrayRef[Str]', default => sub { [ qw/
    TestTable1
    TestTable2
/ ] } );

__PACKAGE__->meta->make_immutable;

1;