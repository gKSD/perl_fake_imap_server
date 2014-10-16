#!/usr/bin/perl -I/home/sofia/mailru/perl_fake_imap_server

#use fake_imap_server;
use IO::File;
use Switch;
use Data::Dumper;

sub print_help {
    print "Usage:\n";
    print "  obligatory: \n";
    print "    --test [-t] =</dir/test_file>\n";
    print "  optional: \n";
    print "    --imap_config [-c] =</dir/config_file>\n";
    print "    --help [-h]\n";
}

my $args = shift @ARGV;
my %parsed_args;

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
                        case '-c' { $param = 'imap_config' }
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

unless ($parsed_args{"test"}) {
    print "option --test [-t] is obligatory\n";
    print_help();
    exit;
}


sub parse_test_file {
    my $test_file = shift;

    my $fh = new IO::File;
    unless ($fh->open("< $test_file")) {
        warn "file($test_file) with reference state of mailbox not found\n";
        return;
    }

    my $k = 0;
    my @result = shift;
    my $is_result = 0;
    my $test_counter = shift;
    my $is_test = 0;
    my $key;

    $test_counter = 0;
    while(<$fh>) {
        chomp $_; 
        s/\s*//;
        if (/^\{\}$/) {
            next;
        }
        if (/\{/) {
            $k++;
            next;
        }
        elsif (/\}/) {
            $k--;
            if ($k == 0) {
                $is_result = 0;
                $is_test = 0;
            }
            next;
        }
        elsif (/^$/) {
            next;
        }

        if ($k == 0) {
            $key = lc $_;
            if ($key eq "result") {
                $is_result = 1;
            }
            elsif ($key eq "test") {
                $is_test = 1;
            }
        }
        elsif ($k == 1) {
            if ($is_result) {
                my @ar = [];
                push @test, @ar;
            }
            elsif ($is_test) {
                $test_counter++;
            }
        }
        elsif ($k == 2) {
            if ($is_result) {
                if (/^(\w+):[ ]+\[([\s\,\w]+)\]$/) {
                    my $key1 = $1;
                    my $value = $2;
                    my %hash = ();
                    my @ar = split (/, */, $value);

                    @{$hash{$key1}} = @ar;
                    push @{$result[-1]}, \%hash;
                }
            }
        }
    }

    $fh->close();
}

my @test_result;
#my $fake_imap_server;
my $tests_amount = 0;
my $check_all = 0;

if (defined $parsed_args{"test"}) {
    parse_test_file($parsed_args{"test"},\@test_result, \$tests_amount);
    my $cmd = "./fake_imap_server.pm run  ".(defined $parsed_args{"imap_config"}? "--config=".$parsed_args{"imap_config"}: '--config=config.conf')."  --test=".$parsed_args{"test"};
    print "\$cmd: $cmd\n";
    system($cmd);
    
    #$fake_imap_server = fake_imap_server->new(config_file => (defined $parsed_args{"config_file"}? $parsed_args{"config_file"}: 'config.conf'), test => $parsed_args{"test"});
}
else {
    #$fake_imap_server = fake_imap_server->new(config_file => (defined $parsed_args{"config_file"}? $parsed_args{"config_file"}: 'config.conf'));
    my $test_file =$fake_imap_server->get_test_file();
    parse_test_file($test_file,\@test_result, \$tests_amount);
}
print "!! ".Dumper(\@test_result)."\n";
#$tests_amount = $fake_imap_server->get_tests_amount();
$check_all = ($#test_result + 1 <= 1? 0: 1);
print "Res \$tests_amount = $tests_amount\n";
#$fake_imap_server->run();

for (my $i = 0; $i < $tests_amount; $i++) {
    print "\$i = $i\n";
}

my $fh = IO::File->new("< /tmp/server.pid");
if (defined $fh) {
    my $line = <$fh>;
    chomp $line;
    print "PID = $line\n";
    kill 9, $line;
}
1;


=begin
use FakeImapServer;

our $fake_imap_server = FakeImapServer->new(conf_file => 'config.conf');

$fake_imap_server->run();
=cut
