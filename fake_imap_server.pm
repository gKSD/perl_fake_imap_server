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

sub print_help
{
    print "Usage:\n";
    print "     to run as script: ./fake_imap_server.pm run\n\n";
    print "     --port [p] =<port>\n";
    print "     --host [-h] =<host>\n";
    print "     --listen [-l] =<listen>\n";

    print "\n     --config-file [-c] =</dir/config_file>\n";
    print "     --tests [-t] =</dir/test_file>\n";
    print "     --scenario [-s] =</dir/scenario_file>\n";
}

my $argument = shift @ARGV;
print Dumper(@ARGV);

if(defined $argument) {
    if ($argument eq 'run') {
        my %data;
        while (defined ($argument = shift @ARGV))
        {
            $_ = $argument;
            if (m/(\w+)=(\w+)/) {
                print "hello user\n";

                my @fields = $argument =~ /((\w+)=(\w+))/g;
                print '@fileds: '.Dumper(@fields);
                $data{$fields[1]} = $fields[2];
            }

        }
        print 'Hashmap: '.Dumper(%data);
        print $data{'port'};
        my $server = fake_imap_server->new();
        $server->run();
    } elsif ($argument eq '-h' or $argument eq '--help') {
        print_help();
    } else {
        print_help();
    }
} else{
   print_help(); 
}


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    my $args  = @_ == 1 ? shift : {@_};
    
    $self->{client} = undef;
    
    print "Args: ".Dumper($args);
    
    $self->{init_params} = $args;
    $self->{server} = undef;

=begin
    $self->{server} = IO::Socket::INET->new(  
        LocalAddr    => 'localhost',
        LocalPort    => 8899,
        Type         => SOCK_STREAM,
        ReuseAddr    => 1,
        Listen       => 5
    ) or die "could not open port\n";
=cut

    bless $self, $class;
    print "Init_params->{aaaa}: ".Dumper($self->{init_params}->{aaaa});


    $self->init();
    my $port = (defined $self->{init_param}->{port}? $self->{init_param}->{port}: 8899);
    warn "Fake imap server is listening $port port\n";

    return $self;
}

sub init
{
    my $self = shift;
    $self->{server} = IO::Socket::INET->new(
        LocalAddr    => (defined $self->{init_param}->{host}? $self->{init_param}->{host}: 'localhost'),
        LocalPort    => (defined $self->{init_param}->{port}? $self->{init_param}->{port}: 8899),
        Type         => SOCK_STREAM,
        ReuseAddr    => (defined $self->{init_param}->{ReuseAddr}? $self->{init_param}->{ReuseAddr}: 1),
        Listen       => (defined $self->{init_param}->{listen}? $self->{init_param}->{listen}: 5)
    ) or die "coud not open port\n";

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

# $self->process_args( \@ARGV, $template ) if defined @ARGV;
# LOOK !!!!!!!!!!  sub configure

1;
