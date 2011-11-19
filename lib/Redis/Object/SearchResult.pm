package Redis::Object::SearchResult;

=head1 NAME

Redis::Object::SearchResult - Search result for Redis search

=head1 DESCRIPTION

Result of a search performed on a Redis database

=head1 SYNOPSIS

    See L<Redis::Object>

=cut

use Moose;

use version 0.74; our $VERSION = qv( "v0.1.0" );

use Carp qw/ croak /;

=head1 ATTRIBUTES

=head2 table

The tale searching on

=cut

has table => ( isa => 'Str', is => 'rw', required => 1 );

=head2 position

The current position, starting at 0.

=cut

has position => ( isa => 'Int', is => 'rw', default => -1 );

# whether performing and search or not
has _and_search => ( isa => 'Bool', is => 'rw', default => 1 );

# filters to search
has _filter => ( isa => 'ArrayRef[CodeRef]', is => 'rw', default => 0 );

# references Redis::Object
has _super => ( isa => 'Redis::Object', is => 'rw', required => 1, weak_ref => 1 );

# possible subset searching on
has _subset => ( isa => 'ArrayRef[Int]', is => 'rw', predicate => '_has_subset' );

=head1 METHODS

=head2 next

Returns the next item in the subset or undef

=cut

sub next {
    my ( $self ) = @_;
    
    # increment position
    $self->position( $self->position + 1 );
    my $position = $self->position();
    
    my @filter = @{ $self->_filter };
    my $ok_req = $self->_and_search
        ? scalar @filter
        : 1;
    
    # using subset
    my $item;
    if ( $self->_has_subset ) {
        
        # whether last
        my $size = scalar @{ $self->_subset };
        return undef if $position >= $size;
        
        # get item by id
        $item = $self->_super->find( $self->table, $self->_subset->[ $position ] );
    }
    
    # using table scan
    else {
        
        # last
        return undef if $position >= $self->_super->_current_id( $self->table );
        
        # get item
        $item = $self->_super->find( $self->table, $position );
    }
    
    # no item found, get next
    return $self->next() unless $item;
    
    # perform filter search, if any
    if ( $ok_req ) {
        my $ok = 0;
        my $filter;
        while( $ok < $ok_req && defined( $filter = shift @filter ) ) {
            $ok++ if $filter->( $item );
        }
        
        # not found
        return $self->next()
            if $ok < $ok_req;
    }
    
    # return the found item
    return $item;
}

=head2 all

Returns all found items as an array

=cut

sub all {
    my ( $self ) = @_;
    my @all;
    while( my $item = $self->next ) {
        push @all, $item;
    }
    return @all;
}

=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

Same license as Perl itself.

=cut

1;