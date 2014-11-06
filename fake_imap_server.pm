#!/usr/bin/perl
package fake_imap_server;

use strict;
use warnings;

use IO::Socket;
use IO::File;
use strict;
use warnings;
use Switch;
use Data::Dumper;
use POSIX;
use POSIX ":sys_wait_h";
use Log::Log4perl qw(:easy);


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
    $self->{connection_number} = -1;
    $self->{selected_folder} = "";
    $self->{fetch_num} = {};
    $self->{is_read_only} = 0;
    $self->{state} = 0;
    #States: 0 - non-authenticated, 1 - authenticated, 2 - selected, 3 - logout

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
        $self->parse_test_file1($self->{init_params}->{test});
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
        $self->{connection_number}++;
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
    my $bad_commands = 0;;
    $self->{state} = 0;
    $self->{logger}->info("client connected to pid $$");
    print $client "* OK Welcome to Fake Imap Server\r\n";

    while(my $line = <$client>) {
        chomp $line;
        if ($line =~ /^\s*(\w+)\s/) {
            $cmd_num = $1;
            $bad_commands = 0;
        }
        else {
            $self->notagged_send("BAD Unrecognised command (non-authenticated state)");
            $self->{logger}->debug(">>>: BAD Unrecognised command (non-authenticated state)");
            $self->{selected_folder} = "";
            $bad_commands++;
            if ($self->check_bad_commands($bad_commands)) {last;}
            next;
        }
        #$self->{selected_folder} = "Inbox";
        #$line = "A003 STORE 1:* -FLAGS (\\Deleted)";
        #$line = "A003 LOGOUT";
        $self->{logger}->debug("<<<: $line");

        if ($line =~ /login/i) {
            if ($mode) {
                if ($self->{imap}->{login}) {
                    if ($self->send_answer_from_config($self->{imap}->{login}, $cmd_num)) {
                        $self->{state} = 1;
                        next;
                    }
                }
            }
            $self->{logger}->debug(">>>: OK LOGIN completed");
            $self->tagged_send("OK LOGIN completed", $cmd_num);
            $self->{state} = 1;
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
            if ($self->{state} == 0) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
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
        elsif ($line =~ /list/i) { #same with xlist
            if ($self->{state} == 0) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
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
                    if ($self->run_cmd_logout($cmd_num)) {
                        last;
                        #next;
                    }
                }
            }
            $self->notagged_send("BYE Fake Imap Server logging out");
            $self->tagged_send("OK LOGOUT completed", $cmd_num);
            close $self->{client};
            last;
        }
        elsif ($line =~ /status/i) {
            if ($self->{state} == 0) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
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
            $line =~ /^\w+\s+STATUS\s+(.+)\s+\((.*)\)\s*$/i;
            my $folder = $1;
            if ($line =~ /inbox/i) {
                $self->notagged_send("STATUS $folder (UIDNEXT 2 MESSAGES 1 UIDVALIDITY 1)");
            }
            else {
                $self->notagged_send("STATUS $folder (UIDNEXT 1 MESSAGES 0 UIDVALIDITY 1)");
            }
            $self->tagged_send("OK STATUS Completed", $cmd_num);

        }
        elsif ($line =~ /select/i) {
            if ($self->{state} == 0) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            $self->{state} = 1;
            $self->{selected_folder} = "";
            if ($mode) {
                if ($self->{imap}->{"select"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"select"}, $cmd_num)) {
                        $self->{state} = 2;
                        next;
                    }
                }
                if ($self->run_cmd_select($cmd_num, $line, 0)) {
                    $self->{state} = 2;
                    next;
                }
            }
            unless ($line =~ /^\w+\s+SELECT\s+(\S+)\s*$/i) {
                $self->{state} = 1;
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            my $folder_with_quotes = $1;
            my $folder = (($folder_with_quotes =~ /^\"(.+)\"$/)? $1: $folder_with_quotes); 
            $self->{selected_folder} = $folder;

            $self->notagged_send("0 exists");
            $self->tagged_send("OK [READ-WRITE] SELECT Completed", $cmd_num);
            $self->{state} = 2;
        }
        elsif ($line =~ /examine/i) {
            if ($self->{state} == 0) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            $self->{state} = 1;
            $self->{selected_folder} = "";
            if ($mode) {
                if ($self->{imap}->{"examine"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"examine"}, $cmd_num)) {
                        $self->{state} = 2;
                        next;
                    }
                }
                if ($self->run_cmd_select($cmd_num, $line, 1)) {
                    $self->{state} = 2;
                    next;
                }
            }
            unless ($line =~ /^\w+\s+EXAMINE\s+(\S+)\s*$/i) {
                $self->{state} = 1;
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            my $folder_with_quotes = $1;
            my $folder = (($folder_with_quotes =~ /^\"(.+)\"$/)? $1: $folder_with_quotes); 
            $self->{selected_folder} = $folder;
            $self->notagged_send("0 exists");
            $self->tagged_send("OK [READ-ONLY] EXAMINE Completed", $cmd_num);
            $self->{state} = 2;
        }
        elsif ($line =~ /fetch/i) {
            unless ($self->{state} == 2) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            if ($mode) {
                if ($self->{imap}->{"fetch-body"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"fetch-body"}, $cmd_num)) {
                        next;
                    }
                }
                elsif ($self->{imap}->{"fetch"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"fetch-body"}, $cmd_num)) {
                        next;
                    }
                }
                if ($self->run_cmd_fetch($cmd_num, $line, 1)) {
                    next;
                }

            }
            if ($line =~ /body/) {
                $self->send_fake_msg($cmd_num);
            }
            else {
                $self->{logger}->debug(">>>: FETCH (UID 2147483647 FLAGS (\\Seen) INTERNALDATE \" 2-May-2014 17:12:07 +0000\")");
                $self->notagged_send("FETCH (UID 2147483647 FLAGS (\\Seen) INTERNALDATE \" 2-May-2014 17:12:07 +0000\")");
                $self->{logger}->debug(">>>: OK FETCH completed");
                $self->tagged_send("OK FETCH completed", $cmd_num);
            }
        }
        elsif ($line =~ /create/i) {
            if ($self->{state} == 0) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            if ($mode) {
                if ($self->{imap}->{"create"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"create"}, $cmd_num)) {
                        next;
                    }
                } 
            }
            $self->tagged_send("NO CREATE error", $cmd_num);
            $self->{logger}->debug(">>>: NO CREATE error"); 
        }
        elsif ($line =~ /rename/i) {
            if ($self->{state} == 0) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            if ($mode) {
                if ($self->{imap}->{"rename"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"rename"}, $cmd_num)) {
                        next;
                    }
                }
                if ($self->run_cmd_rename($cmd_num, $line)) {
                    next;
                }
            }
            $self->tagged_send("NO RENAME error", $cmd_num); 
            $self->{logger}->debug(">>>: NO RENAME error");
        }
        elsif ($line =~ /subscribe/i) {
            if ($self->{state} == 1) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            if ($mode) {
                if ($self->{imap}->{"subscribe"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"subscribe"}, $cmd_num)) {
                        next;
                    }
                }
            }
            $self->tagged_send("BAD SUBSCRIBE error: unsupported command", $cmd_num);
            $self->{logger}->debug(">>>: BAD SUBSCRIBE error: unsupported command", $cmd_num);
        }
        elsif ($line =~ /unsubscribe/i) {
            if ($self->{state} == 1) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            if ($mode) {
                if ($self->{imap}->{"unsubscribe"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"unsubscribe"}, $cmd_num)) {
                        next;
                    }
                }
            }
            $self->tagged_send("BAD UNSUBSCRIBE error: unsupported command", $cmd_num);
            $self->{logger}->debug(">>>: BAD UNSUBSCRIBE error: unsupported command", $cmd_num);
        }
        elsif ($line =~ /lsub/i) {
            if ($self->{state} == 1) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            if ($mode) {
                if ($self->{imap}->{"lsub"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"lsub"}, $cmd_num)) {
                        next;
                    }
                }
            }
            $self->tagged_send("BAD LSUB error: unsupported command", $cmd_num);
            $self->{logger}->debug(">>>: BAD LSUB error: unsupported command", $cmd_num);
        }
        elsif ($line =~ /append/i) {
            if ($self->{state} == 1) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            if ($mode) {
                if ($self->{imap}->{"append"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"append"}, $cmd_num)) {
                        next;
                    }
                }
            }
            $self->tagged_send("BAD APPEND error: unsupported command", $cmd_num);
            $self->{logger}->debug(">>>: BAD APPEND error: unsupported command", $cmd_num);
        }
        elsif ($line =~ /check/i) {
            unless ($self->{state} == 2) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            if ($mode) {
                if ($self->{imap}->{"check"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"check"}, $cmd_num)) {
                        next;
                    }
                }
            }
            $self->tagged_send("OK CHECK completed", $cmd_num); 
            $self->{logger}->debug(">>>: OK CHECK completed");
        }
        elsif ($line =~ /unselect/i) {
            if ($self->{state} == 0) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            $self->{state} = 1;
            $self->{selected_folder} = "";
            if ($mode) {
                if ($self->{imap}->{"unselect"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"unselect"}, $cmd_num)) {
                        next;
                    }
                }
                if ($self->run_cmd_unselect($cmd_num, $line)) {
                    next;
                }
            }
            $self->tagged_send("OK UNSELECT completed", $cmd_num); 
            $self->{logger}->debug(">>>: OK UNSELECT completed");
        }
        elsif ($line =~ /expunge/i) {
            unless ($self->{state} == 2) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            if ($mode) {
                if ($self->{imap}->{"expunge"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"expunge"}, $cmd_num)) {
                        next;
                    }
                }
                if ($self->run_cmd_expunge($cmd_num, $line)) {
                    next;
                }
            }
            $self->tagged_send("OK EXPUNGE completed", $cmd_num); 
            $self->{logger}->debug(">>>: OK EXPUNGE completed");
        }
        elsif ($line =~ /search/i) {
           unless ($self->{state} == 2) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
           }
           if ($mode) {
                if ($self->{imap}->{"search"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"search"}, $cmd_num)) {
                        next;
                    }
                }
            }
            $self->tagged_send("BAD SEARCH error: unsupported command", $cmd_num);
            $self->{logger}->debug(">>>: BAD SEARCH error: unsupported command", $cmd_num);
        }
        elsif ($line =~ /store/i) {
            unless ($self->{state} == 2) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            if ($mode) {
                if ($self->{imap}->{"store"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"store"}, $cmd_num)) {
                        next;
                    }
                }
                if ($self->run_cmd_store($cmd_num, $line)) {
                    next;
                }
            }
            $self->tagged_send("OK STORE completed", $cmd_num); 
            $self->{logger}->debug(">>>: OK STORE completed");
        }
        elsif ($line =~ /uid copy/i) {
            unless ($self->{state} == 2) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            if ($mode) {
                if ($self->{imap}->{"copy"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"copy"}, $cmd_num)) {
                        next;
                    }
                }
            }
            $self->tagged_send("NO COPY error", $cmd_num);
            $self->{logger}->debug(">>>: NO COPY error");
        }
        elsif ($line =~ /close/i) {
            unless ($self->{state} == 2) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            $self->{selected_folder} = "";
            $self->{state} = 1;
            if ($mode) {
                if ($self->{imap}->{"close"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"close"}, $cmd_num)) {
                        next;
                    }
                }
                if ($self->run_cmd_close($cmd_num, $line)) {
                    next;
                }
            }
            $self->tagged_send("OK CLOSE completed", $cmd_num); 
            $self->{logger}->debug(">>>: OK CLOSE completed");
        }
        elsif ($line =~ /delete/i) {
            if ($self->{state} == 0) {
                $self->tagged_send("BAD Error in IMAP command received by Fake Imap Server.", $cmd_num);
                if ($self->check_bad_commands($bad_commands)) {last;}
                next;
            }
            if ($mode) {
                if ($self->{imap}->{"delete"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"delete"}, $cmd_num)) {
                        next;
                    }
                }
                if ($self->run_cmd_delete($cmd_num, $line)) {
                        next;
                }
            }
            $self->tagged_send("OK DELETE completed", $cmd_num);
            $self->{logger}->debug(">>>: OK DELETE completed");
        }
        else {
            if ($mode) {
                if ($self->{imap}->{"bad_command"}) {
                    if ($self->send_answer_from_config($self->{imap}->{"bad_command"}, $cmd_num)) {
                        next;
                    }
                }
            }
            $self->notagged_send("BAD Unrecognised command (non-authenticated state)");
            $self->{logger}->debug(">>>: $cmd_num BAD Unrecognised command (non-authenticated state)");
            $self->{selected_folder} = "";
        }
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
            unless ($flag =~ /\d+\-\w+\-\d+\s*+\d+\:\d+:\d+\s+\+?\d*\s*/) {
                unless ($answer =~ /\($/) {
                    $answer .= " ";
                }
                $answer .= "\\$flag";
            }
        }
        $answer .= ") \"/\" \"$folder\"";
        $self->notagged_send($answer);
        $self->{logger}->debug(">>>: $answer");
    }
    $self->tagged_send("OK LIST completed", $cmd_num);
    $self->{logger}->debug(">>>: OK LIST completed");
    return 1;
}

sub check_bad_commands {
    my $self = shift;
    my $bad_commands = shift;
    if ($bad_commands == 3) {
        $self->notagged_send("BYE Too many invalid IMAP commands");
        $self->{logger}->debug(">>>: BYE Too many invalid IMAP commands");
        close $self->{client};
        return 1;
    }
    return -1;
}

sub run_cmd_status {
    my $self = shift;
    my $cmd_num = shift;
    my $status = shift;

    my %folders = %{$self->{test}[$self->{connection_number}]};
    unless (%folders) {return -1;}

    if ($status =~ /^\w+\s+STATUS\s+(.+)\s+\((.*)\)\s*$/i) {
        my $need_space = 0;
        my $folder_with_quotes = $1;
        my $flags = $2." RECENT ";
        my $folder = (($folder_with_quotes =~ /^\"(.+)\"$/)? $1: $folder_with_quotes);
        my $answer = "STATUS ".$folder_with_quotes." (";

        if ($flags =~ /MESSAGES/i) {
            $answer .= "MESSAGES ".$self->get_msg_amount(\%{$folders{$folder}{"uids"}});
            $need_space = 1;
        }
        if ($flags =~ /RECENT/i) {
            if ($need_space) {$answer .= " ";}
            $answer .= "RECENT ".$self->get_recent_uids(\%{$folders{$folder}{"uids"}});
            $need_space = 1;
        }
        if ($flags =~ /UIDNEXT/i) {
            if ($need_space) {$answer .= " ";}
            $answer .= "UIDNEXT ".$self->get_uidnext(\%{$folders{$folder}{"uids"}});
            $need_space = 1;
        }
        if ($flags =~ /UIDVALIDITY/i) {
            if ($need_space) {$answer .= " ";}
            $answer .= "UIDVALIDITY ".$self->get_uidvalidity(\%{$folders{$folder}});
            $need_space = 1;
        }
        if ($flags =~ /UNSEEN/i) {
            if ($need_space) {$answer .= " ";}
            $answer .= "UNSEEN ".$self->get_unseen_uids(\%{$folders{$folder}{"uids"}});
            $need_space = 1;
        }
        $answer .= ")";
        $self->notagged_send($answer);
        $self->{logger}->debug(">>>: $answer");
        $self->tagged_send("OK STATUS completed", $cmd_num);
        $self->{logger}->debug(">>>: OK STATUS completed");
        return 1;
    }
    $self->tagged_send("BAD STATUS error", $cmd_num);
    $self->{logger}->debug(">>>: BAD STATUS error");
    return 1;
}

sub run_cmd_select {
    my $self = shift;
    my ($cmd_num, $select, $is_examine) = @_;

    my %folders = %{$self->{test}[$self->{connection_number}]};
    $self->{selected_folder} = "";
    unless (%folders) {
        return -1;
    }

    $self->notagged_send("FLAGS ()");
    $self->notagged_send("OK [PERMANENTFLAGS] ()");

    $self->{logger}->debug(">>>: FLAGS ()");
    $self->{logger}->debug(">>>: OK [PERMANENTFLAGS] ()");


    unless ($select =~ /^\w+\s+(SELECT|EXAMINE)\s+(\S+)\s*$/i) {
        $self->{selected_folder} = "";
        $self->tagged_send("BAD SELECT error", $cmd_num);
        $self->{logger}->debug(">>>: BAD SELECT error");
        return 1;
    }
    my $folder_with_quotes = $2;
    my $folder = (($folder_with_quotes =~ /^\"(.+)\"$/)? $1: $folder_with_quotes); 
   
    $self->{selected_folder} = $folder;
    
    my $n = $self->get_msg_amount(\%{$folders{$folder}{"uids"}});
    $self->notagged_send("$n EXISTS");
    $self->{logger}->debug(">>>: $n EXISTS");

    $n = $self->get_recent_uids(\%{$folders{$folder}{"uids"}});
    $self->notagged_send("$n RECENT");
    $self->{logger}->debug(">>>: $n RECENT");

    $n = $self->get_unseen_uids(\%{$folders{$folder}{"uids"}});
    $self->notagged_send("OK [UNSEEN $n]");
    $self->{logger}->debug(">>>: OK [UNSEEN $n]");

    $n = $self->get_uidvalidity(\%{$folders{$folder}});
    $self->notagged_send("OK [UIDVALIDITY $n] UIDs valid");
    $self->{logger}->debug(">>>: OK [UIDVALIDITY $n] UIDs valid");

    $n = $self->get_uidnext(\%{$folders{$folder}{"uids"}});
    $self->notagged_send("OK [UIDNEXT $n] Predicted next UID");
    $self->{logger}->debug(">>>: OK [UIDNEXT $n] Predicted next UID");

    if ($is_examine) {
        $self->{is_read_only} = 1;
        $self->tagged_send("OK [READ-ONLY] EXAMINE completed", $cmd_num);
        $self->{logger}->debug(">>>: OK [READ-ONLY] EXAMINE completed");
    }
    else {
        $self->{is_read_only} = 0;
        $self->tagged_send("OK [READ-WRITE] SELECT completed", $cmd_num);
        $self->{logger}->debug(">>>: OK [READ-WRITE] SELECT completed");
    }
    return 1;
}

sub run_cmd_logout {
    my $self = shift;
    my ($cmd_num, $fetch) = @_;

    $self->{selected_folder} = "";
    $self->notagged_send("BYE Fake Imap Server logging out");
    $self->tagged_send("OK LOGOUT completed", $cmd_num);
    close $self->{client};
    return 1;
}

sub run_cmd_store {
    my $self = shift;
    my ($cmd_num, $store) = @_;

    my %folders = %{$self->{test}[$self->{connection_number}]};
    my $folder  = $self->{selected_folder};
    unless (defined $folder) {
        $self->tagged_send("NO STORE error: no folder selected", $cmd_num);
        $self->{logger}->debug(">>>: NO STORE error: no folder selected");
        return 1;
    }
    unless (defined $self->{fetch_num}->{$folder}) {
        $self->{fetch_num}->{$folder} = {counter => 1};
    }
    if ($store =~ /^\s*\w+\s+STORE\s+([\d\:\*\,]+)\s+(\+?\-?FLAGS)(\.SILENT)?\s*\(([\w\s\\]*)\)\s*$/i) {
        unless ($1 or $2) {
            $self->tagged_send("BAD STORE error: uncorrect arguments", $cmd_num);
            $self->{logger}->debug(">>>: BAD STORE error: uncorrect arguments");
            return 1;
        }

        my $str_uids = $1;
        my $flag_operation = $2;
        my $flags = $4;
        my $silent = ($3? 1: 0);
        
        my @uids = ();
        my $state = -1;
        if ($str_uids =~ /:/) {
            @uids = split (':', $str_uids);
            if ($uids[1] eq '*') {$state = 1;}
            else {$state = 2;}
        }
        elsif ($str_uids =~ /,/) {
            @uids = split (',', $str_uids);
            $state = 3;
        }
        elsif ($str_uids =~ /^(\d+)$/) {
            push @uids, $1;
            $state = 3;
        }
        foreach my $test (@{$self->{test}}) {
            if ($test->{$folder}) {
                foreach my $uid (keys %{$test->{$folder}->{uids}}) {
                    my $ok = 0;
                    switch ($state) {
                        case 1 {
                                if ($uid >= $uids[0]) {$ok = 1;}
                            }
                        case 2 {
                                if ($uid >= $uids[0] and $uid <= $uids[1]) {$ok = 1;}
                            }
                        case 3 {
                                if ($uid ~~ \@uids) {$ok = 1;}
                            }
                    }
                    if ($ok) {
                        my @flags_ar = split(/[\s,\\]+/, $flags);
                        unless ($flags_ar[0]) {shift @flags_ar;}
                        #my @flags_ar = ("deleted", "seen", "omnmo", "qqq", "www");
                        if (lc $flag_operation eq lc "FLAGS") {
                            @{$test->{$folder}->{uids}->{$uid}} = @flags_ar;
                        }
                        elsif (lc $flag_operation eq lc "+FLAGS") {
                            foreach my $flag (@flags_ar) {
                                unless (/$flag/i ~~ \@{$test->{$folder}->{uids}->{$uid}}) {
                                    push @{$test->{$folder}->{uids}->{$uid}}, $flag;
                                }
                            }
                        }
                        else { #-FLAGS
                            my @ar = @{$test->{$folder}->{uids}->{$uid}};
                            my $n = $#ar + 1;
                            for (my $i = 0; $i < $n; $i++) {
                                my $flag = $test->{$folder}->{uids}->{$uid}[$i];
                                if (/$flag/i ~~ \@flags_ar) {
                                    splice  @{$test->{$folder}->{uids}->{$uid}}, $i, 1;
                                    $n--;
                                    $i--;
                                }
                            }
                        }
                        unless ($self->{fetch_num}->{$folder}->{$uid}) {
                            $self->{fetch_num}->{$folder}->{$uid} = $self->{fetch_num}->{$folder}->{"counter"};
                            $self->{fetch_num}->{$folder}->{"counter"}++;
                        }
                        my $flag_list_for_fetch = "(";
                        foreach my $ff (@{$test->{$folder}->{uids}->{$uid}}) {
                            unless ($ff =~ /\d+\-\w+\-\d+\s*+\d+\:\d+:\d+\s+\+?\d*\s*/) {
                                $flag_list_for_fetch .= "\\$ff ";
                            }
                        }
                        $flag_list_for_fetch .= ")";
                        $self->notagged_send($self->{fetch_num}->{$folder}->{$uid}." FETCH FLAGS $flag_list_for_fetch");
                        $self->{logger}->debug(">>>: ".$self->{fetch_num}->{$folder}->{$uid}." FETCH FLAGS $flag_list_for_fetch");
                    }
                }
            }
        }
    }
    $self->tagged_send("OK STORE completed", $cmd_num);
    $self->{logger}->debug(">>>: OK STORE completed");
    return 1;
}

sub run_cmd_fetch {
    my $self = shift;
    my ($cmd_num, $fetch) = @_;

    my %folders = %{$self->{test}[$self->{connection_number}]};
    my $folder  = $self->{selected_folder};
    unless (defined $folder) {
        $self->tagged_send("NO EXPUNGE error: no folder selected", $cmd_num);
        $self->{logger}->debug(">>>: NO EXPUNGE error: no folder selected");
        return 1;
    }
    unless (defined $self->{fetch_num}->{$folder}) {
        $self->{fetch_num}->{$folder} = {counter => 1};
    }

    if ($fetch =~ /body/i) {
        if ($self->{init_params}->{message}) {
            my $file = $self->{init_params}->{message};
            my $fh = new IO::File;
            my $fake_message = "";
            if ($fh->open("< $file")) {
                while (<$fh>) {
                    $fake_message .= $_;
                }
                $fh->close();

                my $length = length($fake_message);

                $fetch =~ /^\s*\w+\s+UID\s+FETCH\s+(\d+)/;
                my $uid = $1;
                my $client = $self->{client};
                my $fetch_id = $self->{fetch_num}->{$folder}->{$uid};

                unless ($fetch_id or $uid or $length ) {
                    return -1;
                }

                eval {
                    print $client "* $fetch_id FETCH (UID $uid BODY[] {$length}\r\n";
                    print $client $fake_message;
                    print $client ")\r\n";
                    print $client "$cmd_num OK FETCH BODY completed\r\n";
                };
                if ($@) {
                    $self->{logger}->error("fake message send error");
                    return -1;
                }
                return 1;
            }
            else {
                $self->{logger}->info("file with fake message ($file)not found\n");
            }
        }
        unless ($self->send_fake_msg($cmd_num)) {return -1;}
        return 1;
    }
    if ($fetch =~ /^\s*\w+\s+UID\s+FETCH\s+(\d+)\:?([\d,\*]+)?\s+\(([\w\s]*)\)\s*$/) {
        my $fuid = $1;
        my $fflags = $3;
        my $answer;
        if ($2) {
             my $right = $2; 
             my $uids = $folders{$folder}{"uids"};
             if ($right eq "*") {
                foreach my $uid (sort keys %{$uids}) {
                    unless ($self->{fetch_num}->{$folder}->{$uid}) {
                        $self->{fetch_num}->{$folder}->{$uid} = $self->{fetch_num}->{$folder}->{"counter"};
                        $self->{fetch_num}->{$folder}->{"counter"}++;
                    }
                    $answer = $self->run_fetch_uid($uid, $fflags, $uids->{$uid});
                    if ($uid >= $fuid) {
                        $self->{logger}->debug(">>>: $answer");
                        $self->notagged_send($answer);
                    }
                }
             }
        }
        else {
            my $uid = $folders{$folder}{"uids"}->{$fuid};
            unless ($self->{fetch_num}->{$folder}->{$fuid}) {
                $self->{fetch_num}->{$folder}->{$fuid} = $self->{fetch_num}->{$folder}->{"counter"};
                $self->{fetch_num}->{$folder}->{"counter"}++;
            }
            $answer = $self->run_fetch_uid($fuid, $fflags, $uid);

            $self->{logger}->debug(">>>: $answer");
            $self->notagged_send($answer);
        }
        $self->{logger}->debug(">>>: OK FETCH completed");
        $self->tagged_send("OK FETCH completed", $cmd_num);
        return 1;
    }
    return -1;
}

sub run_fetch_uid {
    my $self = shift;
    my ($fuid, $fflags, $uid) = @_;
    my $folder  = $self->{selected_folder};
    my $answer = $self->{fetch_num}->{$folder}->{$fuid}." FETCH (UID $fuid ";
    my $date = "";
    my $uid_flags = "";
    
    foreach my $flag (@{$uid}) {
        if ($flag =~ /\d+\-\w+\-\d+\s*+\d+\:\d+:\d+\s+\+?\d*\s*/) {
            $date = $flag;
        }
        else {
            $uid_flags .= "\\$flag ";
        }
                    
    }
    if ($fflags =~ /internaldate/i) {
        if ($date) {
            $answer .= "INTERNALDATE \"$date\" ";
        }
    }
    if ($fflags =~ /flags/i) {
        $answer .= "FLAGS ($uid_flags)";
    }
    $answer .= ")";
    return $answer;
}

sub send_fake_msg {
    my $self = shift;
    my $cmd_num = shift;
    my $fake_message = "From: aaaaa <aaaaa\@mail.ru>\r\nTo: bbbbb <bbbbb\@mail.ru>\r\nSubject: this is just subject\r\n";
    $fake_message .= "Date: Wed, 23 Jul 2014 17:53:07 +0400\r\n";
    $fake_message .= "\r\n";
    $fake_message .= "This is just fake message\r\nTo testing our imap-collector\r\n";
    $fake_message .= "On memory leaks\r\n";

    my $length = length($fake_message);
    my $client = $self->{client};
    eval {
        print $client "* 1 FETCH (UID 587 BODY[] {$length}\r\n";
        print $client $fake_message;
        print $client ")\r\n";
        print $client "$cmd_num OK FETCH BODY completed\r\n";
    };
    if ($@) {
        $self->{logger}->error("fake message send error");
        return -1;
    }
    return 1;
}

sub run_cmd_delete {
    my $self = shift;
    my ($cmd_num, $delete) = @_;

    my %folders = %{$self->{test}[$self->{connection_number}]};
    unless (%folders) {return -1;}
    
    #unless ($delete =~ /^\s*\w+\s+DELETE\s+\"?(\w+)\"?\s*$/i) {
    #    return -1;
    #}

    my @ar = split('\s', $delete);
    my $del_folder = $ar[2];
    if ($ar[2] =~ /^\"(.+)\"$/) {
        $del_folder = $1;
    }
    unless ($folders{$del_folder}) {
        $self->{logger}->debug(">>>: NO DELETE error");
        $self->tagged_send("NO DELETE error", $cmd_num);
    }
    if ($del_folder =~ /Inbox/i) {
        $self->{logger}->debug(">>>: NO DELETE error");
        $self->tagged_send("NO DELETE error", $cmd_num);
        return 1;
    }
    foreach my $flag (@{$folders{$del_folder}{"flags"}}) {
        if ($flag =~ /Noselect/i) {
            $self->{logger}->debug(">>>: NO DELETE error");
            $self->tagged_send("NO DELETE error", $cmd_num);
            return 1;
        }
    }
    #$del_folder = $1;
    foreach my $test (@{$self->{test}}) {
        if ($test->{$del_folder}) {
            delete($test->{$del_folder});
        }
    }
    $self->{logger}->debug(">>>: OK DELETE completed");
    $self->tagged_send("OK DELETE completed", $cmd_num);
    return 1;
}

sub run_cmd_rename {
    my $self = shift;
    my ($cmd_num, $rename) = @_;

    my @ar = split('\s', $rename);
    my $destiny = $ar[3];
    my $source = $ar[2];
    
    if ($destiny =~ /^\"(.+)\"$/) {
        $destiny = $1;
    }
    if ($source =~ /^\"(.+)\"$/) {
        $source = $1;
    }
    unless ($destiny or $$source) {
        $self->{logger}->debug(">>>: BAD RENAME error");
        $self->tagged_send("BAD RENAME error", $cmd_num);
        return 1;
    }
    foreach my $test (@{$self->{test}}) {
        if ($test->{$source}) {
            my %hash = %{$test->{$source}};
            delete($test->{$source});
            %{$test->{$destiny}} = %hash;
        }
    }
    if ($source =~ /Inbox/i) {
        foreach my $test (@{$self->{test}}) {
            %{$test->{"Inbox"}} = ();
        }
    }
    $self->{logger}->debug(">>>: OK RENAME completed");
    $self->tagged_send("OK RENAME completed", $cmd_num);
    return 1;
}

sub run_cmd_expunge {
    my $self = shift;
    my ($cmd_num, $expunge) = @_;

    my %folders = %{$self->{test}[$self->{connection_number}]};
    my $folder  = $self->{selected_folder};
    unless ($self->{selected_folder}) {
        $self->tagged_send("NO EXPUNGE error: no folder selected", $cmd_num);
        $self->{logger}->debug(">>>: NO EXPUNGE error: no folder selected");
        return 1;
    }
    foreach my $uid (keys %{$folders{$self->{selected_folder}}->{uids}}) {
        $self->{logger}->debug(">>>: $uid EXPUNGE");
        $self->notagged_send("$uid EXPUNGE");
        if (/deleted/i ~~ \@{$folders{$self->{selected_folder}}->{uids}->{$uid}}) {
            delete($folders{$self->{selected_folder}}->{uids}->{$uid});
        }
    }
    $self->{selected_folder} = "";
    $self->{logger}->debug(">>>: OK EXPUNGE completed");
    $self->tagged_send("OK EXPUNGE completed", $cmd_num);
    return 1;
}

sub run_cmd_close {
    my $self = shift;
    my ($cmd_num, $close) = @_;

    my %folders = %{$self->{test}[$self->{connection_number}]};
    my $folder  = $self->{selected_folder};
    unless ($self->{selected_folder}) {
        $self->{logger}->debug(">>>: NO CLOSE error: no folder selected");
        $self->tagged_send("NO CLOSE error: no folder selected", $cmd_num);
        return 1;
    }
    unless ($self->{is_read_only}) {
        foreach my $uid (keys %{$folders{$self->{selected_folder}}->{uids}}) {
            if (/deleted/i ~~ \@{$folders{$self->{selected_folder}}->{uids}->{$uid}}) {
                delete($folders{$self->{selected_folder}}->{uids}->{$uid});
            }
        }
    }
    $self->{selected_folder} = "";
    $self->{logger}->debug(">>>: OK CLOSE completed");
    $self->tagged_send("OK CLOSE completed", $cmd_num);
    return 1;

}

sub run_cmd_unselect {
    my $self = shift;
    my ($cmd_num, $unselect) = @_;
    unless ($self->{selected_folder}) {
        $self->{logger}->debug(">>>: BAD UNSELECT error: no folder selected");
        $self->tagged_send("BAD UNSELECT error: no folder selected", $cmd_num);
        return 1;
    }
    $self->{selected_folder} = "";
    $self->{logger}->debug(">>>: OK UNSELECT completed");
    $self->tagged_send("OK UNSELECT completed", $cmd_num);
    return 1;
}

sub tagged_send {
    my $self = shift;
    my $str = $_[0];
    my $num = $_[1];
    my $client = $self->{client};

    eval {print $client "$num $str\r\n";};
    if ($@) {
        $self->{logger}->error("Tagged command send error");
    }
}

sub notagged_send{
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

sub get_msg_amount {
    my ($self, $folder) = @_;
    return (%{$folder} ? scalar(keys %{$folder}): 0);
}

sub get_recent_uids {
    my ($self, $folder) = @_;
    my $n = 0;
    if (%{$folder}) { 
        foreach my $uid (keys %{$folder}) {
            if (/recent/i ~~ \@{$folder->{$uid}}) {
                $n++;
            }
        }
    }
    return $n;
}

sub get_unseen_uids {
    my ($self, $folder) = @_;
    my $n = 0;
    if (%{$folder}) {
        foreach my $uid (keys %{$folder}) {
            unless (/seen/i ~~ \@{$folder->{$uid}}) {
                $n++;
            }
        }
    }
    return $n;
}

sub get_seen_uids {
    my ($self, $folder) = @_;
    my $n = 0;
    if (%{$folder}) {
        foreach my $uid (keys %{$folder}) {
            if (/seen/i ~~ \@{$folder->{$uid}}) {
                $n++;
            }
        }
    }
    return $n;
}

sub get_uidnext {
    my ($self, $folder) = @_;
    my $uid_next = 0;
    if (%{$folder}) {
        foreach my $key (keys %{$folder}) {
            if ($key > $uid_next) {
                $uid_next = $key;
            }
        }
    }
    $uid_next += 1;
    return $uid_next;
}

sub get_uidvalidity {
    my ($self, $folder) = @_;
    return ($folder->{"uidvalidity"}) ? $folder->{"uidvalidity"}:"123456";
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

                    @{$test[-1]->{$folder_name}->{$key1}} = @ar;
                    $folder_attribute = $key1;
                }
                elsif (/^(\w+)[:\s]*$/) {
                    my @ar;
                    @{$test[-1]->{$folder_name}->{$1}} = @ar;
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
                    my %hash = ($key1 => \@ar);
                    push @{$test[-1]->{$folder_name}->{$folder_attribute}}, \%hash;
                }
                elsif (/^(\w+)[:\s]*$/) {
                    my @ar;
                    my %hash = ($1 => \@ar);
                    push @{$test[-1]->{$folder_name}->{$folder_attribute}}, \%hash;
                    $uid = $1;
                }
           }
        }
        elsif ($k == 5) {
            if ($is_test) {
                /^(\w+)\,*$/;
                push @{@{$test[-1]->{$folder_name}->{$folder_attribute}}[-1]->{$uid}}, $1;
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

sub parse_test_file1 {
    my $self = shift;
    my $test_file = shift;

    my $fh = new IO::File;
    unless ($fh->open("$test_file")) {
        die "file($test_file) with imap tests not found\n";
    }

    my @brackets;
    my %glhash;

    eval {
        if ($self->do_parse($fh, \%glhash, 0, \@brackets) <= 0) {
            warn "ERROR in parsing\n";
            $fh->close();
            return -1;
        } else {
            $self->{test} = \@{$glhash{test}}; #\@test;
            $self->{imap} = \%{$glhash{imap}}; #\%imap;
        }
    };
    if ($@) {
        warn "start server error, check your config file, $@\n";
    }

    $fh->close();
    #print Dumper(%glhash);
}

sub do_parse {
    my $self = shift;
    my $fh = shift; #указатель на файл
    my $it = shift; # ссылка на предыдущую структуру
    my $is_ar = shift; # тип предыдущей структуры - хэш или массив
    my $brackets = shift; #ссылка на массив со скобками

    $self->{logger}->debug("FUNCTION do_parse,".Dumper($it));

    my $prev_line;
    my $is_first = 1;

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
            push @{$brackets}, '}'; #type of expected closing bracket
            if ($is_ar) {
                my %hash;
                push @{$it}, \%hash;
                if ($self->do_parse($fh, \%{$it->[-1]}, 0, $brackets) <= 0) {return -1;}
            }
            else {
                %{$it->{$prev_line}} = ();
                if ($self->do_parse($fh, \%{$it->{$prev_line}}, 0, $brackets) <= 0) {return -1;}
            }
            $is_first = 1;
            next;
        }
        if (/^\[$/) {
            push @{$brackets}, ']';
            if (!$is_ar and $is_first) {return -1;}
            if ($is_ar) {
                my @ar;
                push @{$it}, \@ar;
                if ($self->do_parse($fh, \@{$it->[-1]}, 1, $brackets) <= 0) {return -1;}
            }
            else {
                @{$it->{$prev_line}} = ();
                if ($self->do_parse($fh, \@{$it->{$prev_line}}, 1, $brackets) <= 0) {return -1;}
            }
            $is_first = 1;
            next;
        }
        if (/^\]/) {
            my $last = pop @{$brackets};
            unless ($last eq ']') {
                $self->{logger}->debug("Syntax error in config, check ] brackets");
                return -1;
            }
            if (!$is_first) {
                push @{$it}, $prev_line;
            }
            return 1;
        }
        if (/^\}/) {
            my $last = pop @{$brackets};
            unless ($last eq '}') {
                $self->{logger}->debug("Syntax error in config, check } brackets, ");
                return -1;
            }
            if ($is_first) {
                return 1;
            } else {
                $self->{logger}->debug("Syntax error in config, check {} or [] brackets, ");
                return -1;
            }
            next;
        }

        if (/^$/) {next;}
        if (/^\#/) {next;}
        if ($is_first) {
            $prev_line = $_;
            $is_first = 0;
            if (/^(\w+)[:]?\s*[\(\[]\s*([\s\,\w\(\)]*)[\]\)]\,*\s*$/) {
                my $key = $1;
                my $value = $2;
                my @ar = split (/, */, $value);
                @{$it->{$key}} = @ar;
                $is_first = 1;
            }
            elsif (/^(\w+)[:]?\s*\{\s*([\s\,\w\(\),\:,\=,\>]*)\}\,?\s*$/) {
                print "unsupported type of hash, check your config\n";
                return -1;
            }
            elsif (/^(\w+)\s*\:\"?\s*(\w+)\s*\"?\s*\,?$/) {
                $it->{$1} = $2;
                $is_first = 1;
            }
            elsif (/^\s*\[\s*([\s\,\w\(\)]*)\s*\]\,?\s*$/) {
                my $value = $1;
                my @ar = split (/, */, $value);
                push @{$it}, \@ar;
                $is_first = 1;
            }
            elsif  (!$is_ar and /^\s*\[/) {
                return -1;
            }
            elsif (/(.+):\s*$/) {
                $prev_line = $1;
            }
        } else {
            if ($is_ar) {
                push @{$it}, $prev_line;
                $prev_line = $_;
            } else {
                $self->{logger}->debug("Syntax error in config, check {} or [] brackets, "); 
                return -1;
            }
        }
    }
    return 1;
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

    while (my $line = <$fh>) {
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
