#!/usr/bin/perl
package fake_imap_server;

use strict;
use warnings;

#use Socket qw(inet_aton inet_ntoa AF_INET AF_UNIX SOCK_DGRAM SOCK_STREAM);
use IO::Socket;
use strict;
use warnings;

use Data::Dumper;

#TODO: сделать демона из этого!!!!!!!!!!!!

#my $config;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    my $args  = @_ == 1 ? shift : {@_};
    
    $self->{client} = undef;
    $self->{my_commandline} = undef;
    
    print "Args: ".Dumper($args);
    
    $self->{init_params} = $args;
    $self->{server} = IO::Socket::INET->new(  
        LocalAddr    => 'localhost',
        LocalPort    => 8899,
        Type         => SOCK_STREAM,
        ReuseAddr    => 1,
        Listen       => 5
    ) or die "could not open port\n";

    bless $self, $class;
    print "Init_params: ".Dumper($self->{init_params}->{aaaa});

    warn "Fake imap server is listening $port port\n";

    return $self;
}

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
            $self->process_request();
        }
    }
}

sub process_request
{
    my $self = shift;
    my $client = $self->{client};
    warn "client connected to pid $$\n";
    while(my $line = <$client>)
    {
        #print {$client} "sf";
 
        #print $self->{client}  $line;
        #print $self->{client}  "pid $$ > ", $line;

        print "client> ", $line;
        print $client "pid $$ > ", $line;
    }
    exit 0;
}

sub get_commandline()
{
    my $self = shift;
    my $prop = $self->{server};

    ### see if we can find the full command line
    if (open _CMDLINE, "/proc/$$/cmdline") { # unix specific
        my $line = do { local $/ = undef; <_CMDLINE> };
        close _CMDLINE;
        if ($line =~ /^(.+)$/) { # need to untaint to allow for later hup
            return [split /\0/, $1];
        }
    }

    my $script = $0;
    $script = $ENV{'PWD'} .'/'. $script if $script =~ m|^[^/]+/| && $ENV{'PWD'}; # add absolute to relative
    $script =~ /^(.+)$/; # untaint for later use in hup
    return [ $1, @ARGV ]
}

sub commandline
{
    my $self = shift;
    if(@_)
    {
        $self->{my_commandline} = ref($_[0]) ? shift : \@_;
    }
    return $self->{my_commandline} || die "commandline was not set during initialization";
}

# $self->process_args( \@ARGV, $template ) if defined @ARGV;
# LOOK !!!!!!!!!!  sub configure

1;
