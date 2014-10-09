#!/usr/bin/perl

use strict;
use warnings;

#use Socket qw(inet_aton inet_ntoa AF_INET AF_UNIX SOCK_DGRAM SOCK_STREAM);
use IO::Socket;
use strict;
use warnings;

#TODO: сделать демона из этого!!!!!!!!!!!!

my $config_args;

=begin
sub initialize
{
    my $self = shift;
    $self->commandline($self->get_commandline) if ! eval {$self->commandline};

    $config_args = undef;

    $self->configure(@_);
}

sub configure
{

}
=cut

my $server = IO::Socket::INET->new
(
    LocalAddr    => 'localhost',
    LocalPort    => 8899,
    Type         => SOCK_STREAM,
    ReuseAddr    => 1,
    Listen       => 5
) or die "could not open port\n";

warn "Fake imap server is listening $port port\n";

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
