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
#use POSIX qw(WNOHANG);
#use POSIX qw(setsid);
use POSIX;
use POSIX ":sys_wait_h";
use Log::Log4perl qw(:easy);

#use Proc::Daemon;
#Proc::Daemon::Init;

#TODO: сделать демона из этого!!!!!!!!!!!!
my $pid = fork();
exit() if $pid;
die "Couldn't fork: $! " unless defined($pid);
POSIX::setsid() or die "Can't start a new session $!";

sub print_help
{
    print "Usage:\n";
    print "     to run as script: ./fake_imap_server.pm run\n\n";
    print "     --port [-p] =<port>\n";
    print "     --host [-h] =<host>\n";
    print "     --listen [-l] =<listen>\n";

    print "\n     --config [-c] =</dir/config_file>\n";
    print "     --test [-t] =</dir/test_file>\n";
    print "     --mode [-m] =<config>\n";
}

my $argument = shift @ARGV;
if(defined $argument) {
    if ($argument eq 'run') {
        my %data;
        while (defined ($argument = shift @ARGV)) {
            if (my @fields = $argument =~ /^\-\-(\w+)\=([\w\.\/]+)$/g) {
                $data{$fields[0]} = $fields[1];
            }
            elsif ($argument =~ /^\-[hplcts]$/g) {
                my $param = $argument;
                if(defined ($_ = shift @ARGV) and (m/^([\w\.\/]+)$/)){    
                        switch ($param) {
                            case '-h' { $param = 'host' }
                            case '-p' { $param = 'port' }
                            case '-l' { $param = 'listen' }
                            case '-c' { $param = 'config' }
                            case '-t' { $param = 'test' }
                            case '-m' { $param = 'mode' }
                        }
                        $data{$param} = $_;
                }
                else
                {
                    warn "unrecognized param found (It should be like: '-p param_value' or '--param=param_value')\n";
                }
            }
            else
            {
                warn "unrecognized param found (It should be like: '-p param_value' or '--param=param_value')\n";
            }

        }
        my $server = fake_imap_server->new(%data);
        $server->run();
    } elsif ($argument eq '-h' or $argument eq '--help') {
        print_help();
        exit;
    } else {
        print "illegal option: $argument\n";
        print_help();
        exit;
    }
} else{
   print_help();
   exit;
}

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    my $args  = @_ == 1 ? shift : {@_};
    
    $self->{client} = undef;
    
    #$self->{logger}->debug( "Args: ".Dumper(scalar(keys %$args)));
    $self->{init_params} = undef;                       # $args;
    $self->{server} = undef;                            # хранит соединения
    $self->{imap} = undef;                              # сценарий ответов
    $self->{test} = undef;                              # хранение тестов
    $self->{logger} = undef;

    bless $self, $class;

    $self->init($args);
    return $self;
}

sub init
{
    my $self = shift;
    my $args = @_ == 1 ? shift : {@_};

    if (defined $args->{config}) {
        $self->parse_config($args->{config});
    }
    ###Обновляем значения в hashmap $self->{init_params}, если были переданы новые аргументы в init
    foreach my $key (keys %$args) {
        $self->{init_params}->{$key} = $$args{$key};
    }


    my $log_file = ($self->{init_params}->{log_file} ? $self->{init_params}->{log_file}: "fake_imap_server.log");
    Log::Log4perl->easy_init({level => $DEBUG, file => ">> $log_file"});
    $self->{logger} = get_logger();

    if (defined $self->{init_params}->{test}) {
        @{$self->{test}} = [];
        $self->parse_test_file($self->{init_params}->{test});
    }

    if (defined $self->{init_params}->{pid_file} ) {
        my $file = $self->{init_params}->{pid_file};
        my $fh = IO::File->new("> $file");
        if (defined $fh) {
            print $fh "$$\n";
            $fh->close;
        }
    }

    $self->{logger}->debug("After all parse: ".Dumper($self));
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
    ) or die "could not open connection\n";

    my $port = ((defined $self->{init_params}->{port})? $self->{init_params}->{port}: 8899);
    my $host = (defined $self->{init_params}->{host}? $self->{init_params}->{host}: 'localhost');
    warn "Fake imap server started [$host:$port]\n";

    while ($self->{client} = $self->{server}->accept())
    {
        $SIG{CHLD} = 'IGNORE';
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

sub process_request {
    my $self = shift;
    my $client = $self->{client};
    my $mode = ($self->{init_params}->{"mode"} eq "config" ? 1: 0);
    my $cmd_num;

    $self->{logger}->debug("mode = $mode");

    $self->{logger}->info("client connected to pid $$");
    print $client "* OK Welcome to Fake Imap Server\r\n";

    while(my $line = <$client>) {
        chomp $line;
        if ($line =~ /^\s*([\d\w]+)\s/) {
            $cmd_num = $1;
        }
        else {
            #not well formed command! error, die
            #send something as an answer to client to inform that command is incorrect
        }

        $self->{logger}->debug("<<<: $line");

        if ($line =~ /login/i) {
            if ($mode) {
                my $n = $#{$self->{imap}->{login}} + 1;
                for (my $i = 0; $i < $n; $i++) {
                    my $answer = $self->{imap}->{login}[$i];
                    $self->{logger}->debug(">>>: $answer");

                    if ($i == $n - 1) {
                        $self->tagged_send($answer, $cmd_num);
                        next;
                    }
                    $self->notagged_send($answer);
                }
            }
            else {
                $self->{logger}->debug(">>>: OK LOGIN completed");
                $self->tagged_send("OK LOGIN completed", $cmd_num);
            }
        }
        elsif ($line =~ /capability/i) {

        }
        elsif ($line =~ /noop/i)
        {}
        elsif ($line =~ /select/i)
        {}
        elsif ($line =~ /status/i)
        {}
        elsif ($line =~ /fetch/i)
        {}
        elsif ($line =~ /id/i)
        {}
        elsif ($line =~ /examine/i)
        {}
        elsif ($line =~ /create/i)
        {}
        elsif ($line =~ /delete/i)
        {}
        elsif ($line =~ /rename/i)
        {}
        elsif ($line =~ /subscribe/i)
        {}
        elsif ($line =~ /unsubscribe/i)
        {}
        elsif ($line =~ /list/i)
        {}
        elsif ($line =~ /xlist/i)
        {}
        elsif ($line =~ /lsub/i)
        {}
        elsif ($line =~ /append/i)
        {}
        elsif ($line =~ /check/i)
        {}
        elsif ($line =~ /unselect/i)
        {}
        elsif ($line =~ /expunge/i)
        {}
        elsif ($line =~ /search/i)
        {}
        elsif ($line =~ /store/i)
        {}
        elsif ($line =~ /copy/i)
        {}
        elsif ($line =~ /move/i)
        {}
        elsif ($line =~ /close/i)
        {}

        #$self->{logger}->debug( "client> ".$line);
        #print $client "pid $$ > ".$line."\r\n";
    }
    exit 0;
}

sub tagged_send
{
    my $self = shift;
    my $str = $_[0];
    my $num = $_[1];
    my $client = $self->{client};

    eval {print $client "$num $str\r\n";};
    if ($@) {
        $self->{logger}->error("Tagged command send error");
    }
}

sub notagged_send
{
    my $self = shift;
    my $str = $_[0];
    my $client = $self->{client};

    eval {
        if ($str =~ /^\*/) {
            print $client "$str\r\n";
        }
        else {
            print $client "* $str\r\n";
        }
    };
    if ($@) {
        $self->{logger}->error("Untagged command send error");
    }
}

sub get_test_file {
    my $self = shift;
    return $self->{init_params}->{test};
}

sub get_tests_amount {
    my $self = shift;
    return ($#{$self->{test}} + 1);
}

sub parse_test_file {
    my $self = shift;
    my $test_file = shift;

    my $fh = new IO::File;
    unless ($fh->open("< $test_file")) {
        die "file($test_file) with imap tests not found\n";
    }

    my %imap = ();
    my $key;
    my @test;
    my $k = 0;

    my $is_imap = 0;
    my $is_test = 0;
    while (<$fh>) {
        chomp $_;
        s/\s*//;

        if (/^\{\}$/) {
            next;
        }

        if (/\{/) {
            $k++;
            next;
        }

        if (/\}/) {
            $k--;
            if ($k == 0) {
                $is_imap = 0;
                $is_test = 0;
            }
            next;
        }

        if (/^$/) {
            next;
        }

        if ($k == 0) {
            $key = lc $_;
            if ($key eq 'imap') {
                $is_imap = 1;
            }
            elsif ($key eq 'test') {
                $is_test = 1;
            }
        }
        elsif ($k == 1) {
            if($is_imap) {
                $key = lc $_;
                unless ($key eq 'login' or $key eq 'capability' or $key eq 'noop' or $key eq 'select'
                    or $key eq 'status' or $key eq 'fetch' or $key eq 'id' or $key eq 'examine'
                    or $key eq 'create' or $key eq 'delete' or $key eq 'rename' or $key eq 'subscribe'
                    or $key eq 'unsubscribe' or $key eq 'list' or $key eq 'xlist' or $key eq 'lsub'
                    or $key eq 'append' or $key eq 'check' or $key eq 'unselect' or $key eq 'expunge'
                    or $key eq 'search' or $key eq 'store' or $key eq 'copy' or $key eq 'move'
                    or $key eq 'close' or $key eq 'logout') {
                    warn "invalid key in imap part in $test_file\n";
                }
                my @ar;
                @{$imap{$_}} = @ar;
            }
            elsif ($is_test) {
                my @ar = [];
                push @test, @ar;
            }
        }
        elsif ($k == 2) {
            if ($is_imap) {
                push @{$imap{$key}}, $_;
            }
            elsif($is_test) {
                if (/^(\w+):[ ]+\[([\s\,\w]+)\]$/) {
                    my $key1 = $1;
                    my $value = $2;
                    my %hash = ();
                    my @ar = split (/, */, $value);

                    @{$hash{$key1}} = @ar;
                    push @{$test[-1]}, \%hash;
                }
            }
        }
    }
    if ($k != 0) {
        die "syntax error in $test_file (check '{' and '}' amount)\n";
    }

    $fh->close();
    $self->{test} = \@test;
    $self->{imap} = \%imap;
}

sub parse_file_with_test {
    my $self = shift;
    my $test_file = shift;

    my $fh = new IO::File;
    unless ($fh->open("< $test_file")) {
        die "file($test_file) with imap tests not found\n";
    }

    my $k = 0;
    my @test_array;
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

        if ($k == 0) {
            #$key = lc $_;
            my @ar = [];
            push @test_array, @ar;
        }
        else {
            if (/^(\w+):[ ]+\[([\s\,\w]+)\]$/) {
                my $key = $1;
                my $value = $2;
                my %hash = ();
                my @ar = split (/, */, $value);

                @{$hash{$key}} = @ar;

                push @{$test_array[-1]}, \%hash;
                #if (my @ar = $value =~ /([\w]*[, ]*)*([\w]*)/) {
                #    print "ar: ".Dumper(@ar)."\n";
                #}

            }
        }
    }

    $self->{test} = \@test_array;
    $fh->close();
}

sub parse_scenario {
    my $self = shift;
    my $scenario = shift;

    my $fh = new IO::File;
    unless ($fh->open("< $scenario")) {
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
        elsif (/^$/)
        {
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
            my @ar = [];
            @{$hash{$_}} = @ar;
        }
        else {
            #push @hash{$key}, "qe";
            s/\s*//; #убирает пробелы в начале строки
            push @{$hash{$key}}, $_;
        }
    }
    $fh->close();
    $self->{scenario} = \%hash;
}

sub parse_config
{
    my $self = shift;
    my $config_file = shift;

    #open FILE, $config_file or return;
    my $fh = new IO::File;
    unless ($fh->open("< $config_file"))
    {
        warn "config_file ($config_file) not found\n";
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
=begin
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
            }

            if ($do_add)
            {
                $self->{init_params}{$key} = $value;
            }
=cut
            $self->{init_params}{$key} = $value;
        }
    }
    #close FILE;
    $fh->close;

}

1;
