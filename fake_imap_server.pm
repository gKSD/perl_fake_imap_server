#!/usr/bin/perl
package fake_imap_server;

use strict;
use warnings;

#use Socket qw(inet_aton inet_ntoa AF_INET AF_UNIX SOCK_DGRAM SOCK_STREAM);
use IO::Socket;
use strict;
use warnings;

#TODO: сделать демона из этого!!!!!!!!!!!!

#my $config;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    $self->{client} = undef;
    $self->{server} = IO::Socket::INET->new
    (
        LocalAddr    => 'localhost',
        LocalPort    => 8899,
        Type         => SOCK_STREAM,
        Reuse        => 1,
        Listen       => 5
    ) or die "could not open port\n";
    bless $self, $class;
    return $self;
}
#warn "server ready waiting for connections.....  \n";

sub run {
    my $self = shift;
    while ($self->{client} = $self->{server}->accept())
    {
        my $pid;
        while (not defined ($pid = fork()))
        {
            sleep 5;
        }
        if ($pid)
        {
            close $self->{client};        # Only meaningful in the client 
        }
        else
        {
            $self->{client}->autoflush(1);    # Always a good idea 
            close $self->{server};
            $self->do_your_stuff();
        }
    }
}

sub do_your_stuff
{
    my $self = shift;
    my $client = $self->{client};
    warn "client connected to pid $$\n";
    use Data::Dumper;
    print Dumper($self);
    while(my $line = < $client >)
    {
        print {$client} "sf";
       # print $self->{client}  $line;
       # print $self->{client}  "pid $$ > ", $line;
    }
    exit 0;
}

# $self->process_args( \@ARGV, $template ) if defined @ARGV;
# LOOK !!!!!!!!!!  sub configure

1;
