package Redis::Object::Table;

=head1 NAME

Redis::Object::Table - Base class for Redis::Object tables

=head1 DESCRIPTION

Base class for all tables.

=head1 SYNOPSIS

See L<Redis::Object>

=cut

use Moose::Role;

use version 0.74; our $VERSION = qv( "v0.1.0" );


=head1 ATTRIBUTES

=head1 id

Every item has an "id" field. Do not overwrite it

=cut

has id => ( isa => 'Int', is => 'rw' );

# references schema, extending Redis::Object
has _super => ( is => 'ro', required => 1, weak_ref => 1 );

# name of the table
has _table_name => ( is => 'rw', isa => 'Str', predicate => '_has_table_name' );


=head1 METHODS

=head2 update [$attr_ref]

Commit all changes in the object to Redis

=head3 $attr_ref

Optional hash of ( attribname => value )

=cut

sub update {
    my ( $self, $attr_ref ) = @_;
    
    # set atttributes
    if ( $attr_ref ) {
        $self->$_( $attr_ref->{ $_ } ) for keys %$attr_ref;
    }
    
    # write via super handler
    $self->_super->update( $self );
}

=head2 increment $attrib_name, [$amount]

Increment an attribute.

=head3 $attrib_name

Name of the attribute to increment

=head3 $amount

Optional amount, defaults to 1

=cut

sub increment {
    my ( $self, $attrib_name, $amount ) = @_;
    $amount ||= 1;
    my $redis = $self->_super->_redis;
    my $keyname = $self->_keyname( $attrib_name );
    $self->$attrib_name( $redis->incr( $keyname, $amount ) );
}

=head2 remove

Remove the item from the database

=cut

sub remove {
    my ( $self ) = @_;
    return $self->_super->remove( $self );
}

=head2 table_name

Returns the table name

=cut

sub table_name {
    my ( $self ) = @_;
    return $self->_table_name if $self->_has_table_name;
    ( my $name = ref( $self ) ) =~ s/.*:://;
    $self->_table_name( $name );
    return $name;
}

sub _keyname {
    my ( $self, $attrib ) = @_;
    return $self->_super->_keyname(
        $self->table_name,
        $self->id,
        $attrib
    );
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

Same license as Perl itself.

=cut

1;