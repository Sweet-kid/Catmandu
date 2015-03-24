
#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

my $pkg;
BEGIN {
    $pkg = 'Catmandu::MultiImporter';
    use_ok $pkg;
}

my $multi = $pkg->new(importers => []);    

isa_ok $multi, 'Catmandu::Importer';

is_deeply $multi->to_array, [];

done_testing 3;
