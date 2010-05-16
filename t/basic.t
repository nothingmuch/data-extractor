#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Try::Tiny;

BEGIN {
    try { require Devel::PartialDump; Devel::PartialDump->import(qw(dump)) } catch { require overload; *dump = \&overload::StrVal };
}

use ok 'Data::Extractor';

our $d = Data::Extractor->new;

sub extract_ok ($$$;$) {
    my ( $data, $path, $exp, $desc ) = @_;

    $desc ||= dump($data) . ".$path";

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    is_deeply(
        $d->extract($data, $path),
        $exp,
        $desc,
    );
}

extract_ok(
    { foo => "bar" },
    "foo",
    "bar",
);

extract_ok(
    { foo => [ "bar" ] },
    "foo[0]",
    "bar",
);

extract_ok(
    { foo => "bar" },
    "keys",
    [qw(foo)],
);

extract_ok(
    { foo => "bar" },
    "foo.length",
    3,
);



extract_ok(
    { foo => { "blargh" => 1 } },
    "foo.blah",
    undef,
);

extract_ok(
    { foo => { "blargh" => 1 } },
    'foo["blah"]',
    undef,
);

extract_ok (
    { "foo" => [qw(foo bar)] },
    "foo.length",
    2,
);

extract_ok (
    { "foo" => { "keys", "lalala" } },
    "foo.keys",
    "lalala",
);

extract_ok (
    { "foo" => { "keys", "lalala" } },
    "foo.keys()",
    [qw(keys)],
);

extract_ok (
    { "foo" => { "blah", "lalala" } },
    "foo.keys",
    [qw(blah)],
);

extract_ok (
    { "foo" => { "blah", "lalala" } },
    'foo["keys"]',
    undef,
);

extract_ok (
    { "foo" => { "blah", "lalala" } },
    'foo.exists("blah")',
    do {
        use Moose::Autobox;
        { blah => "lalala" }->exists("blah");
    },
);

extract_ok (
    { "foo" => { "blah", "lalala" } },
    'foo.exists("flarp")',
    do {
        use Moose::Autobox;
        { blah => "lalala" }->exists("flarp");
    },
);



extract_ok (
    { "foo" => { "blah", "lalala" } },
    'foo["foo"].defined',
    do {
        use Moose::Autobox;
        undef->defined();
    },
);

throws_ok {
    extract_ok (
        { "foo" => { "blah", "lalala" } },
        'foo["keys"].length',
        undef,
    );
} qr/on an undefined/, "can't call on undef";

extract_ok (
    { "foo" => { qw(foo bar gorch baz oi vey) } },
    'foo["oi","foo"]',
    [qw(vey bar)],
    "hash slice",
);

{
    package Person;
    use Moose;
    
    has name => ( isa => "Str", is => "ro" );
    has friend => ( isa => "Person", is => "ro" );
}

extract_ok (
    Person->new( name => "Jane", friend => Person->new( name => "Dick" ) ),
    "friend.name",
    "Dick",
);

throws_ok {
    extract_ok (
        Person->new( name => "Jane", friend => Person->new( name => "Dick" ) ),
        "friend.blah",
        "Dick",
    );
} qr/Can't locate object method/, 'unknown method is fatal';

lives_ok {
    local $d = Data::Extractor->new( unknown_method_is_fatal => 0 );

    extract_ok (
        Person->new( name => "Jane", friend => Person->new( name => "Dick" ) ),
        "friend.blah",
        undef,
    );
} "unknown method fatal turned off";

throws_ok {
    extract_ok (
        { person => Person->new( name => "Blah" ) },
        'person["name"]',
        undef,
    );
} qr/Simple subscripts/, 'cant do obj["foo"]';

done_testing;

# ex: set sw=4 et:

