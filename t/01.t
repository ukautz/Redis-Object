#!/usr/bin/perl

use strict;
use warnings;
use FindBin qw/ $Bin /;
use Test::More;
use Data::Dumper;

use lib "$Bin/lib";
use lib "$Bin/../lib";

plan skip_all => 'No REDIS_SERVER found in environment'
    unless $ENV{ REDIS_SERVER };
plan tests => 22;

my $TEST_PREFIX = $ENV{ REDIS_TEST_PREFIX } || "perltest";

# check load redis
use_ok( 'Redis::Object' ) || BAIL_OUT( "No need to continue, could not load Redis::Object" );

# check load test database
use_ok( 'TestDB' ) || BAIL_OUT( "No need to continue" );

# init db
my $db = eval { TestDB->new(
    server => $ENV{ REDIS_SERVER },
    prefix => $TEST_PREFIX,
); };
ok( $db, "Database inited" ) || BAIL_OUT( "No need to continue, could not init database: $@" );

my $redis = $db->_redis;

# create simple entry
my $item = $db->create( TestTable1 => {
    attr_str => "Some Value",
    attr_int => 123,
    attr_hash => { key => 'value' }
} );
ok( $item && $item->id, "Entry created" );

# confirm entry
my @keys = get_keys( $item );
ok(
    scalar( @keys ) == 4
    && $keys[0] eq sprintf( $TEST_PREFIX. ':testtable1:%d:_', $item->id )
    && $keys[1] eq sprintf( $TEST_PREFIX. ':testtable1:%d:attr_hash', $item->id )
    && $keys[2] eq sprintf( $TEST_PREFIX. ':testtable1:%d:attr_int', $item->id )
    && $keys[3] eq sprintf( $TEST_PREFIX. ':testtable1:%d:attr_str', $item->id ),
    "Entry valid"
);

# confirm re-read data
$item = $db->find( TestTable1 => $item->id );
ok( 
    $item &&
    ref( $item->attr_hash ) &&
    $item->attr_hash->{ key } eq 'value' &&
    $item->attr_str eq 'Some Value' &&
    $item->attr_int == 123,
    'Read values'
);

# create indexed entry
my $item2 = $db->create( TestTable2 => {
    attr_str => "Some Value",
    attr_int => 123,
    attr_hash => { key => 'value' }
} );
ok( $item2 && $item2->id, "Indexed entry created" );

# confirm indexed entry
@keys = get_keys( $item2 );
ok(
    scalar( @keys ) == 5
    && $keys[0] eq sprintf( $TEST_PREFIX. ':testtable2:%d:_', $item2->id )
    && $keys[1] eq sprintf( $TEST_PREFIX. ':testtable2:%d:_:attr_str:Some_Value', $item2->id )
    && $keys[2] eq sprintf( $TEST_PREFIX. ':testtable2:%d:attr_hash', $item2->id )
    && $keys[3] eq sprintf( $TEST_PREFIX. ':testtable2:%d:attr_int', $item2->id )
    && $keys[4] eq sprintf( $TEST_PREFIX. ':testtable2:%d:attr_str', $item2->id ),
    "Indexed entry valid"
);

# try update, re-read
$item->update( { attr_str => "Other Value" } );
my $item3 = $db->find( TestTable1 => $item->id );
ok(
    $item->attr_str eq 'Other Value'
    && $item3
    && $item->attr_str eq $item3->attr_str,
    'Update item'
);

# try update for indexed attribute
$item2->update( { attr_str => "Other Value" } );
@keys = get_keys( $item2 );
ok(
    scalar( @keys ) == 5
    && $keys[0] eq sprintf( $TEST_PREFIX. ':testtable2:%d:_', $item2->id )
    && $keys[1] eq sprintf( $TEST_PREFIX. ':testtable2:%d:_:attr_str:Other_Value', $item2->id )
    && $keys[2] eq sprintf( $TEST_PREFIX. ':testtable2:%d:attr_hash', $item2->id )
    && $keys[3] eq sprintf( $TEST_PREFIX. ':testtable2:%d:attr_int', $item2->id )
    && $keys[4] eq sprintf( $TEST_PREFIX. ':testtable2:%d:attr_str', $item2->id ),
    "Indexed entry valid"
);

# try safe index values
my $itemx = eval { $db->create( TestTable3 => {
    regular => 'Some String Value',
    safe    => 'SafeValue'
} ) };
@keys = get_keys( $itemx );
ok(
    $itemx &&
    $keys[0] eq sprintf( 'perltest:testtable3:%d:_', $itemx->id ) &&
    $keys[1] eq sprintf( 'perltest:testtable3:%d:_:regular:Some_String_Value', $itemx->id ) &&
    $keys[2] eq sprintf( 'perltest:testtable3:%d:_:safe:SafeValue', $itemx->id ) &&
    $keys[3] eq sprintf( 'perltest:testtable3:%d:regular', $itemx->id ) &&
    $keys[4] eq sprintf( 'perltest:testtable3:%d:safe', $itemx->id )
    ,
    'Correct safe index value'
);

# try unsafe index values
$itemx = eval { $db->create( TestTable3 => {
    regular => 'Some String Value',
    safe    => 'UnSafe Value'
} ) };
ok( ! $itemx && $@, 'Incorrect safe index value' );

# create multiple entries, try search on them
my @msg = (
    'Simple search on table',
    'Simple search on indexed table'
);
foreach my $table_name( qw/ TestTable1 TestTable2 / ) {
    foreach my $num( 0..10 ) {
        $db->create( $table_name => {
            attr_str => sprintf( "Item %02d", $num * 2 ),
            attr_int => 1000 * $num,
            attr_hash => { some => $num }
        } );
    }
    my $result = $db->search( $table_name => {
        attr_str => "Item 1*"
    } );
    my $msg = shift @msg;
    my $found_count = 0;
    while( my $i = $result->next ) {
        $found_count++;
    }
    ok( $found_count == 5, $msg );
}

# count items
my $count = $db->count( 'TestTable1' );
ok( $count == 12, 'Count items' );

# use reset with search
my $result1 = $db->search( TestTable1 => {
    attr_str => "Item 1*"
} );
my $count1 = 0;
while( $result1->next ) { $count1++ }
$result1->reset;
my $count2 = 0;
my $first_item;
while( my $item = $result1->next ) { $first_item ||= $item; $count2++ }
$first_item->remove;
my $count3 = 0;
$result1->reset;
while( $result1->next ) { $count3++ }
ok(
    $count1 == 5 && $count1 == $count2 && $count2 == $count3 + 1,
    "Reset search"
);

# run update all
$result1->reset;
$result1->update_all( {
    attr_int => 123
} );
$result1->reset;
my $count_update = 0;
while( $result1->next ) { $count_update++ if $_->attr_int == 123 }
ok( $count3 == $count_update, "Update all" );

# search with single sub
my @result = $db->search( TestTable1 => sub {
    my ( $self ) = @_;
    $self->attr_int == 4000
} )->all;
ok( scalar( @result ) == 1, 'Search with sub' );

# search complex
@result = $db->search( TestTable1 => {
    attr_str => qr/Item 0[123]/,
    attr_int => '1000',
    attr_hash => sub {
        my ( $ref ) = @_;
        return ( $ref->{ some } || 0 ) == 1;
    }
} )->all;
ok( scalar( @result ) == 1, 'Complex search' );

# remove single item
$db->remove( $item );
my $item_check = $db->find( TestTable1 => $item->id );
@keys = get_keys( $item );
ok( ! $item_check && ! @keys, "Single item removed" );

# run remove all
$result1 = $db->search( TestTable1 => {
    attr_str => sub {
        my ( $val ) = @_;
        return $val =~ /^Item 0[234]/;
    }
} )->remove_all();
$result1->reset;
my $count_remove = 0;
while( $result1->next ) { $count_remove++ }
my $count_after = $db->count( 'TestTable1' );
ok( $count_remove == 0 && $count_after == 8, "Remove multiple items" );

# truncate database
$db->truncate( $_ ) for qw/ TestTable1 TestTable2 TestTable3 /;
$count = 0;
$count += $db->count( $_ ) for qw/ TestTable1 TestTable2 TestTable3 /;
ok( ! $count, 'Tables emptied' );


sub get_keys {
    my ( $i ) = @_;
    return sort $redis->keys( $db->_keyname( $i->table_name => $i->id, '*' ) );
}