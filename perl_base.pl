#!/usr/bin/perl

use Net::Server::Fork;
use JSON;
use Data::Dumper;
use IO::File;
use strict;
#=begin


sub logger {
    my ($sec,$min,$hour,$day,$mon,$year)=(localtime(time))[0,1,2,3,4,5];
 
    SWITCH: {
        #запись на открытие лог файла
        if ($_[0] eq "0") {
            open(LOG,">>log.txt");
            printf LOG "$day.$mon.$year - Open log****************";
            last SWITCH;
        }
        #запись на закрытие лог файла
        if ($_[0] eq "1") {
            printf LOG "$hour:$min:$sec - Close log*************************";
            close(LOG);
            last SWITCH;
        }
        #запись сообщение в логе
        if ($_[0] eq "2") {
            printf LOG "$hour:$min:$sec - $_[1]";last SWITCH;
        }
    }
}


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


sub do_parse {
    my $fh = shift; #указатель на файл
    my $it = shift; # ссылка на предыдущую структуру
    my $is_ar = shift; # тип предыдущей структуры - хэш или массив
    my $brackets = shift; #ссылка на массив со скобками

    print "FUNCTION do_parse,".Dumper($it)."\n";

    my $prev_line;
    my $is_first = 1;

    while (<$fh>) {
        chomp $_;
        print "line $_\n";
        print "\$prev_line: $prev_line, \$is_first: $is_first\n";
        s/\s*//;

        if (/^\{\}$/) {
            next;
        }
        if (/^\[\]$/) {
            next;
        }
        if (/^\{$/) {
            push @{$brackets}, '}'; #type of expected closing bracket
            print "brackets: ".Dumper(@{$brackets})."\n";
            %{$it->{$prev_line}} = ();
            print "it {} before: ".Dumper($it)."\n";
            if (do_parse($fh, \%{$it->{$prev_line}}, 0, $brackets) <= 0) {
                return -1;
            }
            print "it {} after: ".Dumper($it)."\n";
            $is_first = 1;
            next;
        }
        if (/^\[$/) {
            push @{$brackets}, ']';
            print "brackets: ".Dumper(@{$brackets})."\n";
            @{$it->{$prev_line}} = ();
            print "it [] before: ".Dumper($it)."\n";
            if (do_parse($fh, \@{$it->{$prev_line}}, 1, $brackets) <= 0) {
                return -1;
            }
            print "it {} after: ".Dumper($it)."\n";
            $is_first = 1;
            next;
        } 
        if (/^\]/) {
            my $last = pop @{$brackets};
            unless ($last eq ']') {
                print "123 Syntax error in config, check ] brackets, ".Dumper(@{$brackets})."\n";
                return -1;
            }
            push @{$it}, $prev_line;
            return 1;
        }
        if (/^\}/) {
            my $last = pop @{$brackets};
            unless ($last eq '}') {
                print "456 Syntax error in config, check } brackets, ".Dumper(@{$brackets})."\n";
                return -1;
            }
            if ($is_first) {
                return 1;
            } else {
                print "789 Syntax error in config, check {} or [] brackets, ".Dumper(@{$brackets})."\n";
                return -1;
            }
            next;
        }

        if (/^$/) {next;}
        if (/^\#/) {next;}

        if ($is_first) {
            $prev_line = $_;
            $is_first = 0;


            print "LINE is $_\n";
            if (/^(\w+)[:]?\s*[\(\[]\s*([\s\,\w\(\)]+)[\]\)]\,*\s*$/) {
                my $key = $1;
                my $value = $2;
                my @ar = split (/, */, $value);
                @{$it->{$key}} = @ar;
                print "it {} after little push: ".Dumper($it)."\n";
                $is_first = 1;
            }
            elsif (/^(\w+)\s*\:\"?\s*(\w+)\s*\"?\s*\,?$/) {
                $it->{$1} = $2;
                print "it {} after little push: ".Dumper($it)."\n";
                $is_first = 1;
            }

            ### TODO обработать первый элемент, все равно массива или хэша вида a:1, при этом $is_first снова станет равным 1
        } else {
            if ($is_ar) {
                push @{$it}, $prev_line;
                $prev_line = $_;
            } else {
                print "000 Syntax error in config, check {} or [] brackets, ".Dumper(@{$brackets})."\n"; 
                return -1;
            }
        }
    }
    return 1;
}


sub parse_test_file1 {
    print "FUNCTION parse_test_file1\n";
    my $test_file = shift;

    my $fh = new IO::File;
    unless ($fh->open("$test_file")) {
        die "file($test_file) with imap tests not found\n";
    }

    my @brackets;
    my %glhash;
    my $is_new_bracket = 0;
    my $is_init_item = 1;

    if (do_parse($fh, \%glhash, 0, \@brackets) <= 0) {
        print "ERROR in parsing\n";
        $fh->close();
        return -1;
    } else {
        print "OK, parsing completed\n";
    }

    $fh->close();
    print Dumper(%glhash);
}


#parse_test_file("tests/test3");
parse_test_file1("tests/test2");


sub func2 {
    my $fh = shift; 
    while( <$fh> ) { 
        #print "a line: $_";
    } 
} 

sub func1 { 
    my $fh = new IO::File; 
    print "func1\n";
    unless ($fh->open("tests/test2")) { 
          die "file not found\n"; 
    } 
    func2($fh); 
    $fh->close(); 
}

func1();
1;
