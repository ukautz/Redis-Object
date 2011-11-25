package Redis::Object::SearchResult;

=head1 NAME

Redis::Object::SearchResult - Search result for Redis search

=head1 DESCRIPTION

Result of a search performed on a Redis database over which can be iterated.

=head1 DYNAMIC RESULT

Keep in mind, that a Redis::Object::SearchResult has to be viewed as a "dynamic filter", rather than a "fixed set". Iterating twice the same result can lead to different results. Simply put: don't do it.

=head1 SYNOPSIS

See L<Redis::Object>

=cut

use Moose;

use version 0.74; our $VERSION = qv( "v0.1.1" );

use Carp qw/ croak /;

=head1 ATTRIBUTES

=head2 table

The table searching on

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

# original search, needed for reset
has _search => ( isa => 'ArrayRef', is => 'rw', required => 1, default => sub { [] } );

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
    if ( $self->_has_subset && $self->_subset ) {
        
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
    return $_ = $item;
}

=head2 all

Returns all found items as an array.

=cut

sub all {
    my ( $self ) = @_;
    my @all;
    while( my $item = $self->next ) {
        push @all, $item;
    }
    return @all;
}

=head2 reset

Reset to first position. Keep in mind, that a search result could have been changed in between, so iterating a second time can result in a different set of items.

    while( my $item = $result->next ) {
        # ..
    }
    $result->reset;
    whiel( my $item = $result->next ) {
        # ..
    }

=cut

sub reset {
    my ( $self ) = @_;
    my $class = ref $self;
    my $meta = $class->meta;
    my $new_search = $self->_super->search( $self->table, @{ $self->_search } );
    foreach my $attrib( $meta->get_attribute_list ) {
        $self->{ $attrib } = $new_search->$attrib();
    }
    return $self;
}

=head2 update_all $update_ref

Update all items in the result

    my $result = $db->search( TableName => { .. } );
    $result->update_all( { attrib_name => $value } );

I<You need to reset the result afterwards, if you want to iterate over it again!>

=head3 $update_ref

A hashref containing the data for update

=cut

sub update_all {
    my ( $self, $update_ref ) = @_;
    return $self unless $update_ref;
    while( my $item = $self->next ) {
        $item->update( $update_ref );
    }
    return $self;
}

=head2 remove_all

Delete all items in the result set.

Read the note about dynamic L<search results|Redis::Object::SearchResult/"DYNAMIC RESULT">.

=cut

sub remove_all {
    my ( $self ) = @_;
    while( my $item = $self->next ) {
        $item->remove;
    }
    return $self;
}



=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

Same license as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;