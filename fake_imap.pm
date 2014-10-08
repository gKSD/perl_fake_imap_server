#!/usr/bin/perl
package Net::Server::FakeImapServer;

use Net::Server::Fork;
@ISA = qw(Net::Server::Fork); #огранизация наследования

use strict;
use Data::Dumper;

#$__PACKAGE__{'conf_file'} = 'test.conf'; 

my ($a,$b,$c) = @_;

sub process_request
{
    #...code...
    my $self = shift;
    print Dumper($self);
    while(<STDIN>) {
        s/[\r\n]+$//;
        #\015\012 <=> \r\n
        print "Got string: '$_' \r\n";
        last if /quit/i;
    }
    sleep(1000);
}

#MyServer->run(conf_file => 'config.conf');

1;
