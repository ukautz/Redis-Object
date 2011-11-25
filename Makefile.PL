#!/usr/bin/env perl

use 5.008007;

use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Redis::Object',
    VERSION_FROM => 'lib/Redis/Object.pm',
    ABSTRACT     => 'Redis object oriented access',
    AUTHOR       => 'Ulrich Kautz <uk@fortrabbit.de>',
    LICENSE      => "perl",
    PREREQ_PM    => {
        'Redis' => 0,
        'Data::Serializer' => 0,
        'Moose' => '2.0.0'
    },
    test         => {
        TESTS => 't/*.t'
    }
);
