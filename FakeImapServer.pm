#!/usr/bin/perl
package FakeImapServer;

use Net::Server::Fork;
@ISA = qw(Net::Server::Fork); #огранизация наследования

use strict;
use warnings;
use Data::Dumper;

#$__PACKAGE__{'conf_file'} = 'test.conf'; 

my ($a,$b,$c) = @_;

sub tagged_send
{
    my $str = $_[0];
    my $num = $_[1];

    print "$num $str\r\n";
}

sub notagged_send
{
    my $str = $_[0];
    print "* $str\r\n";
}


sub process_request
{
    #...code...
    my $self = shift;
    print Dumper($self);
    while(<STDIN>) {
        s/[\r\n]+$//;
        
        #\015\012 <=> \r\n
        #print "Got string: '$_' \r\n";
        
        my $line = $_;
        my $command_num = (split(' ', $line))[0];
        #print "Number = $command_num \r\n";

        if (index($line, "LOGIN") != -1)
        {
            tagged_send("OK Authentication successful", $command_num);
        }
        elsif (index($line, "CAPABILITY") != -1)
        {
            notagged_send("CAPABILITY IDLE NAMESPACE");
            tagged_send("OK CAPABILITY completed", $command_num);
        }
        else
        {
            tagged_send("BAD Error in IMAP command received by server", $command_num);
        }



        last if /quit/i;
    }
    sleep(1000);
}

#FakeImapServer->run(conf_file => 'config.conf');

1;
