#!/usr/bin/perl -I/home/sofia/mailru/perl_fake_imap_server

=begin
use FakeImapServer;

our $fake_imap_server = FakeImapServer->new(conf_file => 'config.conf');

$fake_imap_server->run();
=cut

use fake_imap_server;

our $fake_imap_server = fake_imap_server->new(conf_file => 'config.conf',
                                                aaaa => 'ddd.ddd');
$fake_imap_server->run();

1;
