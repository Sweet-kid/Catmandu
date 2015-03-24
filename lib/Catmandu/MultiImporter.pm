package Catmandu::MultiImporter;

use Catmandu::Sane;
use Moo;

with 'Catmandu::Importer';

has importers => (is => 'ro', required => 1);

sub generator {
    my ($self) = @_;

    sub {
        state @generators = map { $_->generator } @{$self->importers};
        state $gen = shift @generators;
        while ($gen) {
            if (defined(my $data = $gen->())) {
                return $data;
            } else {
                $gen = shift @generators;
            }
        }
        return;
    };
}

1;

