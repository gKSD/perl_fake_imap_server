#!/usr/bin/perl -I/usr/local/mpop/lib/

use IO::File;
use Switch;
use Data::Dumper;
use DBI;
use Time::HiRes qw(gettimeofday);

use Mailbox;
use mPOP;
use mPOP::Domain (preload=>1);
use PMescalito();
use mPOP::MescFolders();

sub print_help {
    print "Usage:\n";
    print "  obligatory: \n";
    print "    --test [-t] =</dir/test_file>\n";
    print "  optional: \n";
    print "    --imap_config [-c] =</dir/config_file>\n";
    print "    --help [-h]\n";
    print "\nCollector params (for rpop.imap table):\n";
    print "    --UserID=<user_id>\n";
    print "    --UserEmail=<user_email>\n";
    print "    --Host=<imap_srever_host>\n";
    print "    --Email=<email>";
    print "    --User=<user name (default: same with Email)>\n";
    print "    --Password=<password>\n";
    print "    --Flags=<collector flags>\n";
    print "    --Folder=<folder id for collecting inbox letters>\n";
    print "    --Port=<imap server port>\n";
    print "    --ConnectionMode=<ssl|no-ssl>\n";
    print "    --AutoConfigure=<yes|no>\n";
    print "    --ContactFetchRetries=<number of retries>\n";
    print "\n Mysql params: \n";
    print "    --mysql_host=<host>\n";
    print "    --mysql_user=<username>\n";
    print "    --mysql_password=<password>\n";
}

my $args = shift @ARGV;
my %parsed_args;

#default values, may be changed while parsing config or ARGV
$parsed_args{"mysql_host"} = "localhost";
$parsed_args{"mysql_user"} = "mpop";
$parsed_args{"mysql_password"} = '';

if (defined $args) {
    if ($args eq '-h' or $args eq '--help') {
        print_help();
        exit;
    }
    else {
        while(defined $args) {
            if (my @fields = $args =~ /^\-\-(\w+)\=([\w\.\/@]+)$/g) {
                $parsed_args{$fields[0]} = $fields[1];
            }
            elsif ($args =~ /^\-[hplcts]$/g) {
                my $param = $args;
                if(defined ($_ = shift @ARGV) and (m/^([\w\.\/]+)$/)) {
                    switch ($param) {
                        case '-t' { $param = 'test' }
                        case '-c' { $param = 'imap_config' }
                    }
                    $parsed_args{$param} = $_;
                }
                else {
                    warn "1 unrecognized param found (It should be like: '-p param_value' or '--param=param_value')\n";
                }
            }
            else {
                warn "2 unrecognized param found (It should be like: '-p param_value' or '--param=param_value')\n";
            }
            $args = shift @ARGV;
        }
    }
}

unless ($parsed_args{"test"}) {
    print "option --test [-t] is obligatory\n";
    print_help();
    exit;
}

sub parse_imap_config {
    my $config_file = shift;
    my $result = shift;
    my $fh = new IO::File;
    unless ($fh->open("< $config_file"))
    {
        warn "config_file ($config_file) not found\n";
        return;
    }

    my $do_add = 0;
    while (my $line = <$fh>) {
        chomp $line;
        warn "line = $line\n";
        $do_add = 1;
        if ($line =~ /^\s*(\w+)\s+\"?([\w\.\/\@]*)\"?\s*$/) {
            #my $key = lc $1;
            my $key = $1;
            my $value = $2;
            $result->{$key} = $value;
        }
    }
    $fh->close;
}

sub do_parse {
    my $fh = shift; #указатель на файл
    my $it = shift; # ссылка на предыдущую структуру
    my $is_ar = shift; # тип предыдущей структуры - хэш или массив
    my $brackets = shift; #ссылка на массив со скобками

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
                if (!$is_first) {
                    if ($prev_line =~ /^\s*\[\s*([^\f\n\r\t\v]*)\s*\]\,?\s*$/) {
                        my $value = $1;
                        my @ar = split (/, */, $value);
                        my $n = $#ar + 1;
                        for (my $i = 0; $i < $n; $i++) {
                            if ($ar[$i] =~ /^\"(.*)\"$/) {$ar[$i] = $1;}
                        }
                        push @{$it}, \@ar;
                        $is_first = 1;
                    }
                    elsif ($prev_line =~ /^\"(.*)\"$/) {
                        push @{$it}, $1;
                    }
                    else{
                        $prev_line =~ s/\s+$//g;
                        if ($prev_line =~ /[\:\,\;\-\=]$/) { chop $prev_line;}
                        push @{$it}, $prev_line;
                    }
                } 
                my %hash;
                push @{$it}, \%hash;
                if (do_parse($fh, \%{$it->[-1]}, 0, $brackets) <= 0) {return -1;}
            }
            else {
                %{$it->{$prev_line}} = ();
                if (do_parse($fh, \%{$it->{$prev_line}}, 0, $brackets) <= 0) {return -1;}
            }
            $is_first = 1;
            next;
        }
        if (/^\[$/) {
            push @{$brackets}, ']';
            if (!$is_ar and $is_first) {return -1;}
            if ($is_ar) {
                if (!$is_first) {
                    if ($prev_line =~ /^\s*\[\s*([^\f\n\r\t\v]*)\s*\]\,?\s*$/) {
                        my $value = $1;
                        my @ar = split (/, */, $value);
                        my $n = $#ar + 1;
                        for (my $i = 0; $i < $n; $i++) {
                            if ($ar[$i] =~ /^\"(.*)\"$/) {$ar[$i] = $1;}
                        }
                        push @{$it}, \@ar;
                        $is_first = 1;
                    }
                    elsif ($prev_line =~ /^\"(.*)\"$/) {
                        push @{$it}, $1;
                    }
                    else{
                        $prev_line =~ s/\s+$//g;
                        if ($prev_line =~ /[\:\,\;\-\=]$/) { chop $prev_line;}
                        push @{$it}, $prev_line;
                    }
                }
                my @ar;
                push @{$it}, \@ar;
                if (do_parse($fh, \@{$it->[-1]}, 1, $brackets) <= 0) {return -1;}
            }
            else {
                @{$it->{$prev_line}} = ();
                if (do_parse($fh, \@{$it->{$prev_line}}, 1, $brackets) <= 0) {return -1;}
            }
            $is_first = 1;
            next;
        }
        if (/^\]/) {
            my $last = pop @{$brackets};
            unless ($last eq ']') {
                warn "Syntax error in config, check ] brackets\n";
                return -1;
            }
            if (!$is_first) {
                if ($prev_line =~ /^\s*\[\s*([^\f\n\r\t\v]*)\s*\]\,?\s*$/) {
                    my $value = $1;
                    my @ar = split (/, */, $value);
                    my $n = $#ar + 1;
                    for (my $i = 0; $i < $n; $i++) {
                        if ($ar[$i] =~ /^\"(.*)\"$/) {$ar[$i] = $1;}
                    }
                    push @{$it}, \@ar;
                    $is_first = 1;
                }
                elsif ($prev_line =~ /^\"(.*)\"$/) {
                    push @{$it}, $1;
                }
                else {
                    $prev_line =~ s/\s+$//g;
                    if ($prev_line =~ /[\:\,\;\-\=]$/) { chop $prev_line;}
                    push @{$it}, $prev_line;
                }
            }
            return 1;
        }
        if (/^\}/) {
            my $last = pop @{$brackets};
            unless ($last eq '}') {
                warn "Syntax error in config, check } brackets\n";
                return -1;
            }
            if ($is_first) {
                return 1;
            } else {
                warn "Syntax error in config, check {} or [] brackets\n";
                return -1;
            }
            next;
        }

        if (/^$/) {next;}
        if (/^\#/) {next;}
        if ($is_first) {
            $prev_line = $_;
            $is_first = 0;
            if (/^(\w+)[:]?\s*[\(\[]\s*([^\f\n\r\t\v]*)[\]\)]\,*\s*$/) {
                my $key = $1;
                my $value = $2;
                my @ar = split (/, */, $value);
                my $n = $#ar + 1;
                for (my $i = 0; $i < $n; $i++) {
                    if ($ar[$i] =~ /^\"(.*)\"$/) {$ar[$i] = $1;}
                }
                @{$it->{$key}} = @ar;
                $is_first = 1;
            }
            elsif (/^(\w+)[:]?\s*\{\s*([\s\,\w\(\),\:,\=,\>]*)\}\,?\s*$/) {
                print "unsupported type of hash, check your config\n";
                return -1;
            }
            elsif (/^(\w+)\s*\:\"?\s*(\S+)\s*\"?\s*\,?$/) {
                $it->{$1} = $2;
                $is_first = 1;
            }
            elsif (/^\s*\[\s*([^\f\n\r\t\v]*)\s*\]\,?\s*$/) {
                my $value = $1;
                my @ar = split (/, */, $value);
                my $n = $#ar + 1;
                for (my $i = 0; $i < $n; $i++) {
                    if ($ar[$i] =~ /^\"(.*)\"$/) {$ar[$i] = $1;}
                }
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
                if ($prev_line =~ /^\s*\[\s*([^\f\n\r\t\v]*)\s*\]\,?\s*$/) {
                    my $value = $1;
                    my @ar = split (/, */, $value);
                    my $n = $#ar + 1;
                    for (my $i = 0; $i < $n; $i++) {
                        if ($ar[$i] =~ /^\"(.*)\"$/) {$ar[$i] = $1;}
                    }
                    push @{$it}, \@ar;
                    $is_first = 1;
                }
                elsif ($prev_line =~ /^\"(.*)\"$/) {
                    push @{$it}, $1;
                }
                else {
                    $prev_line =~ s/\s+$//g;
                    if ($prev_line =~ /[\:\,\;\-\=]$/) { chop $prev_line;}
                    push @{$it}, $prev_line;
                }
                $prev_line = $_;
            } else {
                warn "Syntax error in config, check {} or [] brackets\n"; 
                return -1;
            }
        }
    }
    return 1;
}
sub parse_test_file {
    my $test_file = shift;
    my $result = shift;
    my $test_counter = shift;
 

    my $fh = new IO::File;
    unless ($fh->open("$test_file")) {
        die "file($test_file) with imap tests not found\n";
    }

    my @brackets;
    my %glhash;

    eval {
        if (do_parse($fh, \%glhash, 0, \@brackets) <= 0) {
            warn "ERROR in parsing\n";
            $fh->close();
            return -1;
        } else {
            my @ar = @{$glhash{test}};
            $$test_counter = $#ar + 1;
            %{$result} = %{$glhash{result}};
        }
    };
    if ($@) {
        warn "start server error, check your config file, $@\n";
    }

    $fh->close();
}


sub check_collector_params {
    my $db = shift;
    my $params = shift;

    $params->{"OldThreshold"} = time();
    $params->{"LastTime"} = time();

    unless (exists($params->{"UserEmail"}) or exists($params->{"UserID"})) {
        die "UserID or UserEmail must be set \n";
    }
    unless (exists($params->{"Email"}) and exists($params->{"Password"})) {
        die "Email and Password must be set \n";
    }

    unless (exists($params->{"UserID"})) {
        my $sth = $db->prepare('select ID from mPOP.user where Username=?');

        my $Username = $params->{"UserEmail"};
        if ($params->{"UserEmail"} =~ /^(\w+)\@mail\.ru$/) {
            $Username = $1;
        }

        $sth->execute($Username);
        $params->{"UserID"} = $sth->fetchrow_hashref()->{"ID"};
   } else {
        unless (exists($params->{"UserEmail"})) {
            my $sth = $db->prepare('select Username from mPOP.user where ID=?');
            $sth->execute($params->{"UserID"});
            my $result = $sth->fetchrow_hashref()->{"Username"};
            unless ($result =~ /^(\w+)\@mail\.ru$/) {
                $result .= "\@mail.ru";
            }
            $params->{"UserEmail"} = $result;
        }
    }
    unless (exists($params->{"Host"})) {
        $params->{"Host"} = "localhost";
    }

    unless (exists($params->{"User"})) {
        $params->{"User"} = $params->{"Email"};
    }
    unless (exists($params->{"EncPassword"})) {
        $params->{"EncPassword"} = "";
    }
    unless (exists($params->{"Flags"})) {
        $params->{"Flags"} = 22;
    }
    unless (exists($params->{"WaitTime"})) {
        $params->{"WaitTime"} = 0;
    }
    unless (exists($params->{"KeepTime"})) {
        $params->{"KeepTime"} = 0;
    }
    unless (exists($params->{"Time"})) {
        $params->{"Time"} = 0;
    }
    unless (exists($params->{"LastMsg"})) {
        $params->{"LastMsg"} = "+[Success]";
    }
    unless (exists($params->{"LastOK"})) {
        $params->{"LastOK"} = 0;
    }
    unless (exists($params->{"Port"})) {
        $params->{"Port"} = "8877";
    }
    unless (exists($params->{"ConnectionMode"})) {
        $params->{"ConnectionMode"} = "no-ssl";
    }
    unless (exists($params->{"AutoConfigure"})) {
        $params->{"AutoConfigure"} = "no";
    }
    unless (exists($params->{"ContactFetchRetries"})) {
        $params->{"ContactFetchRetries"} = 0;
    }
    unless (exists($params->{"Folder"})) {
        $params->{"Folder"} = "0";
    }
}

sub run_connect {
    my $host = shift;
    my $db_name = shift;
    my $user = shift;
    my $psw = shift;
    print "DB params: $db_name, $host, $user, $psw\n";
    my $dbh = DBI->connect("DBI:mysql:database=$db_name;host=$host",$user, $psw)
        or die "can't connect to mysql server\n";
    return $dbh;
}

sub create_collector {
# just INSERT to rpop.imap
    my $db = shift;
    my $UserID = shift;
    my $UserEmail = shift;
    my $Host = shift;
    my $User = shift;
    my $Password = shift;
    my $EncPassword = shift;
    my $Flags = shift;
    my $WaitTime = shift;
    my $Folder = shift;
    my $KeepTime = shift;
    my $Time = shift;
    my $LastTime = shift;
    my $LastMsg = shift;
    my $LastOK = shift;
    my $Port = shift;
    my $ConnectionMode = shift;
    my $Email = shift;
    my $AutoConfigure = shift;
    my $ContactFetchRetries = shift;
    my $OldThreshold = shift;

    print "Params: ".$UserID.", ".$UserEmail.", ".$Host.", ".$User.", ".$Password.", ".$EncPassword.", ".$Flags.", ".
                    $WaitTime.", ".$Folder.", ".$KeepTime.", ".$Time.", ".$LastTime.", ".$LastMsg.", ".$LastOK.", ".
                    $Port.", ".$ConnectionMode.", ".$Email.", ".$AutoConfigure.", ".$ContactFetchRetries.", ".
                    $OldThreshold."\n";

    my $sth = $db->prepare("INSERT INTO rpop.imap (UserID,  UserEmail, Host, User, Password , EncPassword,
                            Flags, WaitTime, Folder, KeepTime, Time, LastTime, LastMsg, LastOK, Port,
                            ConnectionMode,  Email,  AutoConfigure, ContactFetchRetries, OldThreshold)
                            values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
    $sth->execute($UserID, $UserEmail, $Host, $User, $Password , $EncPassword, $Flags,
                    $WaitTime, $Folder, $KeepTime, $Time, $LastTime, $LastMsg, $LastOK,
                    $Port, $ConnectionMode, $Email, $AutoConfigure, $ContactFetchRetries,
                    $OldThreshold) or die $DBI::errstr;
    print "creating collector: ".Dumper($sth->{mysql_insertid})."\n";
    $sth->finish();
    return $sth->{mysql_insertid};
}

sub delete_collector {
#just DELETE from rpop.imap

    my $db = shift;
    my $ID = shift;

    my $sth = $db->prepare("DELETE FROM rpop.imap WHERE  ID=?");
    $sth->execute($ID) or die $DBI::errstr;
    print "Number of rows deleted: ".$sth->rows."\n";
    $sth->finish();
}

sub select_from_db_table_by_UserEmail{
    my $dbh = shift;
    my $UserEmail = shift;
    my $statement = "select * from rpop.imap where UserEmail=?";

    my $sth = $dbh->prepare('select * from rpop.imap where UserEmail=?');
    $sth->execute($UserEmail);
    #my @result = $hash_ref->fetchrow_array();
    #print "select: ".Dumper(\@result)."\n";

    #while (my @row = $sth->fetchrow_array()) {
    #    print "row: ".Dumper(@row)."\n";
    #}

    my $result = $sth->fetchrow_hashref();
    $sth->finish();
}

sub select_from_db_table_by_ID{
    my $dbh = shift;
    my $ID = shift;
    my $statement = "select * from rpop.imap where ID=?";

    my $sth = $dbh->prepare('select * from rpop.imap where ID=?');
    $sth->execute($ID);

    my $result = $sth->fetchrow_hashref();
    $sth->finish();
}

sub my_exit {
    my ($db, $collector_id, $config) = @_;
    delete_collector($db, $collector_id);

    my $pid_file = ($config->{pid_file} ? $config->{pid_file}: "/tmp/server.pid");
    warn "pid_file = $pid_file\n";

    my $fh = IO::File->new("< $pid_file");
    if (defined $fh) {
        my $line = <$fh>;
        chomp $line;
        print "kill PID: $line\n";
        kill 9, $line;
    }
    $fh->close();
}

my %test_result1;
my $tests_amount = 0;
my $check_all = 0; #flag
my $link_to_tests_amount = \$tests_amount;
my $db = run_connect($parsed_args{'mysql_host'}, 'mysql', $parsed_args{'mysql_user'}, $parsed_args{'mysql_password'});
warn "Dumper1 => ".Dumper(\%parsed_args)."\n";
parse_imap_config(($parsed_args{"imap_config"}? $parsed_args{"imap_config"}: 'config.conf'),\%parsed_args);
warn "Dumper => ".Dumper(\%parsed_args)."\n";
 
check_collector_params($db,\%parsed_args);

my $collector_id = create_collector($db, $parsed_args{"UserID"}, $parsed_args{"UserEmail"},
                                    $parsed_args{"Host"}, $parsed_args{"User"}, $parsed_args{"Password"},
                                    $parsed_args{"EncPassword"},$parsed_args{"Flags"},$parsed_args{"WaitTime"},
                                    $parsed_args{"Folder"}, $parsed_args{"KeepTime"}, $parsed_args{"Time"},
                                    $parsed_args{"LastTime"}, $parsed_args{"LastMsg"}, $parsed_args{"LastOK"},
                                    $parsed_args{"Port"}, $parsed_args{"ConnectionMode"},$parsed_args{"Email"},
                                    $parsed_args{"AutoConfigure"}, $parsed_args{"ContactFetchRetries"},
                                    $parsed_args{"OldTreshold"});
select_from_db_table_by_UserEmail($db, 'ksd001@mail.ru');

if (defined $parsed_args{"test"}) {
    parse_test_file($parsed_args{"test"}, \%test_result1, $link_to_tests_amount);
    my $cmd = "./fake_imap_server.pm run  ".(defined $parsed_args{"imap_config"}? 
                    "--config=".$parsed_args{"imap_config"}: '--config=config.conf').
                    "  --test=".$parsed_args{"test"};
    system($cmd);
}
else {
    my_exit($db, $collector_id);
    die "file with test is undefined\n";
}

for (my $i = 0; $i < $tests_amount; $i++) {
    $cmd = "../BUILD/collector --proto=imap --fetch-id=$collector_id --log=imap -l 5";
    system($cmd);
}


eval {
    my $pUser = mPOP::Get()->GetUserFromID($parsed_args{"UserID"});
    my $mesc = $pUser->GetPMescalito;
    #warn "dumper: ".Dumper($pUser)."\n";
    my $ret = $mesc->GetFolders;
    my $msgs = $mesc->GetFolderMessages(0);
    warn Dumper(\@{$msgs});
    
    
    
    
    #my $pMescFolders = mPOP::MescFolders->new( $pUser->GetPMescalito );
    #warn "dumepr: ".Dumper($pMescFolders)."\n";
    #my $sorted_folders = $pMescFolders->GetSortedFolders;
    #warn "dumepr: ".Dumper($sorted_folders)."\n";

};
if ($@) {
    warn "mauu\n";
}
my_exit($db, $collector_id, \%imap_config);

1;
