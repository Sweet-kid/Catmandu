
#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;
use Catmandu::Importer::Mock;

my $pkg;
BEGIN {
    $pkg = 'Catmandu::MultiImporter';
    use_ok $pkg;
}

my $multi = $pkg->new(importers => []);    

can_ok $multi, 'each';

is_deeply $multi->to_array, [];

$multi = $pkg->new(importers => [
        Catmandu::Importer::Mock->new(size => 2),
        Catmandu::Importer::Mock->new(size => 2),
]);    

is_deeply $multi->to_array, [{n=>0},{n=>1},{n=>0},{n=>1}];

done_testing 4;
