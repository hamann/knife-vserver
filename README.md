# Knife::Vserver

## A knife plugin to manage Linux-VServer containers

This is a plugin for [Chef's](http://www.opscode.com/chef) [knife](http://docs.opscode.com/knife.html) tool.

## Installation

Add this line to your application's Gemfile:

    gem 'knife-vserver', :git => "git://github.com/hamann/knife-vserver.git"

And then execute:

    $ bundle

## Overview

Please execute `knife vserver sub-command --help` to see available options in detail.

This plugin provides the following sub-commands:

* knife vserver list QUERY (options)

Uses Chef Server to list all available containers on nodes returned by the query. If option `-m` is set, QUERY is a list of comma seperated hostnames and Chef isn't needed in that case

* knife vserver create SERVER (options)

* knife vserver delete SERVER (options)

* knife vserver modify memory SERVER (options)

* knife vserver add address SERVER (options)

* knife vserver remove address SERVER (options)

* knife vserver start SERVER (options)

* knife vserver stop SERVER (options)

## Requirements and details

This plugin was developed and tested on Debian (squeeze/wheezy)

* Recent Linux VServer Kernel on hosts
* Recent `util-vserver` version
* all commands are executed by SSH
* IP addresses are assigned to `dummy` interfaces
* Memory modification and adding/removing addresses will be synced with vserver configuration files


## Usage

A few examples:

List all available containers

```sh
$ knife vserver list "chef_environment:production"
```
Create a container on server containerhost.example.net with 1024 MB Ram, 2048 MB Swap and some IP addresses

```sh
$ knife vserver create containerhost.example.net -C testcontainer1 \ 
  -H 'testcontainer1.example.net' -R 1024 -S 2048 -I "10.20.20.2/26,172.30.0.1/16"
```
modify its memory settings

```sh
$ knife vserver modify memory containerhost.example.net -C testcontainer1 \
  -R 2048 -S 4096
```
add an aditional IP Address

```sh
$ knife vserver add address containerhost.example.net -C testcontainer1 \
  -I "192.168.100.2/24"
```
and remove it 

```sh
$ knife vserver remove address containerhost.example.net -C testcontainer1 \
  -I "192.168.100.2/24"
```



## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
