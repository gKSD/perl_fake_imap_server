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
    $self->{connection_number} = 0;

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
    my $mode = 0;
    if ($self->{init_params}) {
        $mode = ($self->{init_params}->{"mode"} eq "config" ? 1: 0);
    }
    my $cmd_num;

    $self->{logger}->debug("mode = $mode");

    $self->{logger}->info("client connected to pid $$");
    print $client "* OK Welcome to Fake Imap Server\r\n";

    while(my $line = <$client>) {
        chomp $line;
        if ($line =~ /^\s*(\w+)\s/) {
            $cmd_num = $1;
        }
        else {
            #not well formed command! error, die
            #send something as an answer to client to inform that command is incorrect
        }

        $self->{logger}->debug("<<<: $line");

        if ($line =~ /login/i) {
            if ($mode) {
                if ($self->{imap}->{login}) {
                    if ($self->send_answer_from_config($self->{imap}->{login}, $cmd_num)) {
                        next;
                    }
=begin
                    my $n = $#{$self->{imap}->{login}} + 1;
                    if ($n > 0) {
                        for (my $i = 0; $i < $n; $i++) {
                            my $answer = $self->{imap}->{login}[$i];
                            $self->{logger}->debug(">>>: $answer");

                            if ($i == $n - 1) {
                                $self->tagged_send($answer, $cmd_num);
                                next;
                            }
                            $self->notagged_send($answer);
                        }
                        next;
                    }
=cut
                }
            }
            $self->{logger}->debug(">>>: OK LOGIN completed");
            $self->tagged_send("OK LOGIN completed", $cmd_num);
        }
        elsif ($line =~ /capability/i) {
            if ($mode) {
                if ($self->{imap}->{capability}) {
                    if ($self->send_answer_from_config($self->{imap}->{capability}, $cmd_num)) {
                        next;
                    }
                }
            }
            $self->{logger}->debug(">>>: CAPABILITY IDLE NAMESPACE");
            $self->{logger}->debug(">>>: OK capability complited");

            $self->notagged_send("CAPABILITY IDLE NAMESPACE");
            $self->tagged_send("OK capability complited", $cmd_num);
        }
        elsif ($line =~ /namespace/i) {
            if ($mode) {
                if ($self->{imap}->{namespace}) {
                    if ($self->send_answer_from_config($self->{imap}->{namespace}, $cmd_num)) {
                        next;
                    }
                }

            }
            $self->{logger}->debug(">>>: NAMESPACE ((\"INBOX.\" \".\")) NIL NIL");
            $self->{logger}->debug(">>>: OK Namespace complited");

            $self->notagged_send("NAMESPACE ((\"INBOX.\" \".\")) NIL NIL");
            $self->tagged_send("OK Namespace complited", $cmd_num);
        }
        elsif ($line =~ /noop/i) {
            if ($mode) {
                if ($self->{imap}->{noop}) {
                    if ($self->send_answer_from_config($self->{imap}->{noop}, $cmd_num)) {
                        next;
                    }
                }
            }
            $self->{logger}->debug(">>>: OK NOOP completed");
            $self->tagged_send("OK NOOP completed", $cmd_num);
        }
        elsif ($line =~ /list/i) {
            #same with xlist
            if ($mode) {
                if ($self->{imap}->{list}) {
                    if ($self->send_answer_from_config($self->{imap}->{list}, $cmd_num)) {
                        next;
                    }
                }
                elsif ($self->{imap}->{xlist}) {
                    if ($self->send_answer_from_config($self->{imap}->{xlist}, $cmd_num)) {
                        next;
                    }
                }
                if ($self->run_cmd_list($cmd_num)) {
                    next;
                }
            }
            $self->notagged_send("LIST (\\trash) \"/\" Trash");
            $self->notagged_send("LIST (\\sent) \"/\" Sent");
            $self->notagged_send("LIST (\\inbox) \"/\" Inbox");
            $self->notagged_send("LIST (\\junk) \"/\" Junk");
            $self->tagged_send("OK LIST Completed", $cmd_num);
        }
        elsif ($line =~ /logout/i) {
            if ($mode) {
                if ($self->{imap}->{logout}) {
                    if ($self->send_answer_from_config($self->{imap}->{logout}, $cmd_num)) {
                        next;
                    }
                }
            }
            $self->notagged_send("BYE Fake Imap Server logging out");
            $self->tagged_send("OK LOGOUT completed", $cmd_num);
        }
        elsif ($line =~ /status/i) {
            if ($mode) {
                if ($self->{imap}->{status}) {
                    if ($self->send_answer_from_config($self->{imap}->{status}, $cmd_num)) {
                        next;
                    }
                }
                if ($self->run_cmd_status($cmd_num, $line)) {
                    next;
                }
            }
            if ($line =~ /inbox/i) {
                $self->notagged_send("LIST (\\trash) \"/\" Trash");
            }
            else {
                $self->notagged_send("LIST (\\sent) \"/\" Sent");
            }
            $self->tagged_send("OK LIST Completed", $cmd_num);

        }
        elsif ($line =~ /select/i) {
            
        }
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
    ### TODO: надо сбростиь  $self->{connection_number} = 0;
    exit 0;
}

sub run_cmd_list() {
    my $self = shift;
    my $cmd_num = shift;
    my %folders = %{$self->{test}[$self->{connection_number}]};
    unless (%folders) {return -1;}
    foreach my $folder (keys %folders){
        my $answer = "* XLIST (";
        foreach my $flag (@{$folders{$folder}{"flags"}}) {
            unless ($answer =~ /\($/) {
                $answer .= " ";
            }
            $answer .= "\\$flag";
        }
        $answer .= ") \"/\" \"$folder\"";
        $self->notagged_send($answer);
        $self->{logger}->debug(">>>: $answer");
    }
    $self->tagged_send("OK LIST completed", $cmd_num);
    $self->{logger}->debug(">>>: OK LIST completed");
    return 1;
}

sub run_cmd_status {
    my $self = shift;
    my $cmd_num = shift;
    my $status = shift;

    my %folders = %{$self->{test}[$self->{connection_number}]};
    unless (%folders) {return -1;}

    if ($status =~ /^\w+\s+STATUS\s+(.+)\s+\((.*)\)\s*$/i) {
        my $answer = "STATUS ";
        my $need_space = 0;
        my $folder = $1;
        my $flags = $2;
        if ($folder =~ /^\"(.+)\"$/) {
            $folder = $1;
        }
        $self->{logger}->debug("run_cmd_status: $folder, $flags");

        if ($flags =~ /MESSAGES/i) {
            my $n = 0;
            if ($folders{$folder}{"uids"}) {
                my @ar = @{$folders{$folder}{"uids"}};
                $n = $#ar + 1;
            }
            $answer .= "MESSAGES $n";
            $need_space = 1;
        }
        if (1 or $flags =~ /RECENT/i) {
            if ($need_space) {$answer .= " ";}
            foreach my $uid (@{$folders{$folder}{"uids"}}) {
                $self->{logger}->debug("uid is ".Dumper(%{$uid}));
            }
        }
        if (1 or $flags =~ /UIDNEXT/i) {
        }
        if (1 or $flags =~ /UIDVALIDITY/i) {
        }
        if (1 or $flags =~ /RECENT/i) {
        }

        $self->tagged_send("OK STATUS completed", $cmd_num);
        $self->{logger}->debug(">>>: OK STATUS completed");
        return 1;
    }
    $self->{logger}->info("STATUS command is not well formed");
    return -1;
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

sub send_answer_from_config {
    my $self = shift;
    my @ar = shift;
    @ar = @{$ar[0]};
    my $cmd_num = shift;

    my $n = $#ar + 1;
    if ($n > 0) {
        for (my $i = 0; $i < $n; $i++) {
            $self->{logger}->debug(">>>: $ar[$i]");
            if ($i == $n - 1) {
                $self->tagged_send($ar[$i], $cmd_num);
            }
            else {
                $self->notagged_send($ar[$i]);
            }
        }
        return 1;
    }
    return 0;
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
    my $folder_name;
    my $folder_attribute;
    my $uid;

    my $is_hash = 0;
    my $is_array = 0;

    my $is_imap = 0;
    my $is_test = 0;
    while (<$fh>) {
        chomp $_;
        s/\s*//;

        if (/^\{\}$/) {
            next;
        }
        if (/^\[\]$/) {
            next;
        }
        if (/^\{$/) {
            $is_hash = 1;
            $k++;
            next;
        }
        if (/^\[$/) {
            $k++;
            $is_array = 1;
            next;
        } 
        if (/^[\}\]]/) {
            $k--;
            if (/^\}$/) {
                $is_hash = 0;
            }
            else {
                $is_array = 0;
            }
            if ($k == 0) {
                $is_imap = 0;
                $is_test = 0;
            }
            next;
        }

        if (/^$/) {
            next;
        }
        if (/^\#/) {
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
                /^(\w+)/;
                $key = lc $1;
                unless ($key eq 'login' or $key eq 'capability' or $key eq 'noop' or $key eq 'select'
                    or $key eq 'status' or $key eq 'fetch' or $key eq 'id' or $key eq 'examine'
                    or $key eq 'create' or $key eq 'delete' or $key eq 'rename' or $key eq 'subscribe'
                    or $key eq 'unsubscribe' or $key eq 'list' or $key eq 'xlist' or $key eq 'lsub'
                    or $key eq 'append' or $key eq 'check' or $key eq 'unselect' or $key eq 'expunge'
                    or $key eq 'search' or $key eq 'store' or $key eq 'copy' or $key eq 'move'
                    or $key eq 'close' or $key eq 'logout' or $key eq 'namespace') {
                    warn "invalid key in imap part in $test_file\n";
                }
                my @ar;
                @{$imap{$key}} = @ar;
            }
            elsif ($is_test) {
                #my @ar = [];
                #push @test, @ar;
                my %hash = ();
                push @test, \%hash;
            }
        }
        elsif ($k == 2) {
            if ($is_imap) {
                push @{$imap{$key}}, $_;
            }
            elsif($is_test) {
                my %folder;
                my %hash;

                /^(\w+)/;
                $folder_name = $1;
                #%{$folder{$_}} = %hash;
                $test[-1]->{$folder_name} = \%hash;
                #$test[-1] = \%folder;

                #push @{$test[-1]}, \%folder;
=begin
                if (/^(\w+):[ ]+\[([\s\,\w]+)\]$/) {
                    my $key1 = $1;
                    my $value = $2;
                    my %hash = ();
                    my @ar = split (/, */, $value);

                    @{$hash{$key1}} = @ar;
                    push @{$test[-1]}, \%hash;
                }
=cut
            }
        }
        elsif ($k == 3) {
            if ($is_test) {
                if (/^(\w+)[:]*[ ]*[\(\[]\s*([\s\,\w\(\)]+)[\]\)][\,]*$/) {
                    my $key1 = $1;
                    my $value = $2;
                    my @ar = split (/, */, $value);

                    #@{$test[-1]->{$folder_name}->{$key1}} = @ar;
                    if ($key1 eq "flags") {
                        @{$test[-1]->{$folder_name}->{$key1}} = @ar;
                    }
                    elsif ($key1 eq "uids") {
                        my %hash;
                        foreach my $it (@ar) {
                            my @attr;
                            @{$hash{it}} = @attr;
                        }
                        %{$test[-1]->{$folder_name}->{$key1}} = %hash;
                    }
                    $folder_attribute = $key1;
                }
                elsif (/^(\w+)[:\s]*$/) {
                    my %hash;
                    %{$test[-1]->{$folder_name}->{$1}} = %hash;
                    $folder_attribute = $1;
                }
            }
        }
        elsif ($k == 4) {
           if ($is_test) {
                if (/^(\w+)[:]*[ ]*[\[\(]\s*([\s\,\w\(\)]+)[\]\)][\,]*$/) {
                    my $key1 = $1;
                    my $value = $2;
                    my @ar = split (/, */, $value);
                    @{$test[-1]->{$folder_name}->{$folder_attribute}->{$key1}} = @ar;
                    $uid = $key1;
                }
                elsif (/^(\w+)[:\s]*$/) {
                    my @ar;
                    @{$test[-1]->{$folder_name}->{$folder_attribute}->{$1}} = @ar;
                    $uid = $1;
                }
           }
        }
        elsif ($k == 5) {
            if ($is_test) {
                /^(\w+)\,*$/;
                $self->{logger}->debug("123 ".Dumper(@{$test[-1]->{$folder_name}->{$folder_attribute}}[-1]->{$uid}));
                push @{$test[-1]->{$folder_name}->{$folder_attribute}->{$uid}}, $1;
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
