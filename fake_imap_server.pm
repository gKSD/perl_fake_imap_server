#!/usr/bin/perl
package fake_imap_server;

use strict;
use warnings;

#use Socket qw(inet_aton inet_ntoa AF_INET AF_UNIX SOCK_DGRAM SOCK_STREAM);
use IO::Socket;
use IO::File;
use strict;
use warnings;
use Switch;
use Data::Dumper;

#use Config::YAML;

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
    
    print "Args: ".Dumper(scalar(keys %$args))."\n";
    $self->{init_params} = $args;
    $self->{server} = undef; #для хранени я соединения
    $self->{scenario} = undef;

    bless $self, $class;
    #print "Init_params->{aaaa}: ".Dumper($self->{init_params}->{aaaa});

    $self->init();

### TESTTTTTTTTTTT
    print "TEST\n";
    my $test = "capability => 123, lost => 456";
    my $string="1:one;2:two;3:three";
=begin
    my %hash;

    my @list1 = split /;/, $string;
    foreach my $item(@list1) {
      my ($i,$j)= split(/:/, $item);
        $hash{$i} = $j;
    }
=cut
    my %hash = map{split /\:/, $_}(split /;/, $string); 
    print Dumper \%hash;

    print "TEST end\n";
### TESTTTTTTTTTTTTTTT

    return $self;
}

sub init
{
    my $self = shift;
    my $args = @_ == 1 ? shift : {@_};

    ###Обновляем значения в hashmap $self->{init_params}, если были переданы новые аргументы в init
    if(scalar(keys %$args) != 0) {
        foreach my $key (keys %$args) {
            $self->{init_params}->{$key} = $$args{$key};
        }
    }

    if (defined $self->{init_params}->{config_file})
    {
        print "parse config\n";
        $self->parse_config($self->{init_params}->{config_file});
    }
    
    print "After parse: ".Dumper($self->{init_params})."\n"; 
}

sub run {
    my $self = shift;
    my $args  = @_ == 1 ? shift : {@_};
    if(scalar(keys %$args) != 0) {
        $self->init($args);
    }

    $self->{server} = IO::Socket::INET->new(
        LocalAddr    => (defined $self->{init_params}->{host}? $self->{init_params}->{host}: 'localhost'),
        LocalPort    => (defined $self->{init_params}->{port}? $self->{init_params}->{port}: 8899),
        Type         => SOCK_STREAM,
        ReuseAddr    => (defined $self->{init_params}->{ReuseAddr}? $self->{init_params}->{ReuseAddr}: 1),
        Listen       => (defined $self->{init_params}->{listen}? $self->{init_params}->{listen}: 5)
    ) or die "coud not open connection\n";

    my $port = ((defined $self->{init_params}->{port})? $self->{init_params}->{port}: 8899);
    my $host = (defined $self->{init_params}->{host}? $self->{init_params}->{host}: 'localhost');
    warn "Fake imap server started [$host:$port]\n";

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

sub parse_scenario
{
    my $self = shift;
    my $scenario = shift;

    my $fh = new IO::File;
    unless ($fh->open("< $scenario"))
    {
        die "imap scenario  not found\n";
    }
### Creating hashmap from scenario
### Keys: login, capability

    my $key;
    my %hash;
    my $k = 0; # используется для подсчета скобочек
    while (<$fh>) {
        chomp $_;

        if (/\{/) {
            $k++;
            next;
        }
        elsif (/\}/) {
            $k--;
            next;
        }
        if ($k == 0) {
            $key = lc $_;
            unless ($key eq 'login' or $key eq 'capability' or $key eq 'noop' or $key eq 'select'
                    or $key eq 'status' or $key eq 'fetch' or $key eq 'id' or $key eq 'examine'
                    or $key eq 'create' or $key eq 'delete' or $key eq 'rename' or $key eq 'subscribe'
                    or $key eq 'unsubscribe' or $key eq 'list' or $key eq 'xlist' or $key eq 'lsub'
                    or $key eq 'append' or $key eq 'check' or $key eq 'unselect' or $key eq 'expunge'
                    or $key eq 'search' or $key eq 'store' or $key eq 'copy' or $key eq 'move'
                    or $key eq 'close') {
                die "invalid key in imap scenario ($scenario)\n";
            }
            my @mas = [];
            push (@mas, $_);
            %hash{$_} = @mas;
            #%self->{scenario}{$key} = @mas;
        }
        else {
            #push %hash{$key} $_;
            #push(%hash{$key}, ($_));
        }
    }
    print "scenario hash: ".Dumper(%hash)."\n";
    $fh->close();
}

sub parse_config
{
    my $self = shift;
    my $config_file = shift;

    print "$config_file\n";

    ### TEST
    my $ff = new IO::File;
    $ff->open("< $config_file");
    while (<$ff>) {
        if ( $_ eq 'host')
        {
            print "TESTTT is equal to host ($_)\n";
        }
    }
    $ff->close();
    ###
 
    #open FILE, $config_file or return;
    my $fh = new IO::File;
    unless ($fh->open("< $config_file"))
    {
        return;
    }

    my $do_add = 0;

    while (defined (my $line = <$fh>)) {
        chomp $line;
        $do_add = 1;
        if ($line =~ /^(\w+)[ ]+([\w\.\/]*)$/) {
            my $key = $1;
            my $value = $2;

            ### Параметры, передаваемые напрямую - более приоритетные
            switch ($key) {
                case 'host' {
                        if (defined $self->{init_params}->{host}) {
                            $do_add = 0;
                        }
                    }
                case 'port' {
                        if (defined $self->{init_params}->{port}) {
                            $do_add = 0;
                        }
                    }
                case 'listen' {
                        if (defined $self->{init_params}->{listen}) {
                            $do_add = 0;
                        }
                    }
                case 'test' {
                        if (defined $self->{init_params}->{test}) {
                            $do_add = 0;
                        }
                    }
                case 'scenario' {
                        if (defined $self->{init_params}->{scenario}) {
                            $do_add = 0;
                        }
                    }
            }

            if ($do_add)
            {
                $self->{init_params}{$key} = $value;
            }
        }
    }
    #close FILE;
    $fh->close;
    
### May use YAML
### my $config = Config::YAML->new( config => $config_file );
### print Dumper( $config );

}

=begin
        if (/login/i)
        {}
        elsif (/capability/i)
        {}
        elsif (/noop/i)
        {}
        elsif (/select/i)
        {}
        elsif (/status/i)
        {}
        elsif (/fetch/i)
        {}
        elsif (/id/i)
        {}
        elsif (/examine/i)
        {}
        elsif (/create/i)
        {}
        elsif (/delete/i)
        {}
        elsif (/rename/i)
        {}
        elsif (/subscribe/i)
        {}
        elsif (/unsubscribe/i)
        {}
        elsif (/list/i)
        {}
        elsif (/xlist/i)
        {}
        elsif (/lsub/i)
        {}
        elsif (/append/i)
        {}
        elsif (/check/i)
        {}
        elsif (/unselect/i)
        {}
        elsif (/expunge/i)
        {}
        elsif (/search/i)
        {}
        elsif (/store/i)
        {}
        elsif (/copy/i)
        {}
        elsif (/move/i)
        {}
        elsif (/close/i)
        {}
=cut
1;
