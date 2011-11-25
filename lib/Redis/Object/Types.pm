package Redis::Object::Types;

=head1 NAME

Redis::Object::Types - Description

=head1 DESCRIPTION

Index types

=head1 SYNOPSIS

See L<Redis::Object>

=cut

use strict;

use version 0.74; our $VERSION = qv( "v0.1.0" );

use Moose::Util::TypeConstraints;


=head1 TYPES

=head2 StrIndexed

String type for arbitrary indexed strings.

    has attrib => ( isa => "StrIndexed", is => "rw", required => 1 );

=cut

subtype 'StrIndexed'
    => as 'Str';

=head2 StrIndexedSafe

Indexed String type, with constraints to assure/increase proability that it will not create
errors with Redis (StrIndexed is more loose, and you can save any value)

    has attrib => ( isa => "StrIndexedSafe", is => "rw", required => 1 );

=cut

subtype 'StrIndexedSafe'
    => as 'StrIndexed'
    => where {
        length( $_ ) <= 256
        && /^[A-Za-z0-9_-]+$/
    };

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

Same license as Perl itself.

=cut

1;