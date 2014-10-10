#!/usr/bin/perl
package fake_imap_server;

use strict;
use warnings;

#use Socket qw(inet_aton inet_ntoa AF_INET AF_UNIX SOCK_DGRAM SOCK_STREAM);
use IO::Socket;
use strict;
use warnings;
use Switch;
use Data::Dumper;

use Config::YAML;

#TODO: сделать демона из этого!!!!!!!!!!!!

sub print_help
{
    print "Usage:\n";
    print "     to run as script: ./fake_imap_server.pm run\n\n";
    print "     --port [p] =<port>\n";
    print "     --host [-h] =<host>\n";
    print "     --listen [-l] =<listen>\n";

    print "\n     --config_file [-c] =</dir/config_file>\n";
    print "     --test [-t] =</dir/test_file>\n";
    print "     --scenario [-s] =</dir/scenario_file>\n";
}

my $argument = shift @ARGV;
print Dumper(@ARGV);

if(defined $argument) {
    if ($argument eq 'run') {
        my %data;
        while (defined ($argument = shift @ARGV))
        {
            if (my @fields = $argument =~ /^\-\-(\w+)\=([\w\.\/]+)$/g) {
                $data{$fields[0]} = $fields[1];
            }
            elsif ($argument =~ /^\-[hplcts]$/g)
            {
                my $param = $argument;
                if(defined ($_ = shift @ARGV) and (m/^([\w\.\/]+)$/)){    
                        switch ($param) {
                            case '-h' { $param = 'host' }
                            case '-p' { $param = 'port' }
                            case '-l' { $param = 'listen' }
                            case '-c' { $param = 'config_file' }
                            case '-t' { $param = 'test' }
                            case '-s' { $param = 'scenario' }
                        }
                        $data{$param} = $_;
                }
                else
                {
                    die "unrecognized param found (It should be like: '-p param_value' or '--param=param_value')\n";
                }
            }
            else
            {
                die "unrecognized param found (It should be like: '-p param_value' or '--param=param_value')\n";
            }

        }
        my $server = fake_imap_server->new(%data);
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

    print "&&& ".$self->{init_params}->{port}."\n";
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
    #print "Init_params->{aaaa}: ".Dumper($self->{init_params}->{aaaa});


    $self->init();
    my $port = ((defined $self->{init_params}->{port})? $self->{init_params}->{port}: 8899);
    my $host = (defined $self->{init_params}->{host}? $self->{init_params}->{host}: 'localhost');
    warn "Fake imap server started [$host:$port]\n";

    return $self;
}

sub init
{
    my $self = shift;

    if (defined $self->{init_params}->{config_file})
    {
        $self->parse_config($self->{init_params}->{config_file});
    }

    $self->{server} = IO::Socket::INET->new(
        LocalAddr    => (defined $self->{init_params}->{host}? $self->{init_params}->{host}: 'localhost'),
        LocalPort    => (defined $self->{init_params}->{port}? $self->{init_params}->{port}: 8899),
        Type         => SOCK_STREAM,
        ReuseAddr    => (defined $self->{init_params}->{ReuseAddr}? $self->{init_params}->{ReuseAddr}: 1),
        Listen       => (defined $self->{init_params}->{listen}? $self->{init_params}->{listen}: 5)
    ) or die "coud not open connection\n";
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

sub parse_config
{
    my $self = shift;
    my $config_file = shift;

    print "$config_file\n";
  
    open FILE, $config_file or return;

    while (defined (my $line = <FILE>)) {
        if ($line =~ /^(\w+)[ ]+([\w\.\/]*)$/) {
            my $key = $1;
            my $value = $2;

=begin 
            ### Параметры, передаваемые напрямую - более приоритетные
            switch ($param) {
                case 'host' {
                        unless (defined $self->{init_params}->{config_file}) {
                            $param = 'host';
                        }
                    }
                case 'port' {
                        $param = 'port'
                    }
                case 'listen' {
                        $param = 'listen'
                    }
                case 'config_file' {
                        $param = 'config_file'
                    }
                case 'test' {
                        $param = 'test'
                    }
                case 'scenario' {
                        $param = 'scenario'
                    }
            }

=cut

            print "$key => $value \n";
        }
    }
    close FILE;
    
=begin
    while(<STDIN>) { # читаем по строке
        if ($_ =~ /^(\w+) (\w*)$/) {
            my $key = $1;
            my $value = $2;
        }
   }
=cut

### May use YAML
### my $config = Config::YAML->new( config => $config_file );
### print Dumper( $config );
### 
}

1;
