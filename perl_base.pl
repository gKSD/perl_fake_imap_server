#!/usr/bin/perl

use Net::Server::Fork;
use JSON;
use Data::Dumper;
use strict;
#=begin
sub some_proc {
    my $b = @_[1];
    print $b;
    print "\n";


    my @a = (1,2,3,4,5);

    $b = @a[2];


    my $variable = \$b;

    print $variable;
    print "\n";
    print $$variable;
    print "\n";
}

some_proc(1,2,3);

sub f1 #если есть (), то типо переменных нет 
{
    my $a, $b;
    
    $a = shift;
    $b = shift;

}

sub f2 #если есть (), то типо переменных нет 
{
    my ($a, $b, $c) = @_;
}

sub f3 #если есть (), то типо переменных нет 
{
    my $b = @_[2];
}


for(my $i = 0; $i < 2; $i++)
{
    print "qwqw\n";


}
#=cut
print "123";

### TESTTTTTTTTTTT
    print "TEST\n";
    my $test = "capability => 123, lost => 456";
    my $string="1:one;2:two;3:three";
=begin
    my %hash;

    my @list1 = split /;/, $string;
    foreach my $item(@list1) {
      my ($i,$j)= split(/:/, $item);
        $hash{$i} = $j;
    }
=cut
    my %hash = map{split /\:/, $_}(split /;/, $string); 
    print Dumper \%hash;

    print "TEST end\n";
### TESTTTTTTTTTTTTTTT
1;
