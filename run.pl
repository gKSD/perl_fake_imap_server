#!/usr/bin/perl

package Net::Server::FakeImapServer;

our $fake_imap_server = Net::Server::FakeImapServer->new(conf_file => 'config.conf');

$server->run();

1;
