package Catmandu::Importer::Aleph;

use 5.010;

use File::Slurp qw(slurp);
use List::MoreUtils qw(natatime);

sub new {
   my ($pkg,$opts) = @_;
   return bless $opts, $pkg;
}

sub default_attribute {
   'file';
}

sub each {
   my ($self, $callback) = @_;
   my $num = 0;

   local(*F);
   open(F,'<:utf8',$self->{file}) || die "failed to open " . $self->{file} . " for reading :$ $!\n";

   my $rec     = {};
   my $prev_id = undef;

   my $mapper  = $self->mapper( $self->{inline_map} || $self->{file_map} );
   my $id_len  = undef;

   while(<F>) {
     chomp;
	
     next unless (length $_ >= 18);
     
     # dynamically guess the id length
     unless ($id_len) {
	my ($id) = ($_ =~ /^(\S+)/g);
        $id_len = length $id;
     }
    
     my ($sysid,$s1,$tag,$ind1,$ind2,$s2,$char,$s3,$data) = unpack("A9A1A3A1A1A1A1A1U0A*",$_);
     my @parts = ('_' , split(/\$\$(.)/, $data) );

     if (defined $prev_id && $prev_id != $sysid) {

        if (defined $callback) {
            $callback->( $mapper ? $mapper->($rec) : $rec ) if ($self->{skip} <= $num); 
        }

        $rec = {};

        $num++;

	last if ($self->{count} != -1 && $num == $self->{count} + $self->{skip});
     }

     $rec->{id} = $sysid;
     push @{$rec->{data}}, [$tag, $ind1, $ind2, $char , @parts];

     $prev_id = $sysid;
   }

   if (defined $callback && defined $mapper && keys %$rec) {
       $callback->( $mapper->($rec) ); 
   }

   $num++;

   return $num;
}

# Load a mapping file to map MARC fields to stored fields
# E.g. the input can be
#
#  245       title
#  540+a     rights
#  852+j     relation
#  100+ac    author
#  260-x     publisher
#
sub file_map {
    my $self = shift;

    return undef unless $self->{map};

    my $map = [];

    foreach my $line (split /\n/, slurp($self->{map})) {
        next if ($line =~ /^\s*#/);
        next if ($line =~ /^\s*$/);

        my ($path, $key) = split /\s+/, $line;
        push (@$map , $path => $key );
    }

    $map;
}

# Compile a mapping array into a translator for MARC records
#
# Usage:
#      
#   my $mapper = $self->mapper([ '024' => 'info' , '245' => 'title']);
#   my $hash   = $mapper->($rec);
#
sub mapper {
    my ($self,$map) = @_;
    return undef unless $map;

    my $dc = {};
   
    my $eval =<<EOF;
sub {
   my \$rec = shift;

   my \$dc = {};

EOF

    for (my $i = 0 ; $i < @$map ; $i += 2) {
        my $key = $map->[$i];
	my $value = $map->[$i+1];
        
        if ($key eq 'MRC') {
            $eval .= "   push \@{\$dc->{$value}} , \$rec;\n";
        }
        elsif ($key eq 'SYS') {
            $eval .= "   push \@{\$dc->{$value}} , \$rec->{id};\n";
        }
        elsif ($key =~ /^([A-Z0-9*]{3})(\+([a-z0-9]+))?(\-([a-z0-9]+))?/) {
            my $field    = $1; $field =~ s/\*/./g;
            my $includes = $3 ? join '|' , split (// , $3) : undef;
            my $excludes = $5 ? join '|' , split (// , $5) : undef;

            my $inc_code = $includes ?  ", includes => '$includes'" : "";
            my $exc_code = $excludes ?  ", excludes => '$excludes'" : "";

            $eval .= "   push(\@{\$dc->{$value}} , \&field(\$rec, '$field' $inc_code $exc_code));\n";
        }
        else {
            warn "syntax error in map '$key' -> '$value'";
        }
    }

    $eval .=<<EOF;

    \&clean_empty(\$dc);
}
EOF

   my $sub = eval $eval;

   die "$@\n$eval" if ($@);

   $sub;
}

sub clean_empty {
    my $rec = shift;
    my $out = { _id => $rec->{_id}->[0] };

    foreach my $key (keys %$rec) {
        next if $key eq '_id';

        my $val = $rec->{$key};

        $out->{$key} = $val if defined $val && @$val > 0; 
    }

    $out;
}

sub field {
    my ($rec,$field_regex, %opts) = @_;

    my @fields = grep { $_->[0] =~ /$field_regex/ } @{$rec->{data}};

    my @out = ();

    foreach (@fields) {
        my $len    = @$_;
        my @data   = @$_[4 .. $len-1];
        my @values = ();

        INNER: while (my @v = splice(@data,0,2)) {
            next INNER if defined $opts{includes} && $v[0] !~ /$opts{includes}/;
            next INNER if defined $opts{excludes} && $v[0] =~ /$opts{excludes}/;

            push (@values, $v[1]) if defined $v[1] && length $v[1];
        }

        my $str = join(" ",@values);
        $str =~ s/(^\s+|\s+$)//;

        push @out , $str if length $str;
    }

    @out; 
}

1;

=head1 SYNOPSIS

    use Catmandu::Importer::Aleph;

    my $importer = Catmandu::Importer::Aleph(file => 'import.marc' , map => 'aleph.map');

    or 

    my $importer = Catmandu::Importer::Aleph(file => 'import.marc' , inline_map => [
            '001'       => '_id' ,
            '245'       => 'title' ,
            '852+j'     => 'relation' ,
            '700-x'     => 'author' ,
            '5**'       => 'notes' ,
    ]);

    $importer->each(sub {
        my $obj = shift;

        $obj->{_id}->[0];
        $obj->{_title}->[0]; 
    });

    or via the command line

    catmandu convert -I Aleph -i map=data/aleph.map -o pretty=1 import.txt

    catmandu import  -I Aleph -i map=data/aleph.map -o path=data/aleph.db import.txt

=head1 METHODS

=head2 $c->new(file => $file , map => $map_file , inline_map => [])

Creates a new Catmandu::Importer for parsing MARC sequential data from $file into
Perl hashes. The contents of the Perl hash is defined by the $map_file which has
a contents like:

   245      title
   852+j    relation
   700-x    author

Which states that the '245' field should be extracted into a 'title' key. The
'852' only the 'j' subfield should be extracted into the 'relation' key. And the
'700' field without the 'x' subfield should be in the author field.

Mapping syntax:
    
    <map>      ::= { <line> }
    <line>     ::= <selector> ' '+ <field> '\n'
    <selector> ::= <f-sel> <f-sel> <f-sel> ['+' <s-sel>+] ['-' <s-sel>+]
    <field>    ::= <letter> { <letter> | <digit> }
    <f-sel>    ::= <digit> | <upper> | '*'
    <s-sel>    ::= <digit> | <lower>
    <letter>   ::= <upper> | <lower>
    <digit>    ::= '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9'
    <upper>    ::= 'A' | 'B' | 'C' | 'D' | 'E' | 'F' | 'G' | 'H' | 'I' | 'J' |
                   'K' | 'L' | 'M' | 'N' | 'O' | 'P' | 'Q' | 'R' | 'S' | 'T' |
                   'U' | 'V' | 'W' | 'X' | 'Y' | 'Z'
    <lower>    ::= 'a' | 'b' | 'c' | 'd' | 'e' | 'f' | 'g' | 'h' | 'i' | 'j' |
                   'k' | 'l' | 'm' | 'n' | 'o' | 'p' | 'q' | 'r' | 's' | 't' |
                   'u' | 'v' | 'w' | 'x' | 'y' | 'z'

=head2 $c->each($callback)

Execute $callback for every record imported. The callback functions get as 
first argument the parsed object (a ref hash of key => [ values ]). Returns
the number of objects in the stream.

=head1 SEE ALSO

L<Catmandu::Importer>
