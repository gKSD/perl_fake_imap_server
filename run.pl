#!/usr/bin/perl -I/home/sofia/mailru/perl_fake_imap_server

use fake_imap_server;
use IO::File;


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

our $fake_imap_server = fake_imap_server->new(host => 'omnoomno', scenario => 'scenario.txt');
$fake_imap_server->run(config_file => 'config.conf', host => 'localhost', port => 8081);


1;


=begin
use FakeImapServer;

our $fake_imap_server = FakeImapServer->new(conf_file => 'config.conf');

$fake_imap_server->run();
=cut
