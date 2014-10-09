#!/usr/bin/perl

use strict;
use warnings;

#use Socket qw(inet_aton inet_ntoa AF_INET AF_UNIX SOCK_DGRAM SOCK_STREAM);
use IO::Socket;
use strict;
use warnings;

#TODO: сделать демона из этого!!!!!!!!!!!!

my $config;

my $server = IO::Socket::INET->new
(
    LocalAddr    => 'localhost',
    LocalPort    => 8899,
    Type         => SOCK_STREAM,
    Reuse        => 1,
    Listen       => 5
) or die "could not open port\n";

warn "server ready waiting for connections.....  \n";

my $client;

while ($client = $server->accept())
{
    my $pid;
    while (not defined ($pid = fork()))
    {
        sleep 5;
    }
    if ($pid)
    {
        close $client;        # Only meaningful in the client 
    }
    else
    {
        $client->autoflush(1);    # Always a good idea 
        close $server;
        &do_your_stuff();
    }
}

sub do_your_stuff
{
    warn "client connected to pid $$\n";
    while(my $line = <$client>)
    {
        print "client> ", $line;
        print $client "pid $$ > ", $line;
    }
    exit 0;
}

# $self->process_args( \@ARGV, $template ) if defined @ARGV;
# LOOK !!!!!!!!!!  sub configure

1;
