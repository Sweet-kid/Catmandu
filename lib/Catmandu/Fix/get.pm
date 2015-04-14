package Catmandu::Fix::get;

use Catmandu::Sane;
use Catmandu;
use Moo;
use Catmandu::Fix::Has;

with 'Catmandu::Fix::Base';

has path       => (fix_arg => 1);
has name       => (fix_arg => 1);
has delete     => (fix_opt => 1);
has ignore_404 => (fix_opt => 1);
has opts       => (fix_opt => 'collect');

sub emit {
    my ($self, $fixer) = @_;
    my $path = $fixer->split_path($self->path);
    my $key = pop @$path;
    my $name_var = $fixer->capture($self->name);
    my $opts_var = $fixer->capture($self->opts);
    my $temp_var = $fixer->generate_var;

    $fixer->emit_walk_path($fixer->var, $path, sub {
        my $var = shift;
        $fixer->emit_get_key($var, $key, sub {
            my $val_var = shift;
            my $index_var = shift;
            my $perl = $fixer->emit_declare_vars($temp_var);
            if ($self->ignore_404) {
                $perl .= "try {";
            } 
            $perl .= "${temp_var} = Catmandu->importer(${name_var}, variables => ${val_var}, %{${opts_var}})->first;";
            if ($self->ignore_404) {
                $perl .= "} catch {" .
                    "if (\$_ =~ /^404/) { ${temp_var} = undef; } else { die \$_; }" .
                "};";
            } 
            $perl .= "if (defined(${temp_var})) {";
            $perl .= "${val_var} = ${temp_var};";
            $perl .= "}";
            if ($self->delete) {
                $perl .= "else {";
                if (defined $index_var) { # wildcard: only delete the value where the get failed
                    $perl .= "splice(\@{${var}}, ${index_var}--, 1);";
                } else {
                    $perl .= $fixer->emit_delete_key($var, $key);
                }
                $perl .= "}";
            }$perl;
        });
    });
}

=head1 NAME

Catmandu::Fix::get - change the value of a HASH key or ARRAY index by replacing
it's value with imported data

=head1 SYNOPSIS

   get(foo.bar, JSON, url: "http://foo.com/bar.json", path: data.*)

=head1 SEE ALSO

L<Catmandu::Fix>

=cut

1;
