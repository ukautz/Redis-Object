package Redis::Object;

=head1 NAME

Redis::Object - Use Redis with an ORMish interface

=head1 DESCRIPTION

Implements a scaled down ORM-like interface to access Redis as a database. If you want to use Redis as a cache, use L<Redis> instead.

=head1 SYNOPSIS

    package MyRedisDatabase;
    
    use Moose;
    extends qw/ Redis::Object /;
    
    has tables => ( isa => 'ArrayRef[Str]', is => 'ro', default => sub { [ qw/
        SomeTable
    / ] } );
    
    package MyRedisDatabase::SomeTable;
    
    use Moose;
    extends / Redis::Object::Table /;
    
    has attrib1 => ( isa => 'Str', is => 'rw', default => 'Something' );
    has attrib2 => ( isa => 'Int', is => 'rw' );
    has attrib3 => ( isa => 'HashRef', is => 'rw' );
    has attrib4 => ( isa => 'ArrayRef', is => 'rw' );
    
    # init database
    my $db = MyRedisDatabase->new(
        server => '127.0.0.1:6379'
    );
    
    # create item
    my $item = $db->create( SomeTable => {
        attrib1 => "Hello",
        attrib2 => 123,
        attrib3 => { something => "serializeable" },
        attrib4 => [ 1..99 ]
    } );
    print "Created ". $item->id;
    
    # fetch item by id
    my $item = $db->find( SomeTable => $id );
    print $item->attrib1. "\n";
    
    # search items
    my $result = $db->search( SomeTable => {
        attrib1 => "Hello",
        attrib2 => 123
    } );
    while( my $item = $result->next ) {
        print "Found ". $item->id. "\n";
    }
    
    # update item
    $item->attrib1( "bla" );
    $db->update( $item, {
        attrib2 => 333
    } );
    
    # update multiple items
    $db->update( \@items, {
        attrib3 => { yadda => "yadda" }
    } );

=head1 YOU SHOULD KNOW

=head2 Searching / Sorting

Redis is more than a simple key-value store - but it is no relational database, by any means. So limit your expectations towards complex searching or sorting.

This interface implements searching by primary key (an integer ID, which is automatically assigened to each "row" in the database), searching
indexed String values with compare- and prefix-search. All search capability aside from this results in a full "table" scan.

=head2 Indices

This interface allows you to define certain columes as indexed. Those columes should always be strings - not numbers, nor even more complex data strucutres. Those strings you can search with wildcars, such as "word*" or "w*rd*"

=head2 Structure

This interface will store your instances, represented by L<Redis::Object::Table>-objects, in a distinct strucuture. Do not try to use this interface with pre-existing data!

The structure relates to the L<Moose> attributes of your classes. Assuming the following table-class:

    package MyDB::MyTable;
    
    use Moose;
    with qw/ Redis::Object::Table /;
    
    has somekey => ( isa => "Str", is => "rw", required => 1 );
    has otherkey => ( isa => "Int", is => "rw", required => 1 );
    
    sub INDEX_ATTRIBUTES { qw/ somekey / }

The resulting "rows" would look something like this

    # contains the an ID timestamp, used for certain lookups
    mytable:1:_
    
    # contains the values of both attributres
    mytable:1:somekey
    mytable:1:otherkey
    
    # indexed key "somekey" for fast lookup
    mytable:1:_:somekey:The_Value

There is also a special key/value per table, which contains an incrementing integer for the primary key

    mytable:_id


=cut

use Moose;

use version 0.74; our $VERSION = qv( "v0.1.0" );

use Carp qw/ croak confess /;
use Redis;
use Data::Serializer;
use Data::Dumper;

use Redis::Object::SearchResult;


=head1 ATTRIBUTES

=head2 server

Defaults to 127.0.0.1:6379

=cut

has server => ( isa => 'Str', is => 'rw', default => '127.0.0.1:6379' );

=head2 tables

Array of table names

=cut

has tables => ( isa => 'ArrayRef[Str]', is => 'ro', required => 1 );

=head2 prefix

Optional refix for all key names

=cut

has prefix => ( isa => 'Str', is => 'rw', default => '' );

has _redis  => ( isa => 'Redis', is => 'rw' );
has _table_class  => ( isa => 'HashRef', is => 'rw', default => sub { {} } );
has _serializer => ( isa => 'Data::Serializer', is => 'rw', default => sub {
    Data::Serializer->new
} );

=head1 METHODS

=head2 new %args

=head3 %args

=over

=item * server

The Redis server and port, defaults to '127.0.0.1:6379'

=item * tables

Arrayref of table names. A table has to be implemented as a perl module with the same name.

=back

=cut

sub BUILD {
    my ( $self ) = @_;
    $self->_redis( Redis->new( server => $self->server ) );
    croak "tables is empty"
        unless @{ $self->tables };
    my $base_class = ref( $self );
    $self->_table_class( { map {
        my $class = /::/ ? $_ : "${base_class}::$_";
        eval "use $class; 1;"
            or croak "Cannot load table class '$class' ($@)";
        ( my $name = $class ) =~ s/.*:://;
        ( $name => $class )
    } @{ $self->tables } } );
}

=head2 create $table_name, $create_ref

Create new item

=head3 $table_name

The name of the table

=head3 $create_ref

The attributes of the object to be created

=cut

sub create {
    my ( $self, $table_name, $create_ref ) = @_;
    return $self->_create_or_update( $table_name, $create_ref );
}


=head2 update $item, [$update_ref]

Update existing item into database

=cut

sub update {
    my ( $self, $item, $update_ref ) = @_;
    my %update;
    ( my $table_name = ref( $item ) ) =~ s/.*:://;
    foreach my $attrib( @{ $self->_attribs( $table_name ) } ) {
        $update{ $attrib } = exists $update_ref->{ $attrib }
            ? $update_ref->{ $attrib }
            : $item->$attrib()
        ;
    }
    return $self->_create_or_update( $table_name, \%update, {
        id => $item->id
    } );
}

sub _create_or_update {
    my ( $self, $table_name, $create_ref, $args_ref ) = @_;
    croak "Table '$table_name' is unknown"
        unless defined $self->_table_class->{ $table_name };
    $args_ref ||= {};
    
    # get list of attribs
    my $attribs_ref = $self->_attribs( $table_name );
    my %create;
    
    # build create list
    foreach my $attrib( @$attribs_ref ) {
        $create{ $attrib } = $create_ref->{ $attrib }
            if exists $create_ref->{ $attrib };
        my $attr = $self->_attr_is_ref( $table_name, $attrib );
    }
    
    # create instance (constraints will run)
    my $class = $self->_table_class->{ $table_name };
    my $object = $class->new( %create, _super => $self, _table_name => $table_name );
    
    my $id = $args_ref->{ id } || $self->_next_id( $table_name );
    my $ts = time();
    
    # write the holder key
    #   <table>:<id>:_
    my $holder_key = $self->_keyname( $table_name, $id, '_' );
    $self->_redis->set( $holder_key, $ts );
    
    # write index keys
    #   <table>:<id>:_:<attrib>:<value>
    my $index_attribs_ref = $self->_get_index_attrs( $table_name );
    foreach my $attrib( @$index_attribs_ref ) {
        next unless exists $create{ $attrib };
        my $idx_key = $self->_keyname( $table_name, $id, '_', $attrib );
        
        # delete all (possibly) existing indexes of this attrib
        $self->_redis->del( $_ ) for $self->_redis->keys( $idx_key. ':*' );
        
        # insert new index
        ( my $idx_val = $create{ $attrib } || '__' ) =~ s/[\s\r\n]/_/gms;
        $idx_key .= ':'. $idx_val; # case sensitive
        $self->_redis->set( $idx_key, $ts );
    }
    
    # write attribute keys
    #   <table>:<id>:<attrib>
    while( my( $key, $value ) = each %create ) {
        my $keyname = $self->_keyname( $table_name, $id, $key );
        my $value_safe = $self->_attr_is_ref( $table_name, $key )
            ? $self->_serializer->serialize( {
                ts    => $ts,
                value => $value
            } )
            : $value;
        $self->_redis->set( $keyname, $value_safe );
    }
    
    $object->id( $id );
    return $object;
}

=head2 find $table_name, $item_id

Finds a single item by id

=head3 $table_name

Name of the table

=head3 $item_id

ID of the item

=cut

sub find {
    my ( $self, $table_name, $id ) = @_;
    
    # determine keyname
    my $keyname = $self->_keyname( $table_name, $id );
    my @keys = $self->_redis->keys( "${keyname}:*" );
    return undef unless @keys;
    
    # fetch all attributes
    my $length = length( $keyname ) + 1;
    my %create;
    foreach my $key( @keys ) {
        my $attr = substr( $key, $length );
        next if $attr =~ /^_/;
        my $value = $self->_redis->get( $key );
        if ( $self->_attr_is_ref( $table_name, $attr ) ) {
            $value = $self->_serializer->deserialize( $value )->{ value };
        }
        $create{ $attr } = $value;
    }
    
    # create instance
    my $class = $self->_table_class->{ $table_name };
    my $item = $class->new( %create, id => $id, _super => $self, _table_name => $table_name );
    
    return $item;
}

=head2 search $table_name, $filter, [$args_ref]

Search multiple items by attribute filter.

You can

=head3 $table_name

Name of the table

=head3 $filter

The search condition can have multiple shapes:

=head4 SubRef

A ref to a grep-like sub. Example:

    my $sub_filter = sub {
        my ( $item ) = @_;
        
        # add item to list
        return 1
            if ( $item->attribute eq "something" );
        
        # drop item
        return 0;
    };

=head4 HashRef

A subset of keys and value constraints, Example:

    # this is an AND-filter: all constraints have to fit
    my $filter_ref = {
        
        # simple string matching
        attribute1 => 'something',
        
        # string matches one
        attribute1 => 'something',
        
        # regex filter
        attribute2 => qr/^123/,
        
        # custom filter
        attribute3 => sub {
            my ( $value) = @_;
            return $value =~ /^xx/ && length( $value ) > 99;
        }
    }

=head3 $args_ref

=over

=item * or_search

Perform an or-search instead (default: and-search)

=back

Example

    my $result = $db->search( TableName => {
        attrib => "bla"
    } );
    while( my $item = $result->next ) {
        # ..
    }

=cut

sub search {
    my ( $self, $table_name, $filter, $args_ref ) = @_;
    $args_ref ||= {};
    
    # determine filter type, build filter list
    my $rfilter = ref( $filter ) || 'UNDEF';
    my ( @filter, %pre_ids );
    my $use_pre_ids = 0;
    
    # code type: one filter
    if ( $rfilter eq 'CODE' ) {
        push @filter, $filter;
    }
    
    # not allowed filter
    elsif ( $rfilter ne 'HASH' ) {
        croak "Cannot use filter of type '$rfilter', use CODE-ref or HASH-ref";
    }
    
    # multiple filter
    else {
        my %index_attrib = $self->_get_index_attrs( $table_name );
        while( my ( $attrib, $val ) = each %$filter ) {
            my $rval = ref( $val ) || '';
            if ( $rval eq 'CODE' ) {
                push @filter, sub {
                    my ( $item ) = @_;
                    return $val->( $item->$attrib() );
                };
            }
            elsif ( $rval eq 'Regexp' ) {
                push @filter, sub {
                    my ( $item ) = @_;
                    return $item->$attrib() =~ $val;
                };
            }
            else {
                
                # indexed search
                if ( defined $index_attrib{ $attrib } ) {
                    my $filter_key = $self->_keyname( $table_name, '*', '_', $attrib );
                    ( my $idx_val = $val || '__' ) =~ s/[\s\r\n]/_/gms;
                    $filter_key .= ':'. $idx_val; # case sensitive
                    $use_pre_ids++;
                    my $pre = length( $self->_keyname( $table_name ) ) + 1;
                    $pre_ids{ $_ }++ for map {
                        my ( $id ) = split( /:/, substr( $_, $pre ) );
                        $id;
                    } $self->_redis->keys( $filter_key );
                }
                
                # not indexed prefix search
                elsif ( $val =~ /^(.+?)\*$/ ) {
                    my $c = $1;
                    push @filter, sub {
                        my ( $item ) = @_;
                        return index( $item->$attrib(), $c ) == 0;
                    };
                }
                
                # not indexed compare search
                else {
                    push @filter, sub {
                        my ( $item ) = @_;
                        return $item->$attrib() eq $val;
                    };
                }
            }
        }
    }
    
    return Redis::Object::SearchResult->new(
        table       => $table_name,
        _super      => $self,
        _filter     => \@filter,
        _and_search => $args_ref->{ or_search } ? 0 : 1,
        ( scalar %pre_ids || ( $use_pre_ids && ! $args_ref->{ or_search } )
            ? ( _subset => [ keys %pre_ids ] )
            : ()
        )
    );
}


=head3 remove $search_or_item

Remove a single or multiple items

Single usage

    $db->remove( $item );

Multie usage

    $db->remove( $table => $search_ref );

=cut

sub remove {
    my ( $self, @args ) = @_;
    if ( scalar( @args ) >= 2 ) {
        my ( $table_name, $search_ref ) = @args;
        my $res = $self->search( $table_name => $search_ref );
        while( my $item = $res->next ) {
            $self->remove( $item );
        }
    }
    else {
        my ( $item ) = @args;
        my $search_keyname = $self->_keyname( $item->table_name, $item->id, '*' );
        foreach my $keyname( $self->_redis->keys( $search_keyname ) ) {
            $self->_redis->del( $keyname );
        }
        return ;
    }
}

=head2 truncate

Empties a whole table. ID will be reset. Use with caution.

=cut

sub truncate {
    my ( $self, $table_name ) = @_;
    my $search_keyname = $self->_keyname( $table_name, '*' );
    $self->_redis->del( $_ )
        for $self->_redis->keys( $search_keyname );
    return ;
}

=head2 count

Returns amount of entries in a tbale

=cut

sub count {
    my ( $self, $table_name ) = @_;
    my $search_keyname = $self->_keyname( $table_name, '*', '_' );
    return scalar( $self->_redis->keys( $search_keyname ) ) || 0;
}

sub _attribs {
    my ( $self, $name ) = @_;
    my $class = $self->_table_class->{ $name };
    my $meta = $class->meta;
    my @attribs = grep { !/^(?:_|id$)/ } $meta->get_attribute_list();
    return \@attribs;
}

sub _current_id {
    my ( $self, $name ) = @_;
    my $keyname = $self->_keyname( $name, qw/ _id / );
    return $self->_redis->get( $keyname ) || 0;
}

sub _next_id {
    my ( $self, $name ) = @_;
    my $keyname = $self->_keyname( $name, qw/ _id / );
    return $self->_redis->incr( $keyname );
}

sub _keyname {
    my ( $self, @keys ) = @_;
    return join( ':', map { $_ = lc( $_ ); s/\s/_/g; $_; } grep { defined $_ } (
        ( $self->prefix || undef ),
        @keys
    ) );
}

sub _attr_is_ref {
    my ( $self, $table_name, $attr_name ) = @_;
    my $class = $self->_table_class->{ $table_name };
    my $attrib = $class->meta->get_attribute( $attr_name );
    confess "Undefined attribute '$attr_name' in '$table_name'"
        unless $attrib;
    return ! $attrib->type_constraint->is_subtype_of( 'Value' );
}

sub _get_index_attrs {
    my ( $self, $table_name ) = @_;
    my $class = $self->_table_class->{ $table_name };
    my @index;
    if ( $class->can( 'INDEX_ATTRIBUTES' ) ) {
        @index = $class->INDEX_ATTRIBUTES();
    }
    return wantarray ? map{ ( $_ => 1 ) } @index : \@index;
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