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
plan tests => 16;

my $TEST_PREFIX = $ENV{ REDIS_TEST_PREFIX } || "perltest";

# check load redis
use_ok( 'Redis::Object' ) || BAIL_OUT( "No need to continue" );

# check load test database
use_ok( 'TestDB' ) || BAIL_OUT( "No need to continue" );

# init db
my $db = eval { TestDB->new(
    server => $ENV{ REDIS_SERVER },
    prefix => $TEST_PREFIX,
); };
ok( $db, "Database inited" ) || BAIL_OUT( "No need to continue: $@" );

my $redis = $db->_redis;

# create simple entry
my $item = $db->create( TestTable1 => {
    attr_str => "Some Value",
    attr_int => 123,
    attr_hash => { key => 'value' }
} );
ok( $item && $item->id, "Entry created" );

# confirm entry
my @keys = sort $redis->keys( $db->_keyname( TestTable1 => $item->id, '*' ) );
ok(
    scalar( @keys ) == 4
    && $keys[0] eq sprintf( $TEST_PREFIX. ':testtable1:%d:_', $item->id )
    && $keys[1] eq sprintf( $TEST_PREFIX. ':testtable1:%d:attr_hash', $item->id )
    && $keys[2] eq sprintf( $TEST_PREFIX. ':testtable1:%d:attr_int', $item->id )
    && $keys[3] eq sprintf( $TEST_PREFIX. ':testtable1:%d:attr_str', $item->id ),
    "Entry valid"
);

# create indexed entry
my $item2 = $db->create( TestTable2 => {
    attr_str => "Some Value",
    attr_int => 123,
    attr_hash => { key => 'value' }
} );
ok( $item2 && $item2->id, "Indexed entry created" );

# confirm indexed entry
@keys = sort $redis->keys( $db->_keyname( TestTable2 => $item2->id, '*' ) );
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
@keys = sort $redis->keys( $db->_keyname( TestTable2 => $item2->id, '*' ) );
ok(
    scalar( @keys ) == 5
    && $keys[0] eq sprintf( $TEST_PREFIX. ':testtable2:%d:_', $item2->id )
    && $keys[1] eq sprintf( $TEST_PREFIX. ':testtable2:%d:_:attr_str:Other_Value', $item2->id )
    && $keys[2] eq sprintf( $TEST_PREFIX. ':testtable2:%d:attr_hash', $item2->id )
    && $keys[3] eq sprintf( $TEST_PREFIX. ':testtable2:%d:attr_int', $item2->id )
    && $keys[4] eq sprintf( $TEST_PREFIX. ':testtable2:%d:attr_str', $item2->id ),
    "Indexed entry valid"
);

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

# remove item
$db->remove( $item );
my $item_check = $db->find( TestTable1 => $item->id );
@keys = $redis->keys( $db->_keyname( TestTable1 => $item->id, '*' ) );
ok( ! $item_check && ! @keys, "Item removed" );

# count items
my $count = $db->count( 'TestTable1' );
ok( $count == 11, 'Count items' );

# truncate database
$db->truncate( 'TestTable1' );
$db->truncate( 'TestTable2' );
$count = $db->count( 'TestTable1' ) + $db->count( 'TestTable2' );
ok( ! $count, 'Table emptied' );