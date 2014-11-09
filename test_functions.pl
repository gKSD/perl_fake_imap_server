#!/usr/bin/perl

use strict;

my $test_str = '"aa\bb\\\\ccc\ta"""tt"tt"tt"';

print $test_str . "\n";

####
####
    $test_str =~ /^\"?(.*)\"?$/;
    my $str = $1;
    $str =~ s/\\/\\\\/ig;
    $str =~ s/\"/\\\"/ig;
    $test_str = '"'. $str . '"';
    print $test_str . "\n";


####
####
    $test_str =~ s/\\\\/\\/ig;
    $test_str =~ s/\\\"/\"/ig;
 
    print $test_str . "\n";

