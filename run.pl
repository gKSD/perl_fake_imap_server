#!/usr/bin/perl -I/home/sofia/mailru/perl_fake_imap_server

#use fake_imap_server;
use IO::File;
use Switch;
use Data::Dumper;

sub print_help {
    print "Usage:\n";
    print "    --test [-t] =</dir/test_file>\n";
    print "    --imap_config [-c] =</dir/config_file>\n";
    print "    --help [-h]\n";
}

my $args = shift @ARGV;
print "args = $args, ARGV: ".Dumper(@ARGV)."\n";
my %parsed_args = ();
if (defined $args) {
    if ($args eq '-h' or $args eq '--help') {
        print_help();
        exit;
    }
    else {
        while(defined $args) {
            if (my @fields = $args =~ /^\-\-(\w+)\=([\w\.\/]+)$/g) {
                $parsed_args{$fields[0]} = $fields[1];
            }
            elsif ($args =~ /^\-[hplcts]$/g) {
                my $param = $args;
                if(defined ($_ = shift @ARGV) and (m/^([\w\.\/]+)$/)) {
                    switch ($param) {
                        case '-t' { $param = 'test' }
                        case '-c' { $param = 'config_file' }
                    }
                    $parsed_args{$param} = $_;
                }
                else {
                    warn "1 unrecognized param found (It should be like: '-p param_value' or '--param=param_value')\n";
                }
            }
            else {
                warn "2 unrecognized param found (It should be like: '-p param_value' or '--param=param_value')\n";
            }
            $args = shift @ARGV;
        }
    }
}
print "Dump of parsed_args 111: ". Dumper(%parsed_args)."\n";

sub parse_test_model {
    my $test_model_file = shift;

    my $fh = new IO::File;
    unless ($fh->open("< $test_model_file")) {
        warn "file($test_model_file) with reference state of mailbox not found\n";
    }

    my $k = 0;
    my %hash = ();
    while(<$fh>) {
        chomp $_;
        
        s/\s*//; 
        if (/\{/) {
            $k++;
            next;
        }
        elsif (/\}/) {
            $k--;
            next;
        }
        elsif (/^$/) {
            next;
        }

        unless ($k == 0) {
            if (/^(\w+):[ ]+\[([\s\,\w]+)\]$/) {
                my $key = $1;
                my $value = $2;
                my @ar = split (/, */, $value);

                @{$hash{$key}} = @ar;
            }
        }
    }

    $fh->close();
    return %hash;
}


my %model_state_hash = parse_test_model();
print "run.pl, model_state_hash: ".Dumper(\%model_state_hash)."\n";

our $fake_imap_server = fake_imap_server->new(host => 'omnoomno', scenario => 'scenario.txt');
$fake_imap_server->run(config_file => 'config.conf', host => 'localhost', port => 8081);


1;


=begin
use FakeImapServer;

our $fake_imap_server = FakeImapServer->new(conf_file => 'config.conf');

$fake_imap_server->run();
=cut
