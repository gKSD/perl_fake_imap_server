#!/usr/bin/perl -I/home/sofia/mailru/perl_fake_imap_server

use FakeImapServer;

our $fake_imap_server = FakeImapServer->new(conf_file => 'config.conf');

$fake_imap_server->run();

1;
