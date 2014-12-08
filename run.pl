#!/usr/bin/perl -I/usr/local/mpop/lib/

use strict;
use IO::File;
use Switch;
use Data::Dumper;
use DBI;
use Time::HiRes qw(gettimeofday);
use IO::Socket;

use Mailbox;
use mPOP;
use mPOP::Domain (preload=>1);
use PMescalito();
use mPOP::MescFolders();

sub print_help {
    print "Usage:\n";
    print "    --test [-t] =</dir/test_file>\n";
    print "    --test_dir [-d] =<dir>\n";
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
            elsif (my @fields = $args =~ /^\-\-(\w+)\=\"\s*([\w\.\/@\-\= ]*)\"\s*$/g) {
                $parsed_args{$fields[0]} = $fields[1];
            }
            elsif ($args =~ /^\-[hplcts]$/g) {
                my $param = $args;
                if(defined ($_ = shift @ARGV) and (m/^([\w\.\/@]+)$/)) {
                    switch ($param) {
                        case '-t' { $param = 'test' }
                        case '-c' { $param = 'imap_config' }
                        case '-d' { $param = 'test_dir' }
                    }
                    $parsed_args{$param} = $_;
                }
                else {
                    warn "unrecognized param found (It should be like: '-p param_value' or '--param=param_value')\n";
                }
            }
            else {
                warn "unrecognized param found (It should be like: '-p param_value' or '--param=param_value')\n";
            }
            $args = shift @ARGV;
        }
    }
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
        $do_add = 1;
        if ($line =~ /^\s*(\w+)\s+\"?([\w\.\/\@ \-\=]*)\"?\s*$/) {
            #my $key = lc $1;
            my $key = $1;
            my $value = $2;
            unless (exists $result->{$key}) {
                $result->{$key} = $value;
            }
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
            elsif (/^(\w+)[:]?\s*\{\s*\}\s*$/) {
                $it->{$1} = "";
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
    my $tests = shift;
    my $fh = new IO::File;
    unless ($fh->open("$test_file")) {
        die "file($test_file) with imap tests not found\n";
    }

    my @brackets;
    my %glhash;

    eval {
        if (do_parse($fh, \%glhash, 0, \@brackets) <= 0) {
            warn "error in parsing test file\n";
            $fh->close();
            return -1;
        } else {
            if ($glhash{result}){
                %{$result} = %{$glhash{result}};
            }
            if ($glhash{test}) {
                @{$tests} = @{$glhash{test}};
            }
        }
    };
    if ($@) {
        warn "error in parsing test file, $@\n";
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
        $params->{"Flags"} = 534;#534; #22
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

sub clear_msg_table {
#just DELETE rows from rpop.imap_msg

    my $db = shift;
    my $CollectorId = shift;

    my $sth = $db->prepare("DELETE FROM rpop.imap_msg WHERE  CollectorId=?");
    $sth->execute($CollectorId) or die $DBI::errstr;
    print "Number of rows deleted: ".$sth->rows."\n";
    $sth->finish();
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

sub get_initial_rimap_state {
    my ($folders, $fuids, $matched_folders, $args) = @_;
    my $pUser = mPOP::Get()->GetUserFromID($args->{"UserID"});
    my $mesc = $pUser->GetPMescalito;
    $mesc->ClearFoldersCache;
    $folders = $mesc->GetFolders;
    %{$fuids} = ();
    foreach my $folder (@{$folders}) {
        $fuids->{$folder->{"id"}} = $mesc->GetFolderMessages($folder->{"id"});
    }

    my $old_length = scalar(@{$matched_folders});
    foreach my $folder (@{$folders}) {
        if ($old_length == 0) {
            push @{$matched_folders}, $folder->{name};
        }
        else {
            my $found = 0;
            foreach my $matched_folder (@{$matched_folders}) {
                if ($folder->{name} eq $matched_folder) {$found = 1;}
            }
            unless ($found) {
                    push @{$matched_folders}, $folder->{name};
            }
        }
    }
}

sub compare_msgs_in_fld {
    my ($msgs, $res_msgs, $args) = @_;
    my $fh = new IO::File;
    my $msg_file = ($args->{"message"} ? $args->{"message"}: "message.eml");
    my $msg_to = "";
    my $msg_from = "";
    my $msg_body = "";
    if ($fh->open("< $msg_file")){
        my $sp = 0;
        while (<$fh>) {
            chomp;
            chomp;
            if (/^From\:\s+(.+)/) {
                $msg_from = $1;
            }
            elsif (/^To\:\s+(.+)/) {
                $msg_to = $1;
            }
            elsif(!/^\w+\:/){
                if (length($_) == 0 and length($msg_body) > 0) {$msg_body .= " "; $sp = 1;}
                else {
                    if (!$sp and length($msg_body) > 0) {$msg_body .= " ";}
                    $msg_body .= $_;
                    $sp = 0;
                }
            }
        }
        $fh->close;
    }
    else {
        $msg_to = "bbbbb <bbbbb\@mail.ru>";
        $msg_from = "aaaaa <aaaaa\@mail.ru>";
        $msg_body = "This is just fake message For tests";
    }

    foreach my $uid (keys %{$res_msgs}) {
        my $found = 0;
        foreach my $msg (@{$msgs}) {
            if ($msg->{uidl} =~ /$uid$/) {
                unless ($msg->{microformat} =~ /$msg_body/ and
                    $msg->{to} eq $msg_to and $msg->{from} eq $msg_from) {
                    print "Error: msgs in folders mismatch! (or check your test file)\n";
                    return -1;
                }
                $found = 1;
                last;
            }
        }
        unless ($found) {
            print "Error: msgs in folders mismatch! (or check your test file)\n";
            return -1;
        }
    }
    return 1;
}

sub check_rimap_status {
    my ($result, $old_folders, $old_msgs_by_folder_id, $option, $mode, $matched_folders, $args) = @_;
    my $pUser = mPOP::Get()->GetUserFromID($args->{"UserID"});
    my $mesc = $pUser->GetPMescalito;
    $mesc->ClearFoldersCache;
    my $folders = $mesc->GetFolders;
    my %fuids = ();
    my $folder_id = $args->{"Folder"};
    unless ($result->{$option}) {
        warn "Error: result test part \"$option\" is not defined in test file";
        return -1;
    }

    my $res_inbox = "";
    my $rimap_inbox = "";
    foreach my $key (keys  %{$result->{$option}}) {
        if (lc $key eq "inbox") {
            $res_inbox = $key;
            last;
        }
    }
    foreach my $folder (@{$folders}) {
        if ($folder->{"id"} eq $args->{"Folder"}) {
            $rimap_inbox = $folder->{"name"};
            last;
        }
    }

    if ($mode eq "fetch") {
        my $res_folder = "";
        foreach my $folder (@{$folders}) {
            my $found = 0;
            if ($folder->{name} eq $rimap_inbox and length($res_inbox) > 0) {
                $found = 1;
                $res_folder = $res_inbox;
            }
            else {
                foreach my $key (keys %{$result->{$option}}) {
                    if ($folder_id eq "0") {
                        if ($folder->{name} =~ /^$key$/) {$found = 1;}
                    }
                    elsif ($folder->{name} =~ /(.*)$key$/) {
                        if ($1 =~ /$folder_id/) {
                            $found = 1;
                            $res_folder = $key;
                            last;
                        }
                    }
                }
            }
            if ($found) {
                my $msgs = $mesc->GetFolderMessages($folder->{id});
                my $new_msgs = [];
                foreach my $msg(@{$msgs}) {
                    $found = 0;
                    foreach my $old_msg (@{$old_msgs_by_folder_id->{$folder->{id}}}) {
                        if ($old_msg->{uidl} eq $msg->{uidl}) {
                            $found = 1;
                            last;
                        }
                    }
                    unless ($found) {
                        push @{$new_msgs}, $msg;
                    }
                }
                if (compare_msgs_in_fld($new_msgs, $result->{$option}->{$res_folder}->{uids}, $args) <= 0) {
                    print "\x1b[31mTest FAILED:\x1b[0m  msg fetch error (check: result->{$option}, folder: ".$folder->{name}.")\n";
                    return -1;
                }
            }
        }
    }
    else {
        foreach my $matched_folder (@{$matched_folders}) {
            my $found = 0;
            my $cur_res_folder = "";
            if ($matched_folder eq $rimap_inbox and length($res_inbox) > 0) {
                $cur_res_folder = $res_inbox;
                $found = 1;
            }
            else {
                foreach my $res_folder (keys %{$result->{$option}}) {
                    foreach my $flag (@{$result->{$option}->{$res_folder}->{flags}}) {
                        if (lc $flag eq "sent" and $matched_folder eq "sent" or lc $flag eq "drafts" and $matched_folder eq "drafts" or lc $flag eq "spam" and $matched_folder eq "spam" or lc $flag eq "trash" and $matched_folder eq "trash") {
                            $found = 1;
                            last;
                        }
                    }
                    if ($folder_id eq "0") {
                        if ($matched_folder =~ /^$res_folder$/) {$found = 1;}
                    }
                    elsif ($matched_folder =~ /(.*)$res_folder$/) {
                        if ($1 =~ /$folder_id/) {$found = 1;}
                    }
                    if ($found) {
                        $cur_res_folder = $res_folder;
                        last;
                    }
                }
            }

            if ($found) {
                $found = 0;
                my $fld;
                foreach my $folder (@{$folders}) {
                    $fld = $folder->{name};
                    if ($folder->{name} eq $matched_folder) {
                        $found = 1;
                        if (compare_msgs_in_fld($mesc->GetFolderMessages($folder->{id}), $result->{$option}->{$cur_res_folder}->{uids}, $args) <= 0) {
                            print "\x1b[31mTest FAILED:\x1b[0m sync of msgs in folder ".$folder->{name}." failed, (check: result->{$option}, folder: $matched_folder)\n";
                            return -1;
                        }
                    }
                    #системные папки игнорируются
                    if ($fld eq "sent" or $fld eq "drafts" or $fld eq "spam" or $fld eq "trash" or $fld eq "inbox") {$found = 1;}
                }
                unless ($found) {
                    print "\x1b[31mTest FAILED:\x1b[0m  folder ".$fld->{name}." rimap folder is absent! (check: result->{$option}, folder: $matched_folder)\n";
                    return -1;
                }
            }
            else {
                foreach my $folder (@{$folders}) {
                    if ($folder eq "sent" or $folder eq "drafts" or $folder eq "spam" or $folder eq "trash" or $folder eq "inbox") {next;}
                    if ($folder->{name} =~  /^\d+$matched_folder$/) {
                        print "\x1b[31mTest FAILED:\x1b[0m  folder ".$folder->{name}." should have been deleted during sync, (check: result->{$option}, folder: ".$folder->{name}.")\n";
                        return -1;
                    }
                }
            }
        }
    }
    return 1;
}

sub get_folders {
    my $matched_folders = shift;
    my $current_test = shift;
    my $args = shift;
    my $pUser = mPOP::Get()->GetUserFromID($args->{"UserID"});
    my $mesc = $pUser->GetPMescalito;
    $mesc->ClearFoldersCache;
    my $folders = $mesc->GetFolders;
    my $folder_id = $args->{"Folder"};

    my $old_length = scalar(@{$matched_folders});
    my $found;
    foreach my $folder (@{$folders}) {
        $found = 0;
        if ($folder->{name} ~~ $matched_folders) {next;}
        if ($folder_id == $folder->{id}) {
            push @{$matched_folders}, $folder->{name};
            next;
        }
        foreach my $res_folder (keys %{$current_test}) {
            if ($folder->{name} eq "sent" or $folder->{name} eq "drafts" or $folder->{name} eq "spam" or $folder->{name} eq "trash" or $folder->{name} eq "inbox") {

                foreach my $flag (@{$current_test->{$res_folder}->{flags}}) {
                    if (lc $flag eq "sent" and $folder->{name} eq "sent" or lc $flag eq "drafts" and $folder->{name} eq "drafts" or lc $flag eq "spam" and $folder->{name} eq "spam" or lc $flag eq "trash" and $folder->{name} eq "trash")
                    {$found = 1; last;}
                }
            }
            elsif ($folder_id == 0) {
                if ($folder->{name} =~ /^$res_folder$/) {$found = 1; last;}
            }
            else {
                my $regex = ''.$folder_id.$res_folder;
                my $name = ''.$folder->{name};
                use Data::Dumper;
                if ($name =~ /(.*)$res_folder$/) {
                    if ($1 =~ /$folder_id/) {
                        $found = 1;
                        last;
                    }
                }
            }
        }
        if ($found) {
            push @{$matched_folders}, $folder->{name};
        }
    }
}

sub check_for_extra_fake_imap_server {
    #check if another Fake Imap Server is working, and stopping it
    my $a = `ps waux | grep fake | grep /usr/bin/perl | grep -v ps`;
    print $a;
    my @ar = split (/\s+/,$a);
    unless (scalar(@ar) == 0) {
        print "kill PID: ".$ar[1]."\n";
        kill 9, $ar[1];
    }
}

sub my_exit {
    my ($db, $collector_id, $config) = @_;
    delete_collector($db, $collector_id);
    clear_msg_table($db, $collector_id);

    my $pid_file = ($config->{pid_file} ? $config->{pid_file}: "/tmp/fake_imap_server.pid");
    my $fh = IO::File->new("< $pid_file");
    if (defined $fh) {
        my $line = <$fh>;
        chomp $line;
        print "kill PID: $line\n";
        kill 9, $line;
        $fh->close();
    }
        unlink "connect.txt";
}

check_for_extra_fake_imap_server();
my $db = run_connect($parsed_args{'mysql_host'}, 'mysql', $parsed_args{'mysql_user'}, $parsed_args{'mysql_password'});
parse_imap_config(($parsed_args{"imap_config"}? $parsed_args{"imap_config"}: 'config.conf'),\%parsed_args);
check_collector_params($db,\%parsed_args);
if (!$parsed_args{"test"} and !$parsed_args{"test_dir"}) {
    print "Test files not found!";
    exit;
}

my @files = ();
if ($parsed_args{"test"}) {
    if (open(FH, "< ".$parsed_args{"test"})) {
        close(FH);
        push @files, $parsed_args{"test"};
    }
    else {
        print "Error: single test does not exist\n";
        exit;
    }
}
else {
    opendir DIR, $parsed_args{"test_dir"} or die $!;
    while(my $fname = readdir DIR) {
        if ($fname =~ /^test/) { push @files, $parsed_args{"test_dir"}."/".$fname; }
    }
    closedir DIR;
}
my $test_failed = 0;
my $test_passed = 0;
my $test_files = $#files + 1;
my @failed_files = ();
my $run_pl_path = (($0 =~ /(.*)run\.pl$/)? $1: "");
$run_pl_path =~ s/\.\///;

foreach my $test_file (@files) {
    my %test_result = ();
    my @tests = ();
    my $tests_amount = 0;
    my $pid_file = ($parsed_args{"pid_file"} ? $parsed_args{"pid_file"}: "/tmp/fake_imap_server.pid");

    parse_test_file($test_file, \%test_result, \@tests);
    $tests_amount = $#tests + 1;
    my $cmd = ($parsed_args{"fake_imap_server_exec"}? $parsed_args{"fake_imap_server_exec"}: "./$run_pl_path/fake_imap_server.pm")."  run  ".
                    (defined $parsed_args{"imap_config"}? "--config=".$parsed_args{"imap_config"}: "--config=./$run_pl_path/config.conf").
                    "  --test=".$test_file;
    system($cmd);
    my $ping_retries = ($parsed_args{"ping_retries"} ? $parsed_args{"ping_retries"}: 5);

    my $connected = 0;
    for (my $j = 0; $j < $ping_retries; ++$j) {
        $| = 1;

        my $socket = new IO::Socket::INET (
                            PeerHost => $parsed_args{"host"},
                            PeerPort => $parsed_args{"port"},
                            Proto => 'tcp',
                        );
        if ($socket) {
            my $response = "";
            $socket->recv($response, 1024);
            if ($response =~ /OK Welcome to Fake Imap Server/) {
                print "Connected to Fake Imap Server: $response\n";
                $socket->send("ping");
                $connected = 1;
                $socket->close();
                last;
            }
            $socket->close();
        }
    }
    if ($connected <= 0) {
        print "Something wrong with Fake Imap Server \n";
        exit;
    }

    my $collector_id = create_collector($db, $parsed_args{"UserID"}, $parsed_args{"UserEmail"},
                                        $parsed_args{"Host"}, $parsed_args{"User"}, $parsed_args{"Password"},
                                        $parsed_args{"EncPassword"},$parsed_args{"Flags"},$parsed_args{"WaitTime"},
                                        $parsed_args{"Folder"}, $parsed_args{"KeepTime"}, $parsed_args{"Time"},
                                        $parsed_args{"LastTime"}, $parsed_args{"LastMsg"}, $parsed_args{"LastOK"},
                                        $parsed_args{"Port"}, $parsed_args{"ConnectionMode"},$parsed_args{"Email"},
                                        $parsed_args{"AutoConfigure"}, $parsed_args{"ContactFetchRetries"},
                                        $parsed_args{"OldTreshold"});
    select_from_db_table_by_UserEmail($db, 'ksd001@mail.ru');

    my %old_uids_by_fld = ();
    my @old_flds = ();
    my @matched_folders = ();
    my $mode = ($parsed_args{"Flags"} & 1<<9 ? "sync": "fetch");
    my $is_test_failed = 0;
    if ($mode eq "fetch") {get_initial_rimap_state (\@old_flds, \%old_uids_by_fld, \@matched_folders, \%parsed_args);}

    for (my $i = 0; $i < $tests_amount; $i++) {

        print "\x1b[35mStart test $test_file [$i]\x1b[0m \n";
        my $cmd = "";
        if ($parsed_args{"exec"}) {$cmd = $parsed_args{"exec"}." --fetch-id=$collector_id";}
        else {$cmd = "../BUILD/collector --proto=imap --fetch-id=$collector_id --log=imap -l 5";}
        system($cmd);

        get_folders(\@matched_folders, $tests[$i], \%parsed_args);
        if ($test_result{$i + 1}) {
            if (check_rimap_status(\%test_result, \@old_flds, \%old_uids_by_fld, $i + 1, $mode, \@matched_folders, \%parsed_args) <= 0) {
                $is_test_failed = 1;
                print "\x1b[31mTest: $test_file\x1b[0m \n";
                last;
            }
            else {
                print "\x1b[32mTest passed\x1b[0m \n";
                print "\x1b[32mTest: $test_file\x1b[0m \n";
            }
            if ($mode eq "fetch") {get_initial_rimap_state (\@old_flds, \%old_uids_by_fld,\@matched_folders, \%parsed_args);}
        }
    }
    if ($is_test_failed) {
        my_exit($db, $collector_id, \%parsed_args);
        $test_failed++;
        push @failed_files, $test_file;
        next;
    }
    if(check_rimap_status(\%test_result, \@old_flds, \%old_uids_by_fld, "total", $mode, \@matched_folders,\%parsed_args) <= 0) {
        $test_failed++;
        push @failed_files, $test_file;
        print "\x1b[31mTest: $test_file\x1b[0m \n";
    }
    else {
        $test_passed++;
        print "\x1b[32mTest passed\x1b[0m \n";
        print "\x1b[32mTest: $test_file\x1b[0m \n";
    }
    my_exit($db, $collector_id, \%parsed_args);
}
if ($test_passed == $test_files) {
    print "\x1b[32mAll tests passed successfully: $test_files/$test_files\x1b[0m \n";
    print "Result PASS\n";
}
if ($test_failed) {
    print "\x1b[31mFailed test: $test_failed/$test_files\x1b[0m \n";
    print "\x1b[31mFailed tests: \x1b[0m \n";
    foreach my $failed_file (@failed_files) {
        print "\x1b[31m    $failed_file\x1b[0m \n";
    }
    print "Result FAIL\n";
}
1;
