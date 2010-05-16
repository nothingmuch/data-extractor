#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Try::Tiny;

BEGIN {
    try { require Devel::PartialDump; Devel::PartialDump->import(qw(dump)) } catch { require overload; *dump = \&overload::StrVal };
}

use ok 'Data::Extractor';

my $d = Data::Extractor->new;

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

done_testing;

# ex: set sw=4 et:

